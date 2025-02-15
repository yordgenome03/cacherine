import 'dart:collection';

import 'package:synchronized/synchronized.dart';

import '../monitorings/cache_alert_manager.dart';
import '../monitorings/cache_monitoring.dart';
import '../interfaces/thread_safe_cache.dart';

/// **Thread-safe LRU (Least Recently Used) Cache with Monitoring**
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
/// This cache implements the **LRU eviction policy**, meaning:
/// - When the cache size exceeds `maxSize`, the **least recently used element is removed**.
class MonitoredLRUCache<K, V> extends ThreadSafeCache<K, V>
    with CacheMonitoring<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final _lock = Lock();

  /// Cache monitoring alert manager
  ///
  /// This manager triggers alerts when specified thresholds are exceeded.
  late final CacheAlertManager _cacheAlertManager;

  /// **Creates a [MonitoredLRUCache] with a specified maximum size and alert configuration.**
  ///
  /// This cache is thread-safe and monitors the following performance metrics:
  ///
  /// - **Hit rate and miss rate**: Tracks the success/failure rate of cache accesses.
  /// - **Request latency**: Measures the response time for cache operations.
  /// - **Evictions**: Records the number of evictions caused by the cache's size limit.
  ///
  /// Moreover, it automatically triggers alerts based on the **[alertConfig]** provided.
  ///
  /// ### **Arguments:**
  /// - **[maxSize]**: The maximum size of the cache.
  ///   If this size is exceeded, the **least recently used element is removed (LRU policy).**
  /// - **[alertConfig]**: The alert configuration for cache monitoring.
  ///   Alerts will be triggered when the defined thresholds are exceeded.
  ///
  /// ### **Exceptions:**
  /// - **[ArgumentError]**: Thrown when [maxSize] is `0 or less`.
  MonitoredLRUCache({
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
  /// **This method is thread-safe**, taking a snapshot of the cache before returning the keys.
  @override
  Iterable<K> getKeys() {
    return Map<K, V>.of(_cache).keys;
  }

  /// Retrieves the value for the specified key.
  ///
  /// - **Records cache hit/miss and measures request latency** via [CacheMonitoring].
  /// - **Implements the LRU policy**, meaning the accessed element is **moved to the end of the list**.
  /// - **Returns `null` if the key does not exist in the cache**.
  ///
  /// **This method is thread-safe**.
  @override
  Future<V?> get(K key) async {
    return await monitoredGet(key, () async {
      return await _lock.synchronized(() {
        if (!_cache.containsKey(key)) return null;
        final value = _cache.remove(key);
        if (value == null) return null;
        _cache[key] = value; // LRU: Move accessed element to the end
        return value;
      });
    });
  }

  /// Stores the specified key and value in the cache.
  ///
  /// - If the key already exists, `set()` will **update its value** and move it to the end (LRU policy).
  /// - If the cache size exceeds **[maxSize]**, the **least recently used element will be removed** following the LRU rule.
  ///
  /// **This method is thread-safe**.
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      if (_cache.containsKey(key)) {
        _cache.remove(
            key); // Remove existing key and reinsert it to update position
      } else if (_cache.length >= maxSize) {
        _cache.remove(
            _cache.keys.first); // Remove the least recently used element
      }
      _cache[key] = value;
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
  /// - Outputs **key-value pairs** currently stored in the cache as a string.
  ///
  /// **This method is thread-safe**.
  @override
  String toString() {
    final snapshot = Map.of(_cache);
    return snapshot.toString();
  }
}
