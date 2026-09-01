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

    _engine.engine.onEvict = metrics.recordEvictionReason;
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

  /// Returns the existing value for [key], or computes, stores, and returns
  /// a new one — recording the same hit/miss/latency metrics as [get].
  ///
  /// Holds [AsyncCache.lock] across the whole check-compute-store sequence
  /// (atomicity: no duplicate computation for a racing missing key, and a
  /// single clock snapshot so an entry can't expire between the check and
  /// the store), but writes through this class's own [set] instead of the
  /// engine directly — safe from deadlock because that lock is reentrant —
  /// so a subclass override of [set] still runs.
  ///
  /// Deliberately does **not** dispatch its presence check through this
  /// class's own [containsKey]/[get] (unlike the non-TTL `Monitored*Cache`
  /// legacy facades' shared `monitoredGetOrCompute`): two separate calls
  /// would each independently read the clock, reopening the TTL
  /// check-then-fetch race [Cache.presentValue] exists to close. A subclass
  /// override of [containsKey]/[get] is therefore not observed by this
  /// method's own presence check — only by direct calls to them — the same
  /// documented tradeoff [getAll]/[removeWhere] below make.
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
            await set(key, value, ttl: ttl);
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
  /// single snapshot instead (see [getOrCompute] for why), and — per
  /// `doc/monitored_cache.md` ("`update()` follow[s] `getOrCompute()`
  /// hit/miss semantics") — records the same hit/miss/latency metrics as an
  /// equivalent [getOrCompute] call, writing through this class's own [set]
  /// under the same reentrant lock.
  @override
  Future<V> update(
    K key,
    FutureOr<V> Function(V value) update, {
    FutureOr<V> Function()? ifAbsent,
    Duration? ttl,
  }) async {
    _engine.engine.validateSetArgs(ttl: ttl);
    var found = false;
    return await monitoredGet(key, () async {
          return await _engine.lock.synchronized(() async {
            final (f, existing) = _engine.engine.presentValue(key);
            if (f) {
              found = true;
              final value = await update(existing as V);
              await set(key, value, ttl: ttl);
              return value;
            }
            if (ifAbsent == null) {
              throw StateError('Cannot update missing cache key: $key');
            }
            final value = await ifAbsent();
            await set(key, value, ttl: ttl);
            return value;
          });
        }, found: () => found)
        as V;
  }

  /// Retrieves values for all currently present [keys].
  ///
  /// The inherited [ThreadSafeCache] default checks presence and reads each
  /// key with separate `containsKey`/`get` calls, each independently
  /// acquiring the lock; this override reads each key atomically instead via
  /// [AsyncCache]'s `presentValue`, and — matching every other
  /// `Monitored*Cache` — records the same hit/latency metrics as an
  /// equivalent series of [get] calls (missing keys are omitted without
  /// recording a miss, per `doc/monitored_cache.md`).
  @override
  Future<Map<K, V>> getAll(Iterable<K> keys) {
    return _engine.lock.synchronized(() {
      final values = <K, V>{};
      for (final key in keys) {
        final stopwatch = Stopwatch()..start();
        final (found, value) = _engine.engine.presentValue(key);
        stopwatch.stop();
        if (found) {
          metrics.recordHit(stopwatch.elapsed);
          if (value != null || null is V) {
            values[key] = value as V;
          }
        }
      }
      return values;
    });
  }

  /// Removes all entries that match [test].
  ///
  /// The inherited [ThreadSafeCache] default checks presence and peeks each
  /// key with separate `containsKey`/`peek` calls, each independently
  /// acquiring the lock; this override reads each key atomically instead via
  /// [AsyncCache]'s `presentPeek`, and removes a match through [remove] (not
  /// the unmonitored engine directly) so it still records the manual-eviction
  /// metric [remove] documents.
  @override
  Future<void> removeWhere(FutureOr<bool> Function(K key, V value) test) {
    return _engine.lock.synchronized(() async {
      for (final key in _engine.engine.getKeys().toList()) {
        final (found, value) = _engine.engine.presentPeek(key);
        if (!found) continue;
        if (await test(key, value as V)) {
          await remove(key);
        }
      }
    });
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
    super.dispose(); // PeriodicSweeper: cancels the sweep timer, if any.
    _cacheAlertManager.dispose();
  }

  @override
  String toString() => _engine.toString();
}
