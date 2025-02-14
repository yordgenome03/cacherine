import 'cache_metrics.dart';

/// Cache monitoring mixin
///
/// This mixin provides cache performance monitoring functionality. It measures
/// cache hit rates, miss rates, latencies, and records them in the [CacheMetrics] class.
mixin CacheMonitoring<K, V> {
  final CacheMetrics metrics = CacheMetrics();

  /// Measures and records cache hit/miss performance when accessing a key.
  Future<V?> monitoredGet(K key, Future<V?> Function() getter) async {
    final stopwatch = Stopwatch()..start();
    final value = await getter();
    stopwatch.stop();

    if (value != null) {
      metrics.recordHit(stopwatch.elapsed);
    } else {
      metrics.recordMiss();
    }
    return value;
  }
}
