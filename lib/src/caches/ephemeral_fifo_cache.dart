import 'dart:collection';
import 'package:synchronized/synchronized.dart';

import '../interfaces/thread_safe_cache.dart';

/// **Async-safe Ephemeral FIFO (First In, First Out) Cache**
///
/// This class implements a **FIFO-based cache** with an **ephemeral property**,
/// meaning that **values are immediately removed after being retrieved**.
///
/// It extends [ThreadSafeCache] and serializes concurrent async calls on the
/// same cache instance within the same isolate using `Lock`.
///
/// - **Adopts FIFO (First In, First Out) eviction policy**
/// - **Removes the oldest element when the cache exceeds `maxSize`**
/// - **Removes the key from the cache upon retrieval**
///
/// ### **Note**
/// - **Retrieved data cannot be reused (as it is deleted upon access)**
/// - **If you need to retain keys after access, use `FIFOCache` instead**
class EphemeralFIFOCache<K, V> extends ThreadSafeCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final _lock = Lock();

  /// **Creates an instance of [EphemeralFIFOCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the oldest element is removed** following the FIFO policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  EphemeralFIFOCache(this.maxSize) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
  }

  /// Returns all keys currently stored in the cache.
  ///
  /// **This method is async-safe.**
  @override
  Future<Iterable<K>> getKeys() async {
    return await _lock.synchronized(() {
      return Map<K, V>.of(_cache).keys;
    });
  }

  /// Retrieves the value associated with the specified key and **removes the key from the cache**.
  ///
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **This method is async-safe.**
  @override
  Future<V?> get(K key) async {
    return await _lock.synchronized(() {
      return _cache.remove(key); // Remove after retrieval
    });
  }

  /// Checks whether [key] exists in the cache without removing it.
  ///
  /// **This method is async-safe.**
  @override
  Future<bool> containsKey(K key) async {
    return await _lock.synchronized(() => _cache.containsKey(key));
  }

  /// Stores the specified key-value pair in the cache.
  ///
  /// - If the key already exists, **the value is updated**.
  /// - The updated key is treated as the **most recently added data**, but its order remains unchanged.
  /// - If the cache exceeds **[maxSize]**, the **oldest element is removed** according to the FIFO policy.
  ///
  /// **This method is async-safe.**
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      if (!_cache.containsKey(key) && _cache.length >= maxSize) {
        _cache.remove(
          _cache.keys.first,
        ); // Remove the oldest element following FIFO
      }
      _cache[key] = value; // Update value (order remains unchanged)
    });
  }

  /// Removes the entry with the given key from the cache.
  ///
  /// - If the key does not exist, this call is a no-op.
  ///
  /// **This method is async-safe.**
  @override
  Future<void> remove(K key) async {
    await _lock.synchronized(() {
      _cache.remove(key);
    });
  }

  /// Clears all data stored in the cache.
  ///
  /// - Removes all keys and values from the cache.
  ///
  /// **This method is async-safe.**
  @override
  Future<void> clear() async {
    await _lock.synchronized(_cache.clear);
  }

  /// Returns a string representation of the current cache state.
  ///
  /// - Outputs **key-value pairs** currently stored in the cache as a string.
  ///
  /// **Note:** `toString()` is synchronous and does not acquire the internal
  /// lock. Treat the result as diagnostic output for a point-in-time view.
  @override
  String toString() {
    final snapshot = Map.of(_cache); // Take a snapshot of the cache
    return snapshot.toString();
  }
}
