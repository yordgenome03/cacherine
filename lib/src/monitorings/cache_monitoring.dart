import 'dart:async';

import '../caches/async_cache.dart';
import 'cache_metrics.dart';

/// Cache monitoring mixin
///
/// This mixin provides cache performance monitoring functionality. It measures
/// cache hit rates, miss rates, latencies, and records them in the [CacheMetrics] class.
mixin CacheMonitoring<K, V> {
  final CacheMetrics metrics = CacheMetrics();

  /// Measures and records cache hit/miss performance when accessing a key.
  Future<V?> monitoredGet(
    K key,
    Future<V?> Function() getter, {
    bool Function()? found,
  }) async {
    final stopwatch = Stopwatch()..start();
    final value = await getter();
    stopwatch.stop();

    if (found?.call() ?? value != null) {
      metrics.recordHit(stopwatch.elapsed);
    } else {
      metrics.recordMiss(stopwatch.elapsed);
    }
    return value;
  }

  /// **Shared `getOrCompute()` control flow for a `Monitored*Cache` legacy
  /// facade composing (not extending) an [AsyncCache] engine.**
  ///
  /// Every `Monitored*Cache` legacy facade (`MonitoredLRUCache`,
  /// `MonitoredMRUCache`, `MonitoredFIFOCache`, `MonitoredLFUCache`,
  /// `MonitoredEphemeralFIFOCache`) composes an engine instead of extending
  /// `MonitoredCache`, to keep its original, narrower public signature — see
  /// each facade's own class doc comment for why. That composition means
  /// `getOrCompute` can't simply delegate to the engine's own
  /// `getOrCompute`/`storeOrThrow`: doing so would write through the
  /// engine's `set()`, bypassing a subclass's override of the *facade's*
  /// `set()`. Every one of these facades therefore hand-rolled the identical
  /// "record hit/miss via [monitoredGet], hold the lock, check presence
  /// atomically, compute, write through this class's own `set`" sequence —
  /// this method is that sequence, extracted once.
  ///
  /// [engine] is the facade's composed [AsyncCache]. [writeThrough] must
  /// call the facade's own (possibly overridden) `set` — not `engine.set`
  /// directly — so a subclass's `set` override still sees every write this
  /// makes.
  Future<V> monitoredGetOrCompute(
    K key,
    AsyncCache<K, V> engine,
    FutureOr<V> Function() valueFactory,
    Future<void> Function(K key, V value) writeThrough,
  ) async {
    var found = false;
    return await monitoredGet(key, () async {
          return await engine.lock.synchronized(() async {
            final (f, existing) = engine.engine.presentValue(key);
            if (f) {
              found = true;
              return existing;
            }
            final value = await valueFactory();
            await writeThrough(key, value);
            return value;
          });
        }, found: () => found)
        as V;
  }

  /// The [monitoredGetOrCompute] counterpart for `update`. See its doc
  /// comment.
  Future<V> monitoredUpdate(
    K key,
    AsyncCache<K, V> engine,
    FutureOr<V> Function(V value) update, {
    required Future<void> Function(K key, V value) writeThrough,
    FutureOr<V> Function()? ifAbsent,
  }) async {
    var found = false;
    return await monitoredGet(key, () async {
          return await engine.lock.synchronized(() async {
            final (f, existing) = engine.engine.presentValue(key);
            if (f) {
              found = true;
              final value = await update(existing as V);
              await writeThrough(key, value);
              return value;
            }
            if (ifAbsent == null) {
              throw StateError('Cannot update missing cache key: $key');
            }
            final value = await ifAbsent();
            await writeThrough(key, value);
            return value;
          });
        }, found: () => found)
        as V;
  }
}
