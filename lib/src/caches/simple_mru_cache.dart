import '../stores/mru_store.dart';
import 'cache.dart';

/// **Non-thread-safe MRU (Most Recently Used) Cache**
///
/// This class is designed for use in **single-threaded environments**
/// or scenarios where **concurrent access is not required**.
/// Since it is not thread-safe and does not perform synchronization,
/// **use `MRUCache` if thread safety is needed.**
///
/// It follows the MRU (Most Recently Used) eviction policy,
/// meaning **when the cache exceeds `maxSize`, the most recently used item is removed.**
class SimpleMRUCache<K, V> extends Cache<K, V> {
  /// **Creates an instance of [SimpleMRUCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the most recently used item** is removed following the MRU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleMRUCache(int maxSize)
    : super(store: MRUStore<K, V>(), maxSize: maxSize);
}
