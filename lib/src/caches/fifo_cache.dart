import 'dart:collection';
import 'package:synchronized/synchronized.dart';

import '../interfaces/thread_safe_cache.dart';

/// **Thread-safe FIFO (First In, First Out) Cache**
///
/// This class extends [ThreadSafeCache] and ensures **thread safety using `Lock`**.
/// It allows **safe access to the cache from multiple threads or asynchronous tasks**,
/// preventing data race conditions.
///
/// **Adopts a FIFO eviction policy**,
/// meaning **when the cache exceeds `maxSize`, the oldest element is removed**.
class FIFOCache<K, V> extends ThreadSafeCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final _lock = Lock();

  /// **Creates an instance of [FIFOCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the oldest element is removed** following the FIFO policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  FIFOCache(this.maxSize) {
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
  /// - In FIFO, **the priority of data does not change** (retrieving with `get()` does not affect removal order).
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **This method is thread-safe.**
  @override
  Future<V?> get(K key) async {
    return await _lock.synchronized(() {
      return _cache[key];
    });
  }

  /// Stores the specified key-value pair in the cache.
  ///
  /// - If `set()` is called on an existing key, **the value is updated**.
  /// - The updated key is treated as **the most recent data**, but its order remains unchanged.
  /// - If the cache exceeds **[maxSize]**, the **oldest element is removed** following the FIFO policy.
  ///
  /// **This method is thread-safe.**
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      if (_cache.length >= maxSize) {
        _cache.remove(
          _cache.keys.first,
        ); // Remove the oldest element following FIFO
      }
      _cache[key] = value; // Update value (order remains unchanged)
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
