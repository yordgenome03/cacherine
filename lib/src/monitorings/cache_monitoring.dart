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

  /// **Shared `getOrCompute()` control flow for a non-TTL `Monitored*Cache`
  /// legacy facade composing (not extending) an [AsyncCache] engine.**
  ///
  /// `MonitoredLRUCache`, `MonitoredMRUCache`, `MonitoredFIFOCache`,
  /// `MonitoredLFUCache`, and `MonitoredEphemeralFIFOCache` compose an engine
  /// instead of extending `MonitoredCache`, to keep their original, narrower
  /// public signature — see each facade's own class doc comment for why.
  /// That composition means `getOrCompute` can't simply delegate to the
  /// engine's own `getOrCompute`/`storeOrThrow`: doing so would write through
  /// the engine's `set()`, bypassing a subclass's override of the *facade's*
  /// `set()`. Every one of these facades therefore hand-rolled the identical
  /// "hold the lock, check presence, compute, write through this class's own
  /// `set`" sequence — this method is that sequence, extracted once.
  ///
  /// The presence check and read are dispatched through [containsKey]/[get]
  /// — the facade's own (already-monitored) methods — rather than reading
  /// the composed engine directly, for the same reason as (and none of these
  /// five facades have a `ttl`, so the same safety argument as)
  /// `composedGetOrCompute` in `_composed_engine_ops.dart`: a downstream
  /// subclass's `containsKey`/`get` override still sees every read this
  /// makes, and — because [get] records its own hit metric via
  /// [monitoredGet] as soon as the read resolves — a hit is recorded even if
  /// [valueFactory] (called only on a miss) later throws, matching the
  /// pre-existing `ThreadSafeCache.getOrCompute` default these facades stand
  /// in for. A miss never reaches [get], so it's recorded explicitly here,
  /// timed around [valueFactory] alone.
  ///
  /// **`MonitoredTTLCache` does NOT use this** — see `TTLCache`'s
  /// `getOrCompute` for why a `ttl`-configured facade needs
  /// [Cache.presentValue]'s atomic snapshot instead.
  ///
  /// [engine] is the facade's composed [AsyncCache], used only to acquire its
  /// [AsyncCache.lock]. [containsKey]/[get]/[writeThrough] must all be the
  /// facade's own (possibly overridden) methods, not `engine`'s.
  Future<V> monitoredGetOrCompute(
    K key,
    AsyncCache<K, V> engine,
    Future<bool> Function(K key) containsKey,
    Future<V?> Function(K key) get,
    FutureOr<V> Function() valueFactory,
    Future<void> Function(K key, V value) writeThrough,
  ) {
    return engine.lock.synchronized(() async {
      if (await containsKey(key)) return (await get(key)) as V;
      final stopwatch = Stopwatch()..start();
      final value = await valueFactory();
      stopwatch.stop();
      metrics.recordMiss(stopwatch.elapsed);
      await writeThrough(key, value);
      return value;
    });
  }

  /// The [monitoredGetOrCompute] counterpart for `update`. See its doc
  /// comment.
  Future<V> monitoredUpdate(
    K key,
    AsyncCache<K, V> engine,
    Future<bool> Function(K key) containsKey,
    Future<V?> Function(K key) get,
    FutureOr<V> Function(V value) update, {
    required Future<void> Function(K key, V value) writeThrough,
    FutureOr<V> Function()? ifAbsent,
  }) {
    return engine.lock.synchronized(() async {
      if (await containsKey(key)) {
        final value = await update((await get(key)) as V);
        await writeThrough(key, value);
        return value;
      }
      if (ifAbsent == null) {
        throw StateError('Cannot update missing cache key: $key');
      }
      final stopwatch = Stopwatch()..start();
      final value = await ifAbsent();
      stopwatch.stop();
      metrics.recordMiss(stopwatch.elapsed);
      await writeThrough(key, value);
      return value;
    });
  }
}
