import '../stores/lru_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Async-safe LRU (Least Recently Used) Cache**
///
/// This class extends [ThreadSafeCache] and serializes concurrent async calls
/// on the same cache instance within the same isolate using `Lock`.
///
/// **Adopts an LRU (Least Recently Used) eviction policy**,
/// meaning **when the cache exceeds `maxSize`, the least recently used element is removed**.
class LRUCache<K, V> extends AsyncCache<K, V> {
  /// Creates an instance of [LRUCache] with the specified maximum size.
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the least recently used element is removed** following the LRU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  LRUCache(int maxSize)
    : super(Cache(store: LRUStore<K, V>(), maxSize: maxSize));
}
