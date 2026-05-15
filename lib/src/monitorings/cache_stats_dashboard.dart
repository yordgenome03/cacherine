import 'cache_metrics.dart';

/// Immutable point-in-time snapshot of all cache metrics.
class DashboardSnapshot {
  final double hitRate;
  final double missRate;
  final Duration averageLatency;
  final Duration p50Latency;
  final Duration p95Latency;
  final Duration p99Latency;
  final int evictionsPerMinute;
  final int totalRequests;
  final DateTime capturedAt;

  DashboardSnapshot({
    required this.hitRate,
    required this.missRate,
    required this.averageLatency,
    required this.p50Latency,
    required this.p95Latency,
    required this.p99Latency,
    required this.evictionsPerMinute,
    required this.totalRequests,
    required this.capturedAt,
  });
}

/// Wraps a [CacheMetrics] instance to provide typed snapshots and periodic streaming.
class CacheStatsDashboard {
  final CacheMetrics metrics;

  CacheStatsDashboard(this.metrics);

  /// Captures a point-in-time snapshot of all metrics.
  ///
  /// [window] controls only the eviction-rate calculation (passed to
  /// [CacheMetrics.getRecentStats]). Hit rate, miss rate, latency percentiles,
  /// and [totalRequests] are cumulative counters maintained by [CacheMetrics]
  /// and are not scoped to [window].
  ///
  /// Throws [ArgumentError] if [window] is zero or negative.
  DashboardSnapshot snapshot(Duration window) {
    final stats = metrics.getRecentStats(window);
    return DashboardSnapshot(
      hitRate: metrics.hitRate,
      missRate: metrics.missRate,
      averageLatency: metrics.averageLatency,
      p50Latency: metrics.getLatencyPercentile(50),
      p95Latency: metrics.getLatencyPercentile(95),
      p99Latency: metrics.getLatencyPercentile(99),
      evictionsPerMinute: stats['evictions_per_minute'] as int,
      totalRequests: metrics.totalRequests,
      capturedAt: DateTime.now(),
    );
  }

  /// Returns a [Stream] that emits a [DashboardSnapshot] every [interval].
  ///
  /// The stream is unbounded; callers must cancel the [StreamSubscription] to stop it.
  ///
  /// Throws [ArgumentError] if [interval] is zero or negative.
  Stream<DashboardSnapshot> stream(Duration window, Duration interval) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'must be positive');
    }
    return Stream.periodic(interval, (_) => snapshot(window));
  }
}

String _formatDuration(Duration d) {
  final us = d.inMicroseconds;
  if (us < 1000) return '$usµs';
  if (us < 1000000) return '${d.inMilliseconds}ms';
  return '${(us / 1000000).toStringAsFixed(1)}s';
}

/// Renders [snap] as a Unicode box-drawing text panel suitable for terminal or log output.
String formatDashboard(DashboardSnapshot snap) {
  const innerWidth = 61;
  const contentWidth = innerWidth - 2;

  final filled = (snap.hitRate * 20).round();
  final empty = 20 - filled;
  final bar = '${'█' * filled}${'░' * empty}';
  final hitRatePct = '${(snap.hitRate * 100).toStringAsFixed(1)}%';

  final dt = snap.capturedAt;
  final capturedAt =
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  String row(String content) => '│ ${content.padRight(contentWidth)} │';
  final sep = '├${'─' * innerWidth}┤';
  final topTitle = '─── Cacherine Dashboard Snapshot ';
  final top = '┌$topTitle${'─' * (innerWidth - topTitle.length)}┐';
  final bottom = '└${'─' * innerWidth}┘';

  return [
    top,
    row('Captured at: $capturedAt'),
    sep,
    row('Traffic:     ${snap.totalRequests} requests'),
    row('Hit Rate:    $hitRatePct  [$bar]'),
    sep,
    row(
      'Latency:     P50: ${_formatDuration(snap.p50Latency)}'
      ' / P95: ${_formatDuration(snap.p95Latency)}'
      ' / P99: ${_formatDuration(snap.p99Latency)}',
    ),
    row('Evictions:   ${snap.evictionsPerMinute} / min'),
    bottom,
  ].join('\n');
}
