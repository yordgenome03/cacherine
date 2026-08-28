import '../stores/lfu_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Async-safe LFU (Least Frequently Used) Cache**
///
/// This class serializes concurrent async calls on the same cache instance
/// within the same isolate using `Lock`.
///
/// **Exception:** [toString] is synchronous and does not acquire the lock.
/// It returns a point-in-time snapshot of the cache contents but is not
/// covered by the async-safety guarantee. See [toString] for details.
///
/// **Adopts an LFU (Least Frequently Used) eviction policy**,
/// meaning **when the cache exceeds `maxSize`, the least frequently used element is removed**.
class LFUCache<K, V> extends AsyncCache<K, V> {
  /// **Creates an instance of [LFUCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the least frequently used item is removed** following the LFU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  LFUCache(int maxSize)
    : super(Cache(store: LFUStore<K, V>(), maxSize: maxSize));

  /// The maximum number of entries in the cache.
  @override
  int get maxSize => super.maxSize!;
}
