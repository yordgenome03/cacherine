import 'dart:async';

import '../interfaces/disposable.dart';
import '../interfaces/periodic_sweeper.dart';
import '../interfaces/thread_safe_cache.dart';
import '../monitorings/cache_alert_manager.dart';
import '../monitorings/cache_monitoring.dart';
import '../monitorings/eviction_reason.dart';
import '../stores/ephemeral_fifo_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Async-safe Ephemeral FIFO (First In, First Out) Cache with Monitoring**
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
/// **Features of this cache**:
/// - **FIFO (First In, First Out) eviction policy**
/// - **Ephemeral nature**: Retrieved keys are removed from the cache immediately
/// - **When the cache size exceeds `maxSize`, the oldest element is removed**
///
/// ### **Note**:
/// - **The retrieved data cannot be reused (it is removed from the cache upon retrieval)**
/// - **If you need to preserve the key, use `MonitoredFIFOCache` instead.**
///
/// Wraps an [AsyncCache] configured with an [EphemeralFIFOStore] —
/// internally a composed engine rather than a subclass of [MonitoredCache],
/// so this class keeps its original `set`/`getOrCompute`/`update`/`setAll`
/// signatures (no `weight`/`ttl` parameters) while still mixing in
/// [CacheMonitoring]/[PeriodicSweeper] directly (matching
/// [MonitoredTTLCache]) so `is CacheMonitoring<K, V>` and `is Disposable`
/// keep holding for callers relying on them.
///
/// [setAll] is left to [ThreadSafeCache]'s default implementation, which
/// calls this class's own (overridable) [set] — so a subclass override still
/// sees every write. [getAll]/[removeWhere] are NOT left to their
/// [ThreadSafeCache] defaults: those check presence and then separately
/// read/peek, each independently acquiring the lock — but [get] here is
/// destructive (an entry is removed on retrieval), so a second caller's
/// concurrent [get] can land in the gap and consume the entry first, silently
/// dropping it from [getAll]'s result (or, for [removeWhere], throwing when
/// peeking then returns `null` for a non-nullable `V`). They read each key
/// via a single atomic snapshot instead, recording the same hit/latency/
/// manual-eviction metrics `doc/monitored_cache.md` documents for these bulk
/// operations (matching [MonitoredTTLCache]'s equivalent overrides).
class MonitoredEphemeralFIFOCache<K, V> extends ThreadSafeCache<K, V>
    with CacheMonitoring<K, V>, PeriodicSweeper
    implements Disposable {
  final AsyncCache<K, V> _engine;
  late final CacheAlertManager _cacheAlertManager;

  /// **Creates a [MonitoredEphemeralFIFOCache] with a specified maximum size and alert configuration.**
  ///
  /// - **[maxSize]**: The maximum size of the cache.
  ///   If this size is exceeded, the oldest element will be removed based on the FIFO policy.
  /// - **[alertConfig]**: The alert configuration for cache monitoring.
  ///   Alerts will be triggered when the defined thresholds are exceeded.
  ///
  /// **Throws an [ArgumentError] if [maxSize] is less than or equal to 0.**
  MonitoredEphemeralFIFOCache({
    required int maxSize,
    CacheAlertConfig? alertConfig,
  }) : _engine = AsyncCache(
         Cache(store: EphemeralFIFOStore<K, V>(), maxSize: maxSize),
       ) {
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

  /// Retrieves values for all currently present [keys], consuming each one
  /// (per [get]'s "removed on retrieval" behavior) via a single atomic
  /// snapshot per key — see the class doc comment for why this can't be left
  /// to [ThreadSafeCache]'s default. Records the same hit/latency metrics as
  /// an equivalent series of [get] calls (missing keys are omitted without
  /// recording a miss, per `doc/monitored_cache.md`).
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

  /// Removes all entries that match [test]. Reads each key via a single
  /// atomic peek-based snapshot instead of [ThreadSafeCache]'s default — see
  /// the class doc comment — and removes a match through [remove] (not the
  /// unmonitored engine directly) so it still records the manual-eviction
  /// metric [remove] documents. Peek-based, so testing an entry for removal
  /// never consumes it as a side effect.
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
