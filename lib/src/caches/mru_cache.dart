import 'dart:collection';
import 'package:synchronized/synchronized.dart';

import '../interfaces/thread_safe_cache.dart';

/// **Thread-safe MRU (Most Recently Used) Cache**
///
/// This class ensures **thread safety using `Lock`**,
/// allowing **safe access to the cache from multiple threads or asynchronous tasks**
/// while preventing data race conditions.
///
/// **Adopts the MRU (Most Recently Used) eviction policy**,
/// meaning **when the cache exceeds `maxSize`, the most recently accessed element is removed**.
class MRUCache<K, V> extends ThreadSafeCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final _lock = Lock();

  /// **Creates an instance of [MRUCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the most recently used element is removed** following the MRU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  MRUCache(this.maxSize) {
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

  /// **Retrieves the value associated with the specified key.**
  ///
  /// - **If the key exists, it is removed and reinserted to mark it as "recently used."**
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **This method is thread-safe.**
  @override
  Future<V?> get(K key) async {
    return await _lock.synchronized(() {
      if (!_cache.containsKey(key)) return null;

      final value = _cache.remove(key);
      if (value != null) {
        _cache[key] = value; // MRU: Reinsert to record "recently used" status
      }
      return value;
    });
  }

  /// **Stores the specified key-value pair in the cache.**
  ///
  /// - If `set()` is called on an existing key, **its value is updated**,
  ///   and **its order is updated to mark it as "recently used."**
  /// - If the cache exceeds **[maxSize]**, the **most recently used element is removed** following the MRU policy.
  ///
  /// **This method is thread-safe.**
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      // If the key already exists, remove it to update its order
      if (_cache.containsKey(key)) {
        _cache.remove(key);
      } else if (_cache.length >= maxSize) {
        _evictMRUEntry(); // Evict using MRU policy
      }
      // Insert the key to mark it as the most recently used
      _cache[key] = value;
    });
  }

  /// **Evicts the most recently used (MRU) entry.**
  Future<void> _evictMRUEntry() async {
    if (_cache.isEmpty) return;

    // Remove the last added key (most recently used key)
    final K mruKey = _cache.keys.last;
    _cache.remove(mruKey);
  }

  /// Clears the cache, removing all stored data.
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
