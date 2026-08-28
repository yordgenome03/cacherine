import 'dart:async';

import '../interfaces/disposable.dart';
import '../interfaces/thread_safe_ttl_cache.dart';
import '../monitorings/cache_alert_manager.dart';
import '../monitorings/cache_metrics.dart';
import '../stores/ttl_fifo_store.dart';
import 'monitored_cache.dart';

/// **Async-safe TTL (Time-To-Live) Cache with Monitoring**
///
/// Entries are treated as absent once their TTL has elapsed. Expired entries
/// are removed lazily on [get], proactively by an optional background sweep,
/// and during capacity checks when [maxSize] is configured.
///
/// This cache records hit/miss latency through [metrics] and records
/// eviction events — tagged by cause (expiry, capacity, or manual removal) —
/// when entries are removed.
///
/// Wraps a [MonitoredCache] configured with a [TTLFifoStore] — internally a
/// composed engine rather than a subclass, so this class can keep extending
/// [ThreadSafeTTLCacheInterface] for backward compatibility. [metrics] and
/// [dispose] delegate to that engine directly, so there is exactly one
/// [CacheMetrics] instance and one set of timers per cache, not one per
/// wrapper layer.
class MonitoredTTLCache<K, V> extends ThreadSafeTTLCacheInterface<K, V>
    implements Disposable {
  final MonitoredCache<K, V> _engine;

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
  }) : _engine = MonitoredCache(
         store: TTLFifoStore<K, V>(),
         maxSize: maxSize,
         ttl: ttl,
         sweepInterval: sweepInterval,
         clock: clock,
         alertConfig: alertConfig,
       );

  /// Cache performance metrics: hit/miss rates, latency, and evictions.
  CacheMetrics get metrics => _engine.metrics;

  @override
  Future<Iterable<K>> getKeys() => _engine.getKeys();

  @override
  Future<int> purgeExpired() => _engine.purgeExpired();

  @override
  Future<V?> get(K key) => _engine.get(key);

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
  }) => _engine.getOrCompute(key, valueFactory, ttl: ttl);

  @override
  Future<void> remove(K key) => _engine.remove(key);

  @override
  Future<void> clear() => _engine.clear();

  @override
  void dispose() => _engine.dispose();

  @override
  String toString() => _engine.toString();
}
