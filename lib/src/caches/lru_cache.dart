import 'dart:collection';
import 'package:synchronized/synchronized.dart';

import '../interfaces/thread_safe_cache.dart';

/// **Thread-safe LRU (Least Recently Used) Cache**
///
/// This class extends [ThreadSafeCache] and ensures **thread safety using `Lock`**.
/// It allows **safe access to the cache from multiple threads or asynchronous tasks**,
/// preventing data race conditions.
///
/// **Adopts an LRU (Least Recently Used) eviction policy**,
/// meaning **when the cache exceeds `maxSize`, the least recently used element is removed**.
class LRUCache<K, V> extends ThreadSafeCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final _lock = Lock();

  /// Creates an instance of [LRUCache] with the specified maximum size.
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the least recently used element is removed** following the LRU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  LRUCache(this.maxSize) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
  }

  /// Returns all keys currently stored in the cache.
  ///
  /// **This method is thread-safe.**
  @override
  Iterable<K> getKeys() {
    return Map<K, V>.of(_cache).keys;
  }

  /// Retrieves the value associated with the specified key.
  ///
  /// - **Uses the LRU policy**, meaning that **when a value is retrieved, the element is moved to the end of the list**.
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **This method is thread-safe.**
  @override
  Future<V?> get(K key) async {
    return await _lock.synchronized(() {
      if (!_cache.containsKey(key)) return null;
      final value = _cache.remove(key);
      if (value == null) return null;
      _cache[key] = value; // LRU: Move accessed element to the end
      return value;
    });
  }

  /// Stores the specified key-value pair in the cache.
  ///
  /// - If `set()` is called on an existing key, **its value is updated**
  ///   and moved to the end of the list following the LRU policy.
  /// - If the cache exceeds **[maxSize]**,
  ///   the **least recently used element is removed** according to the LRU rule.
  ///
  /// **This method is thread-safe.**
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      if (_cache.containsKey(key)) {
        _cache.remove(
          key,
        ); // Remove the existing key before inserting the new value
      } else if (_cache.length >= maxSize) {
        _cache.remove(
          _cache.keys.first,
        ); // Remove the least recently used element
      }
      _cache[key] = value;
    });
  }

  /// Clears all data stored in the cache.
  ///
  /// - Removes all keys and values from the cache.
  ///
  /// **This method is thread-safe.**
  @override
  Future<void> clear() async {
    await _lock.synchronized(_cache.clear);
  }

  /// Returns a string representation of the current cache state.
  ///
  /// - Outputs **key-value pairs** currently stored in the cache as a string.
  ///
  /// **This method is thread-safe.**
  @override
  String toString() {
    final snapshot = Map.of(_cache); // Take a snapshot of the cache
    return snapshot.toString();
  }
}
