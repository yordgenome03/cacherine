import 'dart:async';

import '../interfaces/disposable.dart';
import '../interfaces/periodic_sweeper.dart';
import '../interfaces/thread_safe_ttl_cache.dart';
import '../monitorings/cache_alert_manager.dart';
import '../monitorings/cache_monitoring.dart';
import '../monitorings/eviction_reason.dart';
import '../stores/ttl_fifo_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Async-safe TTL (Time-To-Live) Cache with Monitoring**
///
/// Entries are treated as absent once their TTL has elapsed. Expired entries
/// are removed lazily on [get], proactively by an optional background sweep,
/// and during capacity checks when [maxSize] is configured.
///
/// Additionally, by utilizing the [CacheMonitoring] mixin, it automatically
/// **monitors cache performance** — hit/miss rates, request latency, and
/// eviction events tagged by cause ([EvictionReason.expired],
/// [EvictionReason.capacity], [EvictionReason.manual]) — triggering alerts
/// via [CacheAlertManager] if thresholds are exceeded, exactly like every
/// other `Monitored*Cache` in this package.
///
/// This class cannot itself extend the composable [MonitoredCache] engine
/// (Dart only allows one `extends` clause, and this class must extend
/// [ThreadSafeTTLCacheInterface] to keep its `ttl:`-aware `set()`/
/// `getOrCompute()` overloads), so it wires the same
/// engine+mixin+alert-manager+sweep pattern directly, over a plain
/// (non-monitored) [AsyncCache], rather than composing over [MonitoredCache].
class MonitoredTTLCache<K, V> extends ThreadSafeTTLCacheInterface<K, V>
    with CacheMonitoring<K, V>, PeriodicSweeper
    implements Disposable {
  final AsyncCache<K, V> _engine;
  late final CacheAlertManager _cacheAlertManager;

  /// Creates a [MonitoredTTLCache].
  ///
  /// - [ttl]: Default expiry duration for entries stored via [set].
  /// - [maxSize]: Optional capacity limit; the oldest inserted live entry is
  ///   evicted when the limit is exceeded.
  /// - [sweepInterval]: Optional background interval for removing expired
  ///   entries.
  /// - [clock]: Injectable time source for testing; defaults to [DateTime.now].
  /// - [alertConfig]: Optional alert configuration for monitoring thresholds.
  MonitoredTTLCache({
    required Duration ttl,
    int? maxSize,
    Duration? sweepInterval,
    DateTime Function()? clock,
    CacheAlertConfig? alertConfig,
  }) : _engine = AsyncCache(
         Cache(
           store: TTLFifoStore<K, V>(),
           maxSize: maxSize,
           ttl: ttl,
           clock: clock,
         ),
       ) {
    // Validate before starting anything: if construction is going to throw,
    // it must do so before the alert-monitoring timer (or the sweep timer)
    // starts, or the half-constructed instance — never returned to the
    // caller — would leak a running Timer with no way to dispose() it.
    if (sweepInterval != null && sweepInterval <= Duration.zero) {
      throw ArgumentError('sweepInterval must be greater than zero.');
    }

    _engine.engine.onEvict = metrics.recordEviction;
    _cacheAlertManager = CacheAlertManager(
      metrics,
      alertConfig ?? CacheAlertConfig(),
    );
    _cacheAlertManager.monitor();

    if (sweepInterval != null) {
      startSweep(sweepInterval, () async {
        await _engine.purgeExpired();
      });
    }
  }

  @override
  Future<Iterable<K>> getKeys() => _engine.getKeys();

  @override
  Future<int> purgeExpired() => _engine.purgeExpired();

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

  /// Stores [key]/[value] in the cache.
  ///
  /// - [ttl]: Per-entry TTL override. When omitted, the global TTL is used.
  /// - Updating an existing key refreshes its insertion order for FIFO capacity
  ///   eviction purposes.
  @override
  Future<void> set(K key, V value, {Duration? ttl}) =>
      _engine.set(key, value, ttl: ttl);

  @override
  Future<V> getOrCompute(
    K key,
    FutureOr<V> Function() valueFactory, {
    Duration? ttl,
  }) async {
    _engine.engine.validateSetArgs(ttl: ttl);
    var found = false;
    return await monitoredGet(key, () async {
          return await _engine.lock.synchronized(() async {
            final (f, existing) = _engine.engine.presentValue(key);
            if (f) {
              found = true;
              return existing;
            }
            final value = await valueFactory();
            _engine.engine.set(key, value, ttl: ttl);
            return value;
          });
        }, found: () => found)
        as V;
  }

  /// Updates the value for [key] and returns the new value.
  ///
  /// The inherited [ThreadSafeTTLCacheInterface] default checks presence and
  /// reads [key] with separate `containsKey`/`get` calls, each independently
  /// acquiring the lock and reading the clock; this override reads via a
  /// single [AsyncCache.presentValue]-backed snapshot instead. Not tracked in
  /// hit/miss metrics, consistent with every other `Monitored*Cache`'s
  /// `update` (only `get`/`getOrCompute` are monitored).
  @override
  Future<V> update(
    K key,
    FutureOr<V> Function(V value) update, {
    FutureOr<V> Function()? ifAbsent,
    Duration? ttl,
  }) => _engine.update(key, update, ifAbsent: ifAbsent, ttl: ttl);

  /// Retrieves values for all currently present [keys].
  ///
  /// The inherited [ThreadSafeCache] default checks presence and reads each
  /// key with separate `containsKey`/`get` calls, each independently
  /// acquiring the lock; this override reads each key atomically instead.
  @override
  Future<Map<K, V>> getAll(Iterable<K> keys) => _engine.getAll(keys);

  /// Removes all entries that match [test].
  ///
  /// The inherited [ThreadSafeCache] default checks presence and peeks each
  /// key with separate `containsKey`/`peek` calls, each independently
  /// acquiring the lock; this override reads each key atomically instead.
  @override
  Future<void> removeWhere(FutureOr<bool> Function(K key, V value) test) =>
      _engine.removeWhere(test);

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
    super.dispose(); // PeriodicSweeper: cancels the sweep timer, if any.
    _cacheAlertManager.dispose();
  }

  @override
  String toString() => _engine.toString();
}
