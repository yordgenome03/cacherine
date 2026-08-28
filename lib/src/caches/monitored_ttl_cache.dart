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
    _engine.engine.onEvict = metrics.recordEviction;
    _cacheAlertManager = CacheAlertManager(
      metrics,
      alertConfig ?? CacheAlertConfig(),
    );
    _cacheAlertManager.monitor();

    if (sweepInterval != null) {
      if (sweepInterval <= Duration.zero) {
        throw ArgumentError('sweepInterval must be greater than zero.');
      }
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
        found = _engine.engine.containsKey(key);
        return _engine.engine.get(key);
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
    var found = false;
    return await monitoredGet(key, () async {
          return await _engine.lock.synchronized(() async {
            if (_engine.engine.containsKey(key)) {
              found = true;
              return _engine.engine.get(key);
            }
            final value = await valueFactory();
            _engine.engine.set(key, value, ttl: ttl);
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
