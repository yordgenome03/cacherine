import 'dart:collection';
import 'package:synchronized/synchronized.dart';

import '../interfaces/thread_safe_cache.dart';

/// **Thread-safe LFU (Least Frequently Used) Cache**
///
/// This class extends [ThreadSafeCache] and ensures **thread safety using `Lock`**.
/// It allows **safe access to the cache from multiple threads or asynchronous tasks**,
/// preventing data race conditions.
///
/// **Adopts an LFU (Least Frequently Used) eviction policy**,
/// meaning **when the cache exceeds `maxSize`, the least frequently used element is removed**.
class LFUCache<K, V> extends ThreadSafeCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final Map<K, int> _usageCounts = {};
  final _lock = Lock();

  /// **Creates an instance of [LFUCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the least frequently used item is removed** following the LFU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  LFUCache(this.maxSize) {
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

  /// Retrieves the value associated with the specified key and increments its usage count.
  ///
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **This method is thread-safe.**
  @override
  Future<V?> get(K key) async {
    return await _lock.synchronized(() {
      if (!_cache.containsKey(key)) return null;

      // Increment usage count
      _usageCounts[key] = (_usageCounts[key] ?? 0) + 1;
      return _cache[key];
    });
  }

  /// Stores the specified key-value pair in the cache.
  ///
  /// - If `set()` is called on an existing key, **the value is updated**,
  ///   but **its usage count is not reset**.
  /// - If the cache exceeds **[maxSize]**, the **least frequently used element is removed** following the LFU policy.
  ///
  /// **This method is thread-safe.**
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      if (_cache.length >= maxSize) {
        _evictLFUEntry(); // Evict based on LFU policy
      }
      _cache[key] = value;
      _usageCounts[key] = 1; // Initialize with a usage count of 1
    });
  }

  /// Performs eviction based on the LFU (Least Frequently Used) policy.
  Future<void> _evictLFUEntry() async {
    if (_cache.isEmpty) return;

    // Find the key with the lowest usage count
    final K lfuKey =
        _usageCounts.entries.reduce((a, b) => a.value < b.value ? a : b).key;

    // Remove the key
    _cache.remove(lfuKey);
    _usageCounts.remove(lfuKey);
  }

  /// Clears the cache, removing all stored data.
  ///
  /// **This method is thread-safe.**
  @override
  Future<void> clear() async {
    await _lock.synchronized(() {
      _cache.clear();
      _usageCounts.clear();
    });
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
