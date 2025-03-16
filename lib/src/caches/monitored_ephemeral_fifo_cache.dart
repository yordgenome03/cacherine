import 'dart:collection';

import 'package:synchronized/synchronized.dart';

import '../monitorings/cache_alert_manager.dart';
import '../monitorings/cache_monitoring.dart';
import '../interfaces/thread_safe_cache.dart';

/// **Thread-safe Ephemeral FIFO (First In, First Out) Cache with Monitoring**
///
/// This class extends [ThreadSafeCache] and ensures thread-safety using a **`Lock`**.
/// It allows safe access to the cache from multiple threads or asynchronous tasks, preventing data race conditions.
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
class MonitoredEphemeralFIFOCache<K, V> extends ThreadSafeCache<K, V>
    with CacheMonitoring<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final _lock = Lock();

  /// Cache monitoring alert manager
  ///
  /// This manager triggers alerts when specified thresholds are exceeded.
  late final CacheAlertManager _cacheAlertManager;

  /// **Creates a [MonitoredEphemeralFIFOCache] with a specified maximum size and alert configuration.**
  ///
  /// - **[maxSize]**: The maximum size of the cache.
  ///   If this size is exceeded, the oldest element will be removed based on the FIFO policy.
  /// - **[alertConfig]**: The alert configuration for cache monitoring.
  ///   Alerts will be triggered when the defined thresholds are exceeded.
  ///
  /// **Throws an [ArgumentError] if [maxSize] is less than or equal to 0.**
  MonitoredEphemeralFIFOCache({
    required this.maxSize,
    required CacheAlertConfig alertConfig,
  }) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
    _cacheAlertManager = CacheAlertManager(metrics, alertConfig);
    _cacheAlertManager.monitor();
  }

  /// Returns all the keys currently stored in the cache.
  ///
  /// **This method is thread-safe**.
  @override
  Iterable<K> getKeys() {
    return Map<K, V>.of(_cache).keys;
  }

  /// Retrieves the value for the specified key and **removes the key from the cache**.
  ///
  /// - **Records cache hit/miss and measures request latency** via [CacheMonitoring].
  /// - **Returns `null` if the key does not exist in the cache.**
  ///
  /// **This method is thread-safe**.
  @override
  Future<V?> get(K key) async {
    return await monitoredGet(key, () async {
      return await _lock.synchronized(() {
        return _cache.remove(key); // Remove after retrieval
      });
    });
  }

  /// Stores the specified key and value in the cache.
  ///
  /// - If the key already exists, `set()` will **update its value** without changing its position.
  /// - If the cache size exceeds **[maxSize]**, the oldest element will be removed based on the FIFO policy.
  ///
  /// **This method is thread-safe**.
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      if (_cache.length >= maxSize) {
        _cache.remove(
          _cache.keys.first,
        ); // Remove the oldest element based on FIFO policy
      }
      _cache[key] = value; // Update value (position remains unchanged)
    });
  }

  /// Clears the cache and removes all data.
  ///
  /// - The monitoring function remains active even after the cache is cleared.
  ///
  /// **This method is thread-safe**.
  @override
  Future<void> clear() async {
    await _lock.synchronized(_cache.clear);
  }

  /// Returns a string representation of the current state of the cache.
  ///
  /// - Outputs the **key-value pairs** stored in the cache.
  ///
  /// **This method is thread-safe**.
  @override
  String toString() {
    final snapshot = Map.of(_cache); // Take a snapshot of the cache
    return snapshot.toString();
  }
}
