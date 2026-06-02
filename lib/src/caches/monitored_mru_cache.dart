import 'dart:collection';
import 'package:synchronized/synchronized.dart';

import '../monitorings/cache_alert_manager.dart';
import '../monitorings/cache_monitoring.dart';
import '../interfaces/disposable.dart';
import '../interfaces/thread_safe_cache.dart';

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
class MonitoredMRUCache<K, V> extends ThreadSafeCache<K, V>
    with CacheMonitoring<K, V>
    implements Disposable {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final _lock = Lock();

  /// Cache monitoring alert manager
  ///
  /// This manager triggers alerts when specified thresholds are exceeded.
  late final CacheAlertManager _cacheAlertManager;

  /// **Creates a [MonitoredMRUCache] with a specified maximum size and alert configuration.**
  ///
  /// This cache is async-safe and monitors the following performance metrics:
  ///
  /// - **Hit rate and miss rate**: Tracks the success/failure rate of cache accesses.
  /// - **Request latency**: Measures the response time for cache operations.
  /// - **Evictions**: Records the number of evictions caused by the cache's size limit.
  ///
  /// Moreover, it automatically triggers alerts based on the **[alertConfig]** provided.
  ///
  /// ### **Arguments:**
  /// - **[maxSize]**: The maximum size of the cache.
  ///   If this size is exceeded, the **most recently used element is removed (MRU policy).**
  /// - **[alertConfig]**: The alert configuration for cache monitoring.
  ///   Alerts will be triggered when the defined thresholds are exceeded.
  ///
  /// ### **Exceptions:**
  /// - **[ArgumentError]**: Thrown when [maxSize] is `0 or less`.
  MonitoredMRUCache({
    required this.maxSize,
    CacheAlertConfig alertConfig = const CacheAlertConfig(),
  }) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
    _cacheAlertManager = CacheAlertManager(metrics, alertConfig);
    _cacheAlertManager.monitor();
  }

  /// Returns all keys currently stored in the cache.
  ///
  /// **This method is async-safe**.
  @override
  Future<Iterable<K>> getKeys() async {
    return await _lock.synchronized(() {
      return Map<K, V>.of(_cache).keys;
    });
  }

  /// Retrieves the value for the specified key.
  ///
  /// - **Records cache hit/miss and measures request latency** via [CacheMonitoring].
  /// - **If the key exists, it is removed and reinserted to mark it as "recently used".**
  /// - **Returns `null` if the key does not exist in the cache.**
  ///
  /// **This method is async-safe**.
  @override
  Future<V?> get(K key) async {
    return await monitoredGet(key, () async {
      return await _lock.synchronized(() {
        if (!_cache.containsKey(key)) return null;

        final value = _cache.remove(key);
        if (value != null) {
          _cache[key] = value; // MRU: Reinsert to mark as "recently used"
        }
        return value;
      });
    });
  }

  /// Stores the specified key and value in the cache.
  ///
  /// - If the key already exists, `set()` will **update its value** and move it to the most recently used position.
  /// - If the cache size exceeds **[maxSize]**, the **most recently used element will be removed** based on the MRU policy.
  ///
  /// **This method is async-safe**.
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      // If the key exists, remove it to update its order
      if (_cache.containsKey(key)) {
        _cache.remove(key);
      } else if (_cache.length >= maxSize) {
        _evictMRUEntry(); // Perform eviction using MRU policy
        metrics.recordEviction();
      }
      // Insert the key to mark it as the most recently used
      _cache[key] = value;
    });
  }

  /// Performs eviction (removal) using the MRU (Most Recently Used) policy.
  void _evictMRUEntry() {
    if (_cache.isEmpty) return;

    // Remove the last added key (most recently used key)
    final K mruKey = _cache.keys.last;
    _cache.remove(mruKey);
  }

  /// Removes the entry with the given key from the cache.
  ///
  /// - If the key existed, records a manual eviction via [CacheMonitoring].
  /// - If the key does not exist, this call is a no-op.
  ///
  /// **This method is async-safe**.
  @override
  Future<void> remove(K key) async {
    await _lock.synchronized(() {
      if (_cache.containsKey(key)) {
        _cache.remove(key);
        metrics.recordEviction();
      }
    });
  }

  /// Clears the cache and removes all data.
  ///
  /// - The monitoring function remains active even after the cache is cleared.
  ///
  /// **This method is async-safe**.
  @override
  Future<void> clear() async {
    await _lock.synchronized(_cache.clear);
  }

  @override
  void dispose() => _cacheAlertManager.dispose();

  /// Returns a string representation of the current state of the cache.
  ///
  /// - Outputs **key-value pairs** currently stored in the cache as a string.
  ///
  /// **Note:** `toString()` is synchronous and does not acquire the internal
  /// lock. Treat the result as diagnostic output for a point-in-time view.
  @override
  String toString() {
    final snapshot = Map.of(_cache);
    return snapshot.toString();
  }
}
