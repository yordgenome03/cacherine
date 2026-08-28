import '../stores/lfu_store.dart';
import 'cache.dart';

/// **Non-thread-safe LFU (Least Frequently Used) Cache**
///
/// This class is designed for use in **single-threaded environments**
/// or scenarios where **concurrent access is not required**.
/// Since it is not thread-safe and does not perform synchronization,
/// **use `LFUCache` if thread safety is needed.**
///
/// It follows the LFU (Least Frequently Used) eviction policy,
/// meaning **when the cache exceeds `maxSize`, the least frequently used item is removed.**
class SimpleLFUCache<K, V> extends Cache<K, V> {
  /// **Creates an instance of [SimpleLFUCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, the **least frequently used item** is removed following the LFU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleLFUCache(int maxSize)
    : super(store: LFUStore<K, V>(), maxSize: maxSize);

  /// The maximum number of entries in the cache.
  @override
  int get maxSize => super.maxSize!;
}
