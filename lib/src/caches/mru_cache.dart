import '../stores/mru_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Async-safe MRU (Most Recently Used) Cache**
///
/// This class serializes concurrent async calls on the same cache instance
/// within the same isolate using `Lock`.
///
/// **Adopts the MRU (Most Recently Used) eviction policy**,
/// meaning **when the cache exceeds `maxSize`, the most recently accessed element is removed**.
class MRUCache<K, V> extends AsyncCache<K, V> {
  /// **Creates an instance of [MRUCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the most recently used element is removed** following the MRU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  MRUCache(int maxSize)
    : super(Cache(store: MRUStore<K, V>(), maxSize: maxSize));

  /// The maximum number of entries in the cache.
  @override
  int get maxSize => super.maxSize!;
}
