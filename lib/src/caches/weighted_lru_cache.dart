import '../interfaces/weigher.dart';
import '../stores/lru_store.dart';
import 'async_cache.dart';
import 'cache.dart';

/// **Async-safe weight-based LRU (Least Recently Used) Cache**
///
/// Unlike [LRUCache], which only bounds the cache by entry *count*
/// (`maxSize`), this cache bounds itself by a per-entry *weight* (e.g. an
/// estimated byte size) computed by [weigher]. See [SimpleWeightedLRUCache]
/// for the eviction policy this follows.
class WeightedLRUCache<K, V> extends AsyncCache<K, V> {
  /// Creates a [WeightedLRUCache]. See [SimpleWeightedLRUCache] for the
  /// meaning of [weigher]/[maxWeight]/[maxSize] and the exceptions this can
  /// throw.
  WeightedLRUCache({
    required Weigher<K, V> weigher,
    required int maxWeight,
    int? maxSize,
  }) : super(
         Cache(
           store: LRUStore<K, V>(),
           weigher: weigher,
           maxWeight: maxWeight,
           maxSize: maxSize,
         ),
       );
}
