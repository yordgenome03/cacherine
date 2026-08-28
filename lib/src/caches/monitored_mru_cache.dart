import '../monitorings/cache_alert_manager.dart';
import '../stores/mru_store.dart';
import 'monitored_cache.dart';

/// **Async-safe MRU (Most Recently Used) Cache with Monitoring**
///
/// This class serializes concurrent async calls on the same cache instance
/// within the same isolate using `Lock`.
///
/// Additionally, by utilizing the [CacheMonitoring] mixin, it automatically **monitors cache performance**.
/// It records the following metrics and triggers alerts via the [CacheAlertManager] if thresholds are exceeded:
///
/// - **Hit rate and miss rate** (tracking the success/failure rate of cache accesses)
/// - **Request latency** (measuring the response time for cache access)
/// - **Evictions** (tracking the number of evictions due to cache size limits)
///
/// Implements the **MRU eviction policy**, meaning:
/// - When the cache size exceeds `maxSize`, the **most recently used element is removed**.
class MonitoredMRUCache<K, V> extends MonitoredCache<K, V> {
  /// **Creates a [MonitoredMRUCache] with a specified maximum size and alert configuration.**
  ///
  /// ### **Arguments:**
  /// - **[maxSize]**: The maximum size of the cache.
  ///   If this size is exceeded, the **most recently used element is removed (MRU policy).**
  /// - **[alertConfig]**: The alert configuration for cache monitoring.
  ///   Alerts will be triggered when the defined thresholds are exceeded.
  ///
  /// ### **Exceptions:**
  /// - **[ArgumentError]**: Thrown when [maxSize] is `0 or less`.
  MonitoredMRUCache({required super.maxSize, super.alertConfig})
    : super(store: MRUStore<K, V>());

  /// The maximum number of entries in the cache.
  @override
  int get maxSize => super.maxSize!;
}
