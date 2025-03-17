import 'dart:collection';
import '../interfaces/simple_cache.dart';

/// **Non-thread-safe Cache (FIFO + Removal on Retrieval)**
///
/// This class is designed for use in **single-threaded environments**
/// or scenarios where **concurrent access is not required**.
/// Since it is not thread-safe and does not perform synchronization,
/// **use `EphemeralFIFOCache` if thread safety is needed.**
///
/// Once a key is retrieved, it is removed from the cache.
/// **If you want to retain keys after retrieval, use `SimpleFIFOCache` instead.**
///
/// It follows the FIFO (First In, First Out) eviction policy,
/// meaning **when the cache exceeds `maxSize`, the oldest element is removed**.
class SimpleEphemeralFIFOCache<K, V> extends SimpleCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();

  /// Creates an instance of [SimpleEphemeralFIFOCache] with the specified maximum size.
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, the FIFO policy ensures the oldest item is removed.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleEphemeralFIFOCache(this.maxSize) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
  }

  /// Returns all keys currently stored in the cache.
  ///
  /// **This method is not thread-safe.**
  @override
  Iterable<K> getKeys() => _cache.keys;

  /// Retrieves the value associated with the specified key and **removes the key from the cache**.
  ///
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **This method is not thread-safe.**
  @override
  V? get(K key) {
    return _cache.remove(key); // Remove after retrieval
  }

  /// Stores the specified key-value pair in the cache.
  ///
  /// - If `set()` is called on an existing key, **its value is updated**.
  /// - The updated key is treated as **the most recent data**, but its order remains unchanged.
  /// - If the cache exceeds **[maxSize]**, the **oldest element is removed** following the FIFO policy.
  ///
  /// **This method is not thread-safe.**
  @override
  void set(K key, V value) {
    if (_cache.length >= maxSize) {
      _cache.remove(
        _cache.keys.first,
      ); // Remove the oldest element following FIFO
    }
    _cache[key] = value; // Update value (order remains unchanged)
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
