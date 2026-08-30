import 'dart:async';

import '../interfaces/thread_safe_cache.dart';
import '../stores/lru_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Async-safe LRU (Least Recently Used) Cache**
///
/// This class extends [ThreadSafeCache] and serializes concurrent async calls
/// on the same cache instance within the same isolate using `Lock`.
///
/// **Adopts an LRU (Least Recently Used) eviction policy**,
/// meaning **when the cache exceeds `maxSize`, the least recently used element is removed**.
///
/// Wraps an [AsyncCache] configured with an [LRUStore] — internally a
/// composed engine rather than a subclass, so this class keeps its original
/// `set`/`getOrCompute`/`update`/`setAll` signatures (no `weight`/`ttl`
/// parameters) rather than inheriting [AsyncCache]'s wider ones.
class LRUCache<K, V> extends ThreadSafeCache<K, V> {
  final AsyncCache<K, V> _engine;

  /// Creates an instance of [LRUCache] with the specified maximum size.
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the least recently used element is removed** following the LRU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  LRUCache(int maxSize)
    : _engine = AsyncCache(Cache(store: LRUStore<K, V>(), maxSize: maxSize));

  /// The maximum number of entries in the cache.
  int get maxSize => _engine.maxSize!;

  @override
  Future<Iterable<K>> getKeys() => _engine.getKeys();

  @override
  Future<V?> get(K key) => _engine.get(key);

  @override
  Future<Map<K, V>> getAll(Iterable<K> keys) => _engine.getAll(keys);

  @override
  Future<V?> peek(K key) => _engine.peek(key);

  @override
  Future<bool> containsKey(K key) => _engine.containsKey(key);

  @override
  Future<void> set(K key, V value) => _engine.set(key, value);

  @override
  Future<void> setAll(Map<K, V> entries) => _engine.setAll(entries);

  @override
  Future<V> getOrCompute(K key, FutureOr<V> Function() valueFactory) =>
      _engine.getOrCompute(key, valueFactory);

  @override
  Future<V> update(
    K key,
    FutureOr<V> Function(V value) update, {
    FutureOr<V> Function()? ifAbsent,
  }) => _engine.update(key, update, ifAbsent: ifAbsent);

  @override
  Future<void> remove(K key) => _engine.remove(key);

  @override
  Future<void> removeWhere(FutureOr<bool> Function(K key, V value) test) =>
      _engine.removeWhere(test);

  @override
  Future<void> clear() => _engine.clear();

  @override
  String toString() => _engine.toString();
}
