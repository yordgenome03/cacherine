import 'dart:collection';
import '../interfaces/simple_cache.dart';

/// **Non-thread-safe MRU (Most Recently Used) Cache**
///
/// This class is designed for use in **single-threaded environments**
/// or scenarios where **concurrent access is not required**.
/// Since it is not thread-safe and does not perform synchronization,
/// **use `MRUCache` if thread safety is needed.**
///
/// It follows the MRU (Most Recently Used) eviction policy,
/// meaning **when the cache exceeds `maxSize`, the most recently used item is removed.**
class SimpleMRUCache<K, V> extends SimpleCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();

  /// **Creates an instance of [SimpleMRUCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the most recently used item** is removed following the MRU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleMRUCache(this.maxSize) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
  }

  /// Returns all keys stored in the cache.
  ///
  /// **This method is not thread-safe.**
  @override
  Iterable<K> getKeys() => _cache.keys;

  /// Retrieves the value associated with the specified key.
  ///
  /// - If the key exists, it is **marked as "most recently used"** by removing and reinserting it.
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **This method is not thread-safe.**
  @override
  V? get(K key) {
    if (!_cache.containsKey(key)) return null;

    // MRU: Remove and reinsert the key to mark it as the most recently used
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value;
    }
    return value;
  }

  /// Stores the specified key-value pair in the cache.
  ///
  /// - If `set()` is called on an existing key, **its value is updated**,
  ///   and **its order is updated to mark it as "recently used."**
  /// - If the cache exceeds **[maxSize]**, the **most recently used element is removed** following the MRU policy.
  ///
  /// **This method is not thread-safe.**
  @override
  void set(K key, V value) {
    // If the key exists, remove it to update its order
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxSize) {
      _evictMRUEntry(); // Evict using MRU policy
    }
    // Insert the key to mark it as the most recently used
    _cache[key] = value;
  }

  /// Evicts the most recently used (MRU) entry.
  void _evictMRUEntry() {
    if (_cache.isEmpty) return;

    // Remove the last added key (most recently used key)
    final K mruKey = _cache.keys.last;
    _cache.remove(mruKey);
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
