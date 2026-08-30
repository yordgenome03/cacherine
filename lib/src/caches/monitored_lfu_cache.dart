import 'dart:async';

import '../interfaces/disposable.dart';
import '../interfaces/periodic_sweeper.dart';
import '../interfaces/thread_safe_cache.dart';
import '../monitorings/cache_alert_manager.dart';
import '../monitorings/cache_monitoring.dart';
import '../monitorings/eviction_reason.dart';
import '../stores/lfu_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Async-safe LFU (Least Frequently Used) Cache with Monitoring**
///
/// This class serializes concurrent async calls on the same cache instance
/// within the same isolate using `Lock`.
///
/// Additionally, by utilizing the [CacheMonitoring] mixin, it automatically **monitors cache performance**.
/// It records the following metrics and triggers alerts via the [CacheAlertManager] if thresholds are exceeded:
///
/// - **Hit rate and miss rate** (tracking the success/failure rate of cache accesses)
/// - **Request latency** (measuring the response time for cache access)
/// - **Evictions** (tracking the number of evictions due to cache size limits)
///
/// This cache implements the **LFU eviction policy**, and:
/// - When the cache size exceeds `maxSize`, the **least frequently used element is removed**.
///
/// Wraps an [AsyncCache] configured with an [LFUStore] — internally a
/// composed engine rather than a subclass of [MonitoredCache], so this class
/// keeps its original `set`/`getOrCompute`/`update`/`setAll` signatures (no
/// `weight`/`ttl` parameters) while still mixing in [CacheMonitoring]/
/// [PeriodicSweeper] directly (matching [MonitoredTTLCache]) so
/// `is CacheMonitoring<K, V>` and `is Disposable` keep holding for callers
/// relying on them.
class MonitoredLFUCache<K, V> extends ThreadSafeCache<K, V>
    with CacheMonitoring<K, V>, PeriodicSweeper
    implements Disposable {
  final AsyncCache<K, V> _engine;
  late final CacheAlertManager _cacheAlertManager;

  /// **Creates a [MonitoredLFUCache] with a specified maximum size and alert configuration.**
  ///
  /// ### **Arguments:**
  /// - **[maxSize]**: The maximum size of the cache.
  ///   If this size is exceeded, the least frequently used element will be removed based on the LFU policy.
  /// - **[alertConfig]**: The alert configuration for cache monitoring.
  ///   Alerts will be triggered when the defined thresholds are exceeded.
  ///
  /// ### **Exceptions:**
  /// - **[ArgumentError]**: Thrown when [maxSize] is `0 or less`.
  MonitoredLFUCache({required int maxSize, CacheAlertConfig? alertConfig})
    : _engine = AsyncCache(Cache(store: LFUStore<K, V>(), maxSize: maxSize)) {
    _engine.engine.onEvict = metrics.recordEviction;
    _cacheAlertManager = CacheAlertManager(
      metrics,
      alertConfig ?? CacheAlertConfig(),
    );
    _cacheAlertManager.monitor();
  }

  /// The maximum number of entries in the cache.
  int get maxSize => _engine.maxSize!;

  @override
  Future<Iterable<K>> getKeys() => _engine.getKeys();

  @override
  Future<V?> get(K key) async {
    var found = false;
    return await monitoredGet(key, () async {
      return await _engine.lock.synchronized(() {
        final (f, value) = _engine.engine.presentValue(key);
        found = f;
        return value;
      });
    }, found: () => found);
  }

  @override
  Future<V?> peek(K key) => _engine.peek(key);

  @override
  Future<bool> containsKey(K key) => _engine.containsKey(key);

  @override
  Future<void> set(K key, V value) => _engine.set(key, value);

  @override
  Future<void> setAll(Map<K, V> entries) => _engine.setAll(entries);

  @override
  Future<V> getOrCompute(K key, FutureOr<V> Function() valueFactory) async {
    var found = false;
    return await monitoredGet(key, () async {
          return await _engine.lock.synchronized(() async {
            final (f, existing) = _engine.engine.presentValue(key);
            if (f) {
              found = true;
              return existing;
            }
            final value = await valueFactory();
            _engine.engine.set(key, value);
            return value;
          });
        }, found: () => found)
        as V;
  }

  /// Updates the value for [key] and returns the new value.
  ///
  /// Per `doc/monitored_cache.md` ("`update()` follow[s] `getOrCompute()`
  /// hit/miss semantics"), this records the same hit/miss/latency metrics as
  /// an equivalent [getOrCompute] call.
  @override
  Future<V> update(
    K key,
    FutureOr<V> Function(V value) update, {
    FutureOr<V> Function()? ifAbsent,
  }) async {
    var found = false;
    return await monitoredGet(key, () async {
          return await _engine.lock.synchronized(() async {
            final (f, existing) = _engine.engine.presentValue(key);
            if (f) {
              found = true;
              final value = await update(existing as V);
              _engine.engine.set(key, value);
              return value;
            }
            if (ifAbsent == null) {
              throw StateError('Cannot update missing cache key: $key');
            }
            final value = await ifAbsent();
            _engine.engine.set(key, value);
            return value;
          });
        }, found: () => found)
        as V;
  }

  /// Retrieves values for all currently present [keys], recording the same
  /// hit/latency metrics as an equivalent series of [get] calls (missing
  /// keys are omitted without recording a miss, per `doc/monitored_cache.md`).
  @override
  Future<Map<K, V>> getAll(Iterable<K> keys) async {
    final values = <K, V>{};
    for (final key in keys) {
      final stopwatch = Stopwatch()..start();
      final (found, value) = await _engine.lock.synchronized(
        () => _engine.engine.presentValue(key),
      );
      stopwatch.stop();
      if (found) {
        metrics.recordHit(stopwatch.elapsed);
        if (value != null || null is V) {
          values[key] = value as V;
        }
      }
    }
    return values;
  }

  /// Removes all entries that match [test], removing a match through
  /// [remove] so it still records a manual-eviction metric.
  @override
  Future<void> removeWhere(FutureOr<bool> Function(K key, V value) test) async {
    for (final key in await getKeys()) {
      final (found, value) = await _engine.lock.synchronized(
        () => _engine.engine.presentPeek(key),
      );
      if (!found) continue;
      if (await test(key, value as V)) {
        await remove(key);
      }
    }
  }

  @override
  Future<void> remove(K key) async {
    final removed = await _engine.lock.synchronized(
      () => _engine.engine.removeIfPresent(key),
    );
    if (removed) metrics.recordEviction(EvictionReason.manual);
  }

  @override
  Future<void> clear() => _engine.clear();

  @override
  void dispose() {
    super.dispose(); // PeriodicSweeper: no-op here (this facade never sweeps).
    _cacheAlertManager.dispose();
  }

  @override
  String toString() => _engine.toString();
}
