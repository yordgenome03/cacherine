import 'dart:collection';

import '../interfaces/simple_cache.dart';

/// **Non-thread-safe LRU (Least Recently Used) Cache**
///
/// This class is designed for use in **single-threaded environments**
/// or scenarios where **concurrent access is not required**.
/// Since it is not thread-safe and does not perform synchronization,
/// **use `LRUCache` if thread safety is needed.**
///
/// It follows the LRU (Least Recently Used) eviction policy,
/// meaning **when the cache exceeds `maxSize`, the least recently used element is removed**.
class SimpleLRUCache<K, V> extends SimpleCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();

  /// Creates an instance of [SimpleLRUCache] with the specified maximum size.
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, the **least recently used element** is removed following the LRU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleLRUCache(this.maxSize) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
  }

  /// Returns all keys currently stored in the cache.
  ///
  /// **This method is not thread-safe.**
  @override
  Iterable<K> getKeys() => _cache.keys;

  /// Retrieves the value associated with the specified key.
  ///
  /// - **Uses the LRU policy**, meaning that **when a value is retrieved, the element is moved to the end of the list**.
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **This method is not thread-safe.**
  @override
  V? get(K key) {
    if (!_cache.containsKey(key)) return null;
    final value = _cache.remove(key);
    if (value == null) return null;
    _cache[key] = value; // LRU: Move accessed element to the end
    return value;
  }

  /// Stores the specified key-value pair in the cache.
  ///
  /// - If `set()` is called on an existing key, **its value is updated**
  ///   and moved to the end of the list following the LRU policy.
  /// - If the cache exceeds **[maxSize]**, the **least recently used element is removed** following the LRU policy.
  ///
  /// **This method is not thread-safe.**
  @override
  void set(K key, V value) {
    if (_cache.containsKey(key)) {
      _cache.remove(
        key,
      ); // Remove the existing key before inserting the new value
    } else if (_cache.length >= maxSize) {
      _cache.remove(
        _cache.keys.first,
      ); // Remove the least recently used element following LRU
    }
    _cache[key] = value;
  }

  /// Clears all data stored in the cache.
  ///
  /// - Removes all keys and values from the cache.
  ///
  /// **This method is not thread-safe.**
  @override
  void clear() {
    _cache.clear();
  }

  /// Returns a string representation of the current cache state.
  ///
  /// - Outputs **key-value pairs** currently stored in the cache as a string.
  ///
  /// **This method is not thread-safe.**
  @override
  String toString() {
    return _cache.toString();
  }
}
