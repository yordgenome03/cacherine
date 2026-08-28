import '../stores/ephemeral_fifo_store.dart';
import 'cache.dart';

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
class SimpleEphemeralFIFOCache<K, V> extends Cache<K, V> {
  /// Creates an instance of [SimpleEphemeralFIFOCache] with the specified maximum size.
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, the FIFO policy ensures the oldest item is removed.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleEphemeralFIFOCache(int maxSize)
    : super(store: EphemeralFIFOStore<K, V>(), maxSize: maxSize);

  /// The maximum number of entries in the cache.
  @override
  int get maxSize => super.maxSize!;
}
