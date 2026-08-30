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
///
/// [getAll]/[setAll]/[removeWhere] are left to [ThreadSafeCache]'s default
/// implementations, which call this class's own (overridable) [get]/[set]/
/// [containsKey]/[peek]/[remove] — so a subclass overriding one of those
/// still has its override invoked (and, since [get]/[remove] are already
/// monitored, the defaults automatically record the traffic/eviction
/// metrics `doc/monitored_cache.md` documents for those bulk operations
/// too, with no separate bookkeeping needed here).
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
    _engine.engine.onEvict = metrics.recordEvictionReason;
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

  /// Returns the existing value for [key], or computes, stores, and returns
  /// a new one — recording the same hit/miss/latency metrics as [get].
  ///
  /// Holds [AsyncCache.lock] across the whole check-compute-store sequence
  /// (buying atomicity: no duplicate computation for a racing missing key,
  /// same as [AsyncCache.getOrCompute]), but writes through this class's own
  /// [set] instead of the engine directly — safe from deadlock because the
  /// lock is reentrant — so a subclass override of [set] still runs.
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
            await set(key, value);
            return value;
          });
        }, found: () => found)
        as V;
  }

  /// Updates the value for [key] and returns the new value.
  ///
  /// Per `doc/monitored_cache.md` ("`update()` follow[s] `getOrCompute()`
  /// hit/miss semantics"), this records the same hit/miss/latency metrics as
  /// an equivalent [getOrCompute] call, and — see [getOrCompute] — writes
  /// through this class's own [set] under the same reentrant lock.
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
              await set(key, value);
              return value;
            }
            if (ifAbsent == null) {
              throw StateError('Cannot update missing cache key: $key');
            }
            final value = await ifAbsent();
            await set(key, value);
            return value;
          });
        }, found: () => found)
        as V;
  }

  @override
  Future<void> remove(K key) async {
    final removed = await _engine.lock.synchronized(
      () => _engine.engine.removeIfPresent(key),
    );
    if (removed) metrics.recordEvictionReason(EvictionReason.manual);
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
