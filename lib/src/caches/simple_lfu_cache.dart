import 'dart:collection';

import '../interfaces/simple_cache.dart';

/// **Non-thread-safe LFU (Least Frequently Used) Cache**
///
/// This class is designed for use in **single-threaded environments**
/// or scenarios where **concurrent access is not required**.
/// Since it is not thread-safe and does not perform synchronization,
/// **use `LFUCache` if thread safety is needed.**
///
/// It follows the LFU (Least Frequently Used) eviction policy,
/// meaning **when the cache exceeds `maxSize`, the least frequently used item is removed.**
class SimpleLFUCache<K, V> extends SimpleCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final Map<K, int> _usageCounts = {};

  /// **Creates an instance of [SimpleLFUCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, the **least frequently used item** is removed following the LFU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleLFUCache(this.maxSize) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
  }

  /// Returns all keys currently stored in the cache.
  ///
  /// **This method is not thread-safe.**
  @override
  Iterable<K> getKeys() => _cache.keys;

  /// Retrieves the value associated with the specified key and increments its access count.
  ///
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **This method is not thread-safe.**
  @override
  V? get(K key) {
    if (!_cache.containsKey(key)) return null;

    // Increment usage count
    _usageCounts[key] = (_usageCounts[key] ?? 0) + 1;
    return _cache[key];
  }

  /// Stores the specified key-value pair in the cache.
  ///
  /// - If `set()` is called on an existing key, **its value is updated**,
  ///   but **its usage count is not reset**.
  /// - If the cache exceeds **[maxSize]**, the **least frequently used element is removed** following the LFU policy.
  ///
  /// **This method is not thread-safe.**
  @override
  void set(K key, V value) {
    if (_cache.length >= maxSize) {
      _evictLFUEntry(); // Evict based on LFU policy
    }
    _cache[key] = value;
    _usageCounts[key] = 1; // Initialize with a usage count of 1
  }

  /// **Evicts the least frequently used (LFU) entry.**
  void _evictLFUEntry() {
    if (_cache.isEmpty) return;

    // Find the key with the lowest usage count
    final K lfuKey = _usageCounts.entries
        .reduce(
          (a, b) => a.value < b.value ? a : b,
        )
        .key;

    // Remove the key
    _cache.remove(lfuKey);
    _usageCounts.remove(lfuKey);
  }

  /// Clears all data stored in the cache.
  ///
  /// - Removes all keys and values from the cache.
  ///
  /// **This method is not thread-safe.**
  @override
  void clear() {
    _cache.clear();
    _usageCounts.clear();
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
