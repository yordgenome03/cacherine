/// Cache performance metrics class
///
/// This class tracks cache hit rates, miss rates, request latencies (delays),
/// and eviction events. It provides the data necessary to measure and check
/// cache performance over time.
class CacheMetrics {
  int _hits = 0;
  int _misses = 0;
  int _totalRequests = 0;
  final List<Duration> _latencies = [];
  final List<DateTime> _evictions = [];

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

  /// Records a cache hit with the given request latency.
  /// [latency] is the [Duration] representing the request's latency.
  void recordHit(Duration latency) {
    _hits++;
    _totalRequests++;
    _latencies.add(latency);
  }

  /// Records a cache miss
  void recordMiss() {
    _misses++;
    _totalRequests++;
  }

  /// Records a cache eviction event
  void recordEviction() {
    _evictions.add(DateTime.now());
  }

  /// Retrieves the recent cache statistics within a given time window.
  Map<String, dynamic> getRecentStats(Duration window) {
    final now = DateTime.now();
    final windowStart = now.subtract(window);
    final recentEvictions =
        _evictions.where((t) => t.isAfter(windowStart)).length;
    return {
      'hit_rate': hitRate,
      'miss_rate': missRate,
      'average_latency': averageLatency.inMilliseconds,
      'p95_latency': getLatencyPercentile(95).inMilliseconds,
      'p99_latency': getLatencyPercentile(99).inMilliseconds,
      'evictions_per_minute':
          (recentEvictions * 60000) ~/ window.inMilliseconds,
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
}
