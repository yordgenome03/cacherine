import '../stores/fifo_store.dart';
import 'cache.dart';

/// **Non-thread-safe FIFO (First In, First Out) Cache**
///
/// This class is designed for use in **single-threaded environments**
/// or scenarios where **concurrent access is not required**.
/// Since it is not thread-safe and does not perform synchronization,
/// **use `FIFOCache` if thread safety is needed.**
///
/// It follows the FIFO (First In, First Out) eviction policy,
/// meaning **when the cache exceeds `maxSize`, the oldest element is removed**.
class SimpleFIFOCache<K, V> extends Cache<K, V> {
  /// Creates an instance of [SimpleFIFOCache] with the specified maximum size.
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, the FIFO policy ensures the oldest element is removed.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleFIFOCache(int maxSize)
    : super(store: FIFOStore<K, V>(), maxSize: maxSize);
}
