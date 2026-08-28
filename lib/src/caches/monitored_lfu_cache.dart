import '../monitorings/cache_alert_manager.dart';
import '../stores/lfu_store.dart';
import 'monitored_cache.dart';

/// **Async-safe LFU (Least Frequently Used) Cache with Monitoring**
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
/// This cache implements the **LFU eviction policy**, and:
/// - When the cache size exceeds `maxSize`, the **least frequently used element is removed**.
class MonitoredLFUCache<K, V> extends MonitoredCache<K, V> {
  /// **Creates a [MonitoredLFUCache] with a specified maximum size and alert configuration.**
  ///
  /// ### **Arguments:**
  /// - **[maxSize]**: The maximum size of the cache.
  ///   If this size is exceeded, the least frequently used element will be removed based on the LFU policy.
  /// - **[alertConfig]**: The alert configuration for cache monitoring.
  ///   Alerts will be triggered when the defined thresholds are exceeded.
  ///
  /// ### **Exceptions:**
  /// - **[ArgumentError]**: Thrown when [maxSize] is `0 or less`.
  MonitoredLFUCache({required super.maxSize, super.alertConfig})
    : super(store: LFUStore<K, V>());
}
