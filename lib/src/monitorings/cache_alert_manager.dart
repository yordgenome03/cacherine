import 'dart:async';
import 'cache_metrics.dart';
import 'eviction_reason.dart';

void _noopAlertCallback(String _) {}

/// Cache alert management class
///
/// This class monitors cache performance and triggers alerts when the user-defined
/// thresholds are exceeded. It periodically checks cache statistics, provided by
/// the [CacheMetrics] class, and sends alerts based on the configuration.
class CacheAlertManager {
  final CacheMetrics metrics;
  final CacheAlertConfig config;

  Timer? _timer;
  bool _isDisposed = false;

  /// Initializes the alert manager.
  /// [metrics] is an instance of [CacheMetrics] that tracks cache performance,
  /// and [config] is an instance of [CacheAlertConfig] that configures the alert thresholds and notifications.
  CacheAlertManager(this.metrics, this.config);

  /// Periodically monitors cache performance at the interval specified in [config].
  void monitor() {
    if (_isDisposed) return;
    _timer?.cancel();
    _timer = Timer.periodic(config.alertCheckInterval, (_) {
      final stats = metrics.snapshot(config.alertCheckInterval);
      _checkAlerts(stats);
    });
  }

  /// Cancels the monitoring timer and releases resources.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _isDisposed = true;
  }

  /// Checks the cache statistics and triggers alerts if any thresholds are exceeded.
  void _checkAlerts(CacheMetricsSnapshot stats) {
    if (stats.hitRate < config.hitRateThreshold) {
      config.notifyCallback(
        'Warning: Low hit rate detected. '
        'Actual: ${stats.hitRate} (Threshold: ${config.hitRateThreshold})',
      );
    }
    if (stats.missRate > config.missRateThreshold) {
      config.notifyCallback(
        'Warning: High miss rate detected. '
        'Actual: ${stats.missRate} (Threshold: ${config.missRateThreshold})',
      );
    }
    if (stats.p95Latency.inMilliseconds > config.p95LatencyThreshold) {
      config.notifyCallback(
        'Warning: High p95 latency detected. '
        'Actual: ${stats.p95Latency.inMilliseconds}ms (Threshold: ${config.p95LatencyThreshold}ms)',
      );
    }
    if (stats.p99Latency.inMilliseconds > config.p99LatencyThreshold) {
      config.notifyCallback(
        'Warning: High p99 latency detected. '
        'Actual: ${stats.p99Latency.inMilliseconds}ms (Threshold: ${config.p99LatencyThreshold}ms)',
      );
    }
    if (stats.averageLatency.inMilliseconds > config.averageLatencyThreshold) {
      config.notifyCallback(
        'Warning: High average latency detected. '
        'Actual: ${stats.averageLatency.inMilliseconds}ms (Threshold: ${config.averageLatencyThreshold}ms)',
      );
    }
    if (stats.evictionsPerMinute > config.evictionsPerMinuteThreshold) {
      config.notifyCallback(
        'Warning: High eviction rate detected. '
        'Actual: ${stats.evictionsPerMinute} evictions/min '
        '(Threshold: ${config.evictionsPerMinuteThreshold} evictions/min)',
      );
    }
    final perReasonThreshold = config.evictionsPerReasonThreshold;
    if (perReasonThreshold != null) {
      for (final entry in stats.evictionsPerMinuteByReason.entries) {
        final threshold = perReasonThreshold[entry.key];
        if (threshold != null && entry.value > threshold) {
          config.notifyCallback(
            'Warning: High ${entry.key.name} eviction rate detected. '
            'Actual: ${entry.value} evictions/min '
            '(Threshold: $threshold evictions/min)',
          );
        }
      }
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

  /// Optional, additive per-[EvictionReason] thresholds, checked alongside
  /// [evictionsPerMinuteThreshold]. `null` (the default) disables per-reason
  /// alerting entirely; a reason absent from the map is simply not checked.
  /// Useful for distinguishing an expected `expired` rate (that's what TTL is
  /// for) from a `capacity`/`weight` rate that signals the cache is
  /// undersized — lumping them into one aggregate threshold can mask the
  /// latter behind harmless expiry churn.
  final Map<EvictionReason, int>? evictionsPerReasonThreshold;
  final int averageLatencyThreshold;
  final Duration alertCheckInterval;

  /// Initializes the alert configuration.
  ///
  /// [notifyCallback] is the function used to notify about alerts,
  /// the various thresholds set user-defined limits for performance metrics,
  /// and [alertCheckInterval] sets the interval for checking alerts.
  CacheAlertConfig({
    this.notifyCallback = _noopAlertCallback,
    this.hitRateThreshold = 0.5,
    this.missRateThreshold = 0.5,
    this.p95LatencyThreshold = 200,
    this.p99LatencyThreshold = 300,
    this.evictionsPerMinuteThreshold = 1000,
    this.evictionsPerReasonThreshold,
    this.averageLatencyThreshold = 100,
    this.alertCheckInterval = const Duration(
      minutes: 1,
    ), // Default check every minute
  }) {
    if (alertCheckInterval <= Duration.zero) {
      throw ArgumentError('alertCheckInterval must be greater than zero.');
    }
  }
}
