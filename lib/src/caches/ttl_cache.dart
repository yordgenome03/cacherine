import 'dart:async';

import '../interfaces/disposable.dart';
import '../interfaces/periodic_sweeper.dart';
import '../interfaces/thread_safe_ttl_cache.dart';
import '../stores/ttl_fifo_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Thread-safe TTL (Time-To-Live) Cache**
///
/// Entries are automatically treated as absent once their TTL has elapsed.
/// Expiry is checked lazily on [get]; an optional background sweep can remove
/// expired entries proactively to reclaim memory.
///
/// Implements [Disposable] — call [dispose] to cancel the sweep timer.
///
/// Wraps an [AsyncCache] configured with a [TTLFifoStore] — internally a
/// composed engine rather than a subclass, so this class can keep extending
/// [ThreadSafeTTLCacheInterface] for backward compatibility.
class TTLCache<K, V> extends ThreadSafeTTLCacheInterface<K, V>
    with PeriodicSweeper
    implements Disposable {
  final AsyncCache<K, V> _engine;

  /// Creates a [TTLCache].
  ///
  /// - [ttl]: Default expiry duration for all entries stored via [set].
  /// - [maxSize]: Optional capacity limit; the oldest-inserted live entry is
  ///   evicted (FIFO) when the limit is exceeded.
  /// - [sweepInterval]: When provided, a background timer fires at this interval
  ///   and removes all expired entries.
  /// - [clock]: Injectable time source for testing; defaults to [DateTime.now].
  TTLCache({
    required Duration ttl,
    int? maxSize,
    Duration? sweepInterval,
    DateTime Function()? clock,
  }) : _engine = AsyncCache(
         Cache(
           store: TTLFifoStore<K, V>(),
           maxSize: maxSize,
           ttl: ttl,
           clock: clock,
         ),
       ) {
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
  Future<V?> get(K key) => _engine.get(key);

  @override
  Future<V?> peek(K key) => _engine.peek(key);

  @override
  Future<bool> containsKey(K key) => _engine.containsKey(key);

  /// Stores [key]/[value] in the cache.
  ///
  /// - [ttl]: Per-entry TTL override. When omitted, the global TTL is used.
  /// - If the key already exists, its value and expiry are updated and its
  ///   insertion order is refreshed (it becomes the newest entry for FIFO purposes).
  @override
  Future<void> set(K key, V value, {Duration? ttl}) =>
      _engine.set(key, value, ttl: ttl);

  @override
  Future<V> getOrCompute(
    K key,
    FutureOr<V> Function() valueFactory, {
    Duration? ttl,
  }) => _engine.getOrCompute(key, valueFactory, ttl: ttl);

  /// Updates the value for [key] and returns the new value.
  ///
  /// The inherited [ThreadSafeTTLCacheInterface] default checks presence and
  /// reads [key] with separate `containsKey`/`get` calls, each independently
  /// acquiring the lock and reading the clock; this override reads via a
  /// single [AsyncCache.presentValue]-backed snapshot instead (see
  /// [AsyncCache.update]).
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
  /// acquiring the lock; this override reads each key atomically instead
  /// (see [AsyncCache.getAll]).
  @override
  Future<Map<K, V>> getAll(Iterable<K> keys) => _engine.getAll(keys);

  /// Removes all entries that match [test].
  ///
  /// The inherited [ThreadSafeCache] default checks presence and peeks each
  /// key with separate `containsKey`/`peek` calls, each independently
  /// acquiring the lock; this override reads each key atomically instead
  /// (see [AsyncCache.removeWhere]).
  @override
  Future<void> removeWhere(FutureOr<bool> Function(K key, V value) test) =>
      _engine.removeWhere(test);

  @override
  Future<void> remove(K key) => _engine.remove(key);

  @override
  Future<void> clear() => _engine.clear();

  /// **Note:** `toString()` is synchronous and does not acquire the internal
  /// lock. Treat the result as diagnostic output for a point-in-time view.
  @override
  String toString() => _engine.toString();
}
