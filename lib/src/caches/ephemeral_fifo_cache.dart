import '../stores/ephemeral_fifo_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Async-safe Ephemeral FIFO (First In, First Out) Cache**
///
/// This class implements a **FIFO-based cache** with an **ephemeral property**,
/// meaning that **values are immediately removed after being retrieved**.
///
/// It serializes concurrent async calls on the same cache instance within
/// the same isolate using `Lock`.
///
/// - **Adopts FIFO (First In, First Out) eviction policy**
/// - **Removes the oldest element when the cache exceeds `maxSize`**
/// - **Removes the key from the cache upon retrieval**
///
/// ### **Note**
/// - **Retrieved data cannot be reused (as it is deleted upon access)**
/// - **If you need to retain keys after access, use `FIFOCache` instead**
class EphemeralFIFOCache<K, V> extends AsyncCache<K, V> {
  /// **Creates an instance of [EphemeralFIFOCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the oldest element is removed** following the FIFO policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  EphemeralFIFOCache(int maxSize)
    : super(Cache(store: EphemeralFIFOStore<K, V>(), maxSize: maxSize));

  /// The maximum number of entries in the cache.
  @override
  int get maxSize => super.maxSize!;
}
