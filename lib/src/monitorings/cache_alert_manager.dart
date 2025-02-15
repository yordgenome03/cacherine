import 'dart:async';
import 'cache_metrics.dart';

/// Cache alert management class
///
/// This class monitors cache performance and triggers alerts when the user-defined
/// thresholds are exceeded. It periodically checks cache statistics, provided by
/// the [CacheMetrics] class, and sends alerts based on the configuration.
class CacheAlertManager {
  final CacheMetrics metrics;
  final CacheAlertConfig config;

  /// Initializes the alert manager.
  /// [metrics] is an instance of [CacheMetrics] that tracks cache performance,
  /// and [config] is an instance of [CacheAlertConfig] that configures the alert thresholds and notifications.
  CacheAlertManager(this.metrics, this.config);

  /// Periodically monitors cache performance at the interval specified in [config].
  void monitor() {
    Timer.periodic(config.alertCheckInterval, (_) {
      final stats = metrics.getRecentStats(config.alertCheckInterval);
      _checkAlerts(stats);
    });
  }

  /// Checks the cache statistics and triggers alerts if any thresholds are exceeded.
  void _checkAlerts(Map<String, dynamic> stats) {
    if (stats['hit_rate'] as double < config.hitRateThreshold) {
      config.notifyCallback('Warning: Low hit rate detected. '
          'Actual: ${stats['hit_rate']} (Threshold: ${config.hitRateThreshold})');
    }
    if (stats['miss_rate'] as double > config.missRateThreshold) {
      config.notifyCallback('Warning: High miss rate detected. '
          'Actual: ${stats['miss_rate']} (Threshold: ${config.missRateThreshold})');
    }
    if ((stats['p95_latency'] as num).toInt() > config.p95LatencyThreshold) {
      config.notifyCallback('Warning: High p95 latency detected. '
          'Actual: ${stats['p95_latency']}ms (Threshold: ${config.p95LatencyThreshold}ms)');
    }
    if ((stats['p99_latency'] as num).toInt() > config.p99LatencyThreshold) {
      config.notifyCallback('Warning: High p99 latency detected. '
          'Actual: ${stats['p99_latency']}ms (Threshold: ${config.p99LatencyThreshold}ms)');
    }
    if ((stats['average_latency'] as num).toInt() >
        config.averageLatencyThreshold) {
      config.notifyCallback('Warning: High average latency detected. '
          'Actual: ${stats['average_latency']}ms (Threshold: ${config.averageLatencyThreshold}ms)');
    }
    if ((stats['evictions_per_minute'] as num).toInt() >
        config.evictionsPerMinuteThreshold) {
      config.notifyCallback('Warning: High eviction rate detected. '
          'Actual: ${stats['evictions_per_minute']} evictions/min '
          '(Threshold: ${config.evictionsPerMinuteThreshold} evictions/min)');
    }
  }
}

/// Cache alert configuration class
///
/// This class configures thresholds and notification settings for cache performance alerts.
class CacheAlertConfig {
  final void Function(String) notifyCallback;
  final double hitRateThreshold;
  final double missRateThreshold;
  final int p95LatencyThreshold;
  final int p99LatencyThreshold;
  final int evictionsPerMinuteThreshold;
  final int averageLatencyThreshold;
  final Duration alertCheckInterval;

  /// Initializes the alert configuration.
  ///
  /// [notifyCallback] is the function used to notify about alerts,
  /// the various thresholds set user-defined limits for performance metrics,
  /// and [alertCheckInterval] sets the interval for checking alerts.
  CacheAlertConfig({
    required this.notifyCallback,
    this.hitRateThreshold = 0.5,
    this.missRateThreshold = 0.5,
    this.p95LatencyThreshold = 200,
    this.p99LatencyThreshold = 300,
    this.evictionsPerMinuteThreshold = 1000,
    this.averageLatencyThreshold = 100,
    this.alertCheckInterval =
        const Duration(minutes: 1), // Default check every minute
  });
}
