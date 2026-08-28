import '../monitorings/cache_alert_manager.dart';
import '../stores/ephemeral_fifo_store.dart';
import 'monitored_cache.dart';

/// **Async-safe Ephemeral FIFO (First In, First Out) Cache with Monitoring**
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
/// **Features of this cache**:
/// - **FIFO (First In, First Out) eviction policy**
/// - **Ephemeral nature**: Retrieved keys are removed from the cache immediately
/// - **When the cache size exceeds `maxSize`, the oldest element is removed**
///
/// ### **Note**:
/// - **The retrieved data cannot be reused (it is removed from the cache upon retrieval)**
/// - **If you need to preserve the key, use `MonitoredFIFOCache` instead.**
class MonitoredEphemeralFIFOCache<K, V> extends MonitoredCache<K, V> {
  /// **Creates a [MonitoredEphemeralFIFOCache] with a specified maximum size and alert configuration.**
  ///
  /// - **[maxSize]**: The maximum size of the cache.
  ///   If this size is exceeded, the oldest element will be removed based on the FIFO policy.
  /// - **[alertConfig]**: The alert configuration for cache monitoring.
  ///   Alerts will be triggered when the defined thresholds are exceeded.
  ///
  /// **Throws an [ArgumentError] if [maxSize] is less than or equal to 0.**
  MonitoredEphemeralFIFOCache({required super.maxSize, super.alertConfig})
    : super(store: EphemeralFIFOStore<K, V>());
}
