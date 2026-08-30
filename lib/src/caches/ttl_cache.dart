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

  /// Returns the existing value for [key], or computes, stores, and returns
  /// a new one.
  ///
  /// Holds [AsyncCache.lock] across the whole check-compute-store sequence
  /// (atomicity: no duplicate computation for a racing missing key, and a
  /// single clock snapshot so an entry can't expire between the check and
  /// the store), but writes through this class's own [set] instead of the
  /// engine directly — safe from deadlock because that lock is reentrant —
  /// so a subclass override of [set] still runs.
  @override
  Future<V> getOrCompute(
    K key,
    FutureOr<V> Function() valueFactory, {
    Duration? ttl,
  }) {
    _engine.engine.validateSetArgs(ttl: ttl);
    return _engine.lock.synchronized(() async {
      final (found, existing) = _engine.engine.presentValue(key);
      if (found) return existing as V;
      final value = await valueFactory();
      await set(key, value, ttl: ttl);
      return value;
    });
  }

  /// Updates the value for [key] and returns the new value.
  ///
  /// The inherited [ThreadSafeTTLCacheInterface] default checks presence and
  /// reads [key] with separate `containsKey`/`get` calls, each independently
  /// acquiring the lock and reading the clock; this override reads via a
  /// single snapshot instead, and — see [getOrCompute] — writes through this
  /// class's own [set] under the same reentrant lock.
  @override
  Future<V> update(
    K key,
    FutureOr<V> Function(V value) update, {
    FutureOr<V> Function()? ifAbsent,
    Duration? ttl,
  }) {
    _engine.engine.validateSetArgs(ttl: ttl);
    return _engine.lock.synchronized(() async {
      final (found, existing) = _engine.engine.presentValue(key);
      if (found) {
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
  }

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
