import 'dart:async';

import '../interfaces/disposable.dart';
import '../interfaces/periodic_sweeper.dart';
import '../interfaces/weigher.dart';
import '../monitorings/cache_alert_manager.dart';
import '../monitorings/cache_monitoring.dart';
import '../monitorings/eviction_reason.dart';
import '../stores/cache_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Composable, async-safe cache engine with performance monitoring.**
///
/// Adds hit/miss/latency tracking and eviction alerting (via [CacheMonitoring]
/// and [CacheAlertManager]) on top of [AsyncCache]. Every eviction the
/// underlying [Cache] performs — capacity, weight, or expiry — is recorded
/// with its [EvictionReason]; explicit [remove] calls are recorded
/// separately as [EvictionReason.manual].
///
/// Implements [Disposable] (via [PeriodicSweeper]): call [dispose] to cancel
/// the alert-monitoring timer and, if TTL sweeping was configured, the sweep
/// timer.
class MonitoredCache<K, V> extends AsyncCache<K, V>
    with CacheMonitoring<K, V>, PeriodicSweeper
    implements Disposable {
  late final CacheAlertManager _cacheAlertManager;

  /// Creates a [MonitoredCache]. See [Cache] for [store]/[maxSize]/[weigher]/
  /// [maxWeight]/[ttl]/[clock]. [sweepInterval], when given alongside [ttl],
  /// starts a background timer that proactively purges expired entries.
  /// [alertConfig] configures performance-alert thresholds.
  MonitoredCache({
    required CacheStore<K, V> store,
    int? maxSize,
    Weigher<K, V>? weigher,
    int? maxWeight,
    Duration? ttl,
    Duration? sweepInterval,
    DateTime Function()? clock,
    CacheAlertConfig? alertConfig,
  }) : super(
         Cache(
           store: store,
           maxSize: maxSize,
           weigher: weigher,
           maxWeight: maxWeight,
           ttl: ttl,
           clock: clock,
         ),
       ) {
    // Validate before starting anything: if construction is going to throw,
    // it must do so before the alert-monitoring timer (or the sweep timer)
    // starts, or the half-constructed instance — never returned to the
    // caller — would leak a running Timer with no way to dispose() it.
    if (sweepInterval != null) {
      if (ttl == null) {
        throw ArgumentError(
          'sweepInterval was supplied but this cache was not configured '
          'with a default ttl.',
        );
      }
      if (sweepInterval <= Duration.zero) {
        throw ArgumentError('sweepInterval must be greater than zero.');
      }
    }

    engine.onEvict = metrics.recordEviction;
    _cacheAlertManager = CacheAlertManager(
      metrics,
      alertConfig ?? CacheAlertConfig(),
    );
    _cacheAlertManager.monitor();

    if (sweepInterval != null) {
      startSweep(sweepInterval, () async {
        await lock.synchronized(engine.purgeExpired);
      });
    }
  }

  @override
  Future<V?> get(K key) async {
    var found = false;
    return await monitoredGet(key, () async {
      return await lock.synchronized(() {
        final (f, value) = engine.presentValue(key);
        found = f;
        return value;
      });
    }, found: () => found);
  }

  @override
  Future<V> getOrCompute(
    K key,
    FutureOr<V> Function() valueFactory, {
    int? weight,
    Duration? ttl,
  }) async {
    engine.validateSetArgs(weight: weight, ttl: ttl);
    var found = false;
    return await monitoredGet(key, () async {
          return await lock.synchronized(() async {
            final (f, existing) = engine.presentValue(key);
            if (f) {
              found = true;
              return existing;
            }
            final value = await valueFactory();
            engine.set(key, value, weight: weight, ttl: ttl);
            return value;
          });
        }, found: () => found)
        as V;
  }

  @override
  Future<void> remove(K key) async {
    final removed = await lock.synchronized(() => engine.removeIfPresent(key));
    if (removed) metrics.recordEviction(EvictionReason.manual);
  }

  @override
  void dispose() {
    super.dispose(); // PeriodicSweeper: cancels the sweep timer, if any.
    _cacheAlertManager.dispose();
  }
}
