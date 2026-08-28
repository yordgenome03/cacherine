import '../stores/fifo_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Async-safe FIFO (First In, First Out) Cache**
///
/// This class serializes concurrent async calls on the same cache instance
/// within the same isolate using `Lock`.
///
/// **Adopts a FIFO eviction policy**,
/// meaning **when the cache exceeds `maxSize`, the oldest element is removed**.
class FIFOCache<K, V> extends AsyncCache<K, V> {
  /// **Creates an instance of [FIFOCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the oldest element is removed** following the FIFO policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  FIFOCache(int maxSize)
    : super(Cache(store: FIFOStore<K, V>(), maxSize: maxSize));

  /// The maximum number of entries in the cache.
  @override
  int get maxSize => super.maxSize!;
}
