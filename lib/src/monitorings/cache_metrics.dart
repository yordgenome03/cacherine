import 'dart:collection';

import 'eviction_reason.dart';

/// Typed point-in-time snapshot of cache metrics.
class CacheMetricsSnapshot {
  final double hitRate;
  final double missRate;
  final Duration averageLatency;
  final Duration p50Latency;
  final Duration p95Latency;
  final Duration p99Latency;
  final int evictionsPerMinute;

  /// Eviction rate broken out by [EvictionReason], additive alongside the
  /// aggregate [evictionsPerMinute]. Reasons with zero recent evictions are
  /// omitted.
  final Map<EvictionReason, int> evictionsPerMinuteByReason;
  final int totalRequests;
  final DateTime capturedAt;

  CacheMetricsSnapshot({
    required this.hitRate,
    required this.missRate,
    required this.averageLatency,
    required this.p50Latency,
    required this.p95Latency,
    required this.p99Latency,
    required this.evictionsPerMinute,
    required this.totalRequests,
    required this.capturedAt,
    Map<EvictionReason, int> evictionsPerMinuteByReason = const {},
  }) : evictionsPerMinuteByReason = Map.unmodifiable(
         evictionsPerMinuteByReason,
       );
}

class _EvictionRecord {
  final DateTime at;
  final EvictionReason reason;
  const _EvictionRecord(this.at, this.reason);
}

/// Cache performance metrics class
///
/// This class tracks cache hit rates, miss rates, request latencies (delays),
/// and eviction events. It provides the data necessary to measure and check
/// cache performance over time.
///
/// **Bounded storage**: latency samples are kept in a rolling window of the
/// most recent [maxLatencySamples] (1 000) entries, and eviction timestamps
/// are kept in a rolling window of the most recent [maxEvictionSamples]
/// (10 000) entries. This prevents unbounded heap growth in long-running
/// caches. As a result, [averageLatency] and [getLatencyPercentile] reflect
/// only the most recent 1 000 requests (hits and misses), and [getRecentStats] eviction counts are
/// accurate only while the requested window fits within the retained eviction
/// history.
class CacheMetrics {
  static const int maxLatencySamples = 1000;
  static const int maxEvictionSamples = 10000;

  final DateTime Function() _clock;

  int _hits = 0;
  int _misses = 0;
  int _totalRequests = 0;
  final Queue<Duration> _latencies = Queue();
  final Queue<_EvictionRecord> _evictions = Queue();

  /// Creates a metrics collector.
  ///
  /// [clock] defaults to [DateTime.now] and can be injected in tests to make
  /// time-window calculations deterministic.
  CacheMetrics({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// The number of cache hits
  int get hits => _hits;

  /// The number of cache misses
  int get misses => _misses;

  /// The total number of requests to the cache
  int get totalRequests => _totalRequests;

  /// Cache hit rate (the ratio of hits to total requests)
  double get hitRate => _totalRequests == 0 ? 0 : _hits / _totalRequests;

  /// Cache miss rate (the ratio of misses to total requests)
  double get missRate => _totalRequests == 0 ? 0 : _misses / _totalRequests;

  /// Average request latency
  Duration get averageLatency {
    if (_latencies.isEmpty) return Duration.zero;
    final total = _latencies.fold(Duration.zero, (a, b) => a + b);
    return Duration(microseconds: total.inMicroseconds ~/ _latencies.length);
  }

  /// Get the latency for a given percentile (e.g., 95th percentile)
  Duration getLatencyPercentile(double percentile) {
    if (_latencies.isEmpty) return Duration.zero;
    final sorted = List.of(_latencies)..sort();
    return _latencyPercentile(sorted, percentile);
  }

  /// Records a cache hit with the given request latency.
  /// [latency] is the [Duration] representing the request's latency.
  void recordHit(Duration latency) {
    _hits++;
    _totalRequests++;
    if (_latencies.length >= maxLatencySamples) _latencies.removeFirst();
    _latencies.add(latency);
  }

  /// Records a cache miss with the given request latency.
  /// [latency] is the [Duration] representing the request's latency.
  /// Latency is recorded for every request (hit or miss).
  void recordMiss(Duration latency) {
    _misses++;
    _totalRequests++;
    if (_latencies.length >= maxLatencySamples) _latencies.removeFirst();
    _latencies.add(latency);
  }

  /// Records a cache eviction event without a specific cause, bucketed as
  /// [EvictionReason.unspecified].
  ///
  /// Kept as a genuine zero-argument method — rather than giving
  /// [recordEvictionReason] an optional parameter — because `CacheMetrics` is
  /// public and non-final: an optional parameter would be source-breaking
  /// for a downstream subclass overriding this method with the original
  /// zero-argument signature (Dart rejects an override with fewer
  /// parameters than the method it overrides).
  void recordEviction() => recordEvictionReason(EvictionReason.unspecified);

  /// Records a cache eviction event caused by [reason], so it can be broken
  /// out in [CacheMetricsSnapshot.evictionsPerMinuteByReason].
  void recordEvictionReason(EvictionReason reason) {
    if (_evictions.length >= maxEvictionSamples) _evictions.removeFirst();
    _evictions.add(_EvictionRecord(_clock(), reason));
  }

  /// Captures a typed point-in-time snapshot within a given time window.
  ///
  /// Throws [ArgumentError] if [window] is zero or negative.
  CacheMetricsSnapshot snapshot(Duration window) {
    if (window.inMicroseconds <= 0) {
      throw ArgumentError(
        'window must be a positive Duration, but was $window',
      );
    }
    final now = _clock();
    final windowStart = now.subtract(window);
    final recentEvictions = _evictions
        .where((e) => e.at.isAfter(windowStart))
        .toList();
    final byReason = <EvictionReason, int>{};
    for (final e in recentEvictions) {
      byReason[e.reason] = (byReason[e.reason] ?? 0) + 1;
    }
    final perMinuteByReason = byReason.map(
      (reason, count) => MapEntry(
        reason,
        (count * Duration.microsecondsPerMinute) ~/ window.inMicroseconds,
      ),
    );
    final sortedLatencies = List.of(_latencies)..sort();
    return CacheMetricsSnapshot(
      hitRate: hitRate,
      missRate: missRate,
      averageLatency: averageLatency,
      p50Latency: _latencyPercentile(sortedLatencies, 50),
      p95Latency: _latencyPercentile(sortedLatencies, 95),
      p99Latency: _latencyPercentile(sortedLatencies, 99),
      evictionsPerMinute:
          (recentEvictions.length * Duration.microsecondsPerMinute) ~/
          window.inMicroseconds,
      evictionsPerMinuteByReason: perMinuteByReason,
      totalRequests: totalRequests,
      capturedAt: now,
    );
  }

  /// Retrieves the recent cache statistics within a given time window.
  ///
  /// Prefer [snapshot] for typed access. This method is retained for backward
  /// compatibility.
  ///
  /// Throws [ArgumentError] if [window] is zero or negative.
  Map<String, dynamic> getRecentStats(Duration window) {
    final snap = snapshot(window);
    return {
      'hit_rate': snap.hitRate,
      'miss_rate': snap.missRate,
      'average_latency': snap.averageLatency.inMilliseconds,
      'p50_latency': snap.p50Latency.inMilliseconds,
      'p95_latency': snap.p95Latency.inMilliseconds,
      'p99_latency': snap.p99Latency.inMilliseconds,
      'evictions_per_minute': snap.evictionsPerMinute,
    };
  }

  /// Resets all cache metrics to their initial state.
  void reset() {
    _hits = 0;
    _misses = 0;
    _totalRequests = 0;
    _latencies.clear();
    _evictions.clear();
  }

  Duration _latencyPercentile(List<Duration> sorted, double percentile) {
    if (sorted.isEmpty) return Duration.zero;
    final index = ((sorted.length - 1) * percentile / 100).toInt();

    // For 50th percentile (median), take the average of two middle values when even
    if (percentile == 50 && sorted.length % 2 == 0) {
      final mid1 = sorted[sorted.length ~/ 2 - 1];
      final mid2 = sorted[sorted.length ~/ 2];
      return Duration(
        milliseconds: (mid1.inMilliseconds + mid2.inMilliseconds) ~/ 2,
      );
    }

    return sorted[index];
  }
}
