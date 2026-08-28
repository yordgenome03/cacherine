import '../interfaces/weigher.dart';
import '../monitorings/cache_alert_manager.dart';
import '../stores/lru_store.dart';
import 'monitored_cache.dart';

/// **Async-safe weight-based LRU (Least Recently Used) Cache with Monitoring**
///
/// Combines [WeightedLRUCache]'s weight-bounded LRU eviction with the same
/// hit/miss/latency tracking and eviction alerting as every other
/// `Monitored*Cache` in this package. See [MonitoredCache] for the general
/// monitoring contract.
class MonitoredWeightedLRUCache<K, V> extends MonitoredCache<K, V> {
  /// Creates a [MonitoredWeightedLRUCache]. See [SimpleWeightedLRUCache] for
  /// the meaning of [weigher]/[maxWeight]/[maxSize] and the exceptions this
  /// can throw; [alertConfig] configures performance-alert thresholds.
  MonitoredWeightedLRUCache({
    required Weigher<K, V> weigher,
    required int maxWeight,
    int? maxSize,
    CacheAlertConfig? alertConfig,
  }) : super(
         store: LRUStore<K, V>(),
         weigher: weigher,
         maxWeight: maxWeight,
         maxSize: maxSize,
         alertConfig: alertConfig,
       );
}
