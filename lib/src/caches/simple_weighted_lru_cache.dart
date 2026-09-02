import '../interfaces/weigher.dart';
import '../stores/lru_store.dart';
import 'cache.dart';

/// **Non-thread-safe weight-based LRU (Least Recently Used) Cache**
///
/// Unlike [SimpleLRUCache], which only bounds the cache by entry *count*
/// (`maxSize`), this cache bounds itself by a per-entry *weight* (e.g. an
/// estimated byte size) computed by [weigher]. It follows the LRU (Least
/// Recently Used) eviction policy: when the cache's total weight would
/// exceed `maxWeight` (or, if set, when its entry count would exceed
/// `maxSize`), the least recently used entries are removed until the new
/// entry fits.
///
/// This class is designed for single-threaded use; use [WeightedLRUCache] if
/// async-safe access is needed.
class SimpleWeightedLRUCache<K, V> extends Cache<K, V> {
  /// Creates a [SimpleWeightedLRUCache].
  ///
  /// - **[weigher]**: Computes an entry's weight from its key and value.
  ///   Used by `set()` whenever no explicit `weight` is given.
  /// - **[maxWeight]**: The maximum total weight the cache may hold.
  /// - **[maxSize]**: An optional cap on the number of entries, enforced
  ///   alongside `maxWeight` — eviction is triggered whenever *either* limit
  ///   would be exceeded.
  ///
  /// **Throws [ArgumentError]** if [maxWeight] is `0` or less, or if
  /// [maxSize] is provided and is `0` or less.
  SimpleWeightedLRUCache({
    required Weigher<K, V> weigher,
    required int maxWeight,
    super.maxSize,
  }) : super(store: LRUStore<K, V>(), weigher: weigher, maxWeight: maxWeight);
}
