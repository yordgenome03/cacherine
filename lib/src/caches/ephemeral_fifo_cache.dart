import 'dart:async';

import '../interfaces/thread_safe_cache.dart';
import '../stores/ephemeral_fifo_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Async-safe Ephemeral FIFO (First In, First Out) Cache**
///
/// This class implements a **FIFO-based cache** with an **ephemeral property**,
/// meaning that **values are immediately removed after being retrieved**.
///
/// It serializes concurrent async calls on the same cache instance within
/// the same isolate using `Lock`.
///
/// - **Adopts FIFO (First In, First Out) eviction policy**
/// - **Removes the oldest element when the cache exceeds `maxSize`**
/// - **Removes the key from the cache upon retrieval**
///
/// ### **Note**
/// - **Retrieved data cannot be reused (as it is deleted upon access)**
/// - **If you need to retain keys after access, use `FIFOCache` instead**
///
/// Wraps an [AsyncCache] configured with an [EphemeralFIFOStore] —
/// internally a composed engine rather than a subclass, so this class keeps
/// its original `set`/`getOrCompute`/`update`/`setAll` signatures (no
/// `weight`/`ttl` parameters) rather than inheriting [AsyncCache]'s wider
/// ones.
///
/// [setAll] is left to [ThreadSafeCache]'s default implementation, which
/// calls this class's own (overridable) [set] — so a subclass override still
/// sees every write. [getAll]/[removeWhere] are NOT left to their
/// [ThreadSafeCache] defaults, unlike every other legacy facade: those
/// defaults check presence and then separately read/peek, each independently
/// acquiring the lock — but [get] here is destructive (an entry is removed on
/// retrieval), so a second caller's concurrent [get] can land in the gap and
/// consume the entry first, silently dropping it from [getAll]'s result (or,
/// for [removeWhere], throwing when [peek] then returns `null` for a
/// non-nullable `V`). They delegate straight to the underlying [AsyncCache]'s
/// already-atomic implementations instead. [getOrCompute]/[update] are
/// overridden to hold [AsyncCache.lock] across the whole check-compute-store
/// sequence (atomicity: no duplicate computation for a racing missing key,
/// matching [AsyncCache.getOrCompute]) while still writing through this
/// class's own [set] — safe from deadlock because that lock is reentrant.
class EphemeralFIFOCache<K, V> extends ThreadSafeCache<K, V> {
  final AsyncCache<K, V> _engine;

  /// **Creates an instance of [EphemeralFIFOCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the oldest element is removed** following the FIFO policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  EphemeralFIFOCache(int maxSize)
    : _engine = AsyncCache(
        Cache(store: EphemeralFIFOStore<K, V>(), maxSize: maxSize),
      );

  /// The maximum number of entries in the cache.
  int get maxSize => _engine.maxSize!;

  @override
  Future<Iterable<K>> getKeys() => _engine.getKeys();

  @override
  Future<V?> get(K key) => _engine.get(key);

  @override
  Future<V?> peek(K key) => _engine.peek(key);

  @override
  Future<bool> containsKey(K key) => _engine.containsKey(key);

  @override
  Future<void> set(K key, V value) => _engine.set(key, value);

  /// Retrieves values for all currently present [keys], consuming each one
  /// (per [get]'s "removed on retrieval" behavior) via a single atomic
  /// snapshot per key — see the class doc comment for why this can't be left
  /// to [ThreadSafeCache]'s default.
  @override
  Future<Map<K, V>> getAll(Iterable<K> keys) => _engine.getAll(keys);

  /// Removes all entries that match [test]. Reads each key via a single
  /// atomic peek-based snapshot — see the class doc comment for why this
  /// can't be left to [ThreadSafeCache]'s default. Peek-based, so testing an
  /// entry for removal never consumes it as a side effect.
  @override
  Future<void> removeWhere(FutureOr<bool> Function(K key, V value) test) =>
      _engine.removeWhere(test);

  @override
  Future<V> getOrCompute(K key, FutureOr<V> Function() valueFactory) {
    return _engine.lock.synchronized(() async {
      final (found, existing) = _engine.engine.presentValue(key);
      if (found) return existing as V;
      final value = await valueFactory();
      await set(key, value);
      return value;
    });
  }

  @override
  Future<V> update(
    K key,
    FutureOr<V> Function(V value) update, {
    FutureOr<V> Function()? ifAbsent,
  }) {
    return _engine.lock.synchronized(() async {
      final (found, existing) = _engine.engine.presentValue(key);
      if (found) {
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
  }

  @override
  Future<void> remove(K key) => _engine.remove(key);

  @override
  Future<void> clear() => _engine.clear();

  @override
  String toString() => _engine.toString();
}
