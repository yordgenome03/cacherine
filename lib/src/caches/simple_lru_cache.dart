import '../stores/lru_store.dart';
import 'cache.dart';

/// **Non-thread-safe LRU (Least Recently Used) Cache**
///
/// This class is designed for use in **single-threaded environments**
/// or scenarios where **concurrent access is not required**.
/// Since it is not thread-safe and does not perform synchronization,
/// **use `LRUCache` if thread safety is needed.**
///
/// It follows the LRU (Least Recently Used) eviction policy,
/// meaning **when the cache exceeds `maxSize`, the least recently used element is removed**.
class SimpleLRUCache<K, V> extends Cache<K, V> {
  /// Creates an instance of [SimpleLRUCache] with the specified maximum size.
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, the **least recently used element** is removed following the LRU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleLRUCache(int maxSize)
    : super(store: LRUStore<K, V>(), maxSize: maxSize);
}
