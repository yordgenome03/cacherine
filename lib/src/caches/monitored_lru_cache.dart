import 'dart:collection';

import 'package:synchronized/synchronized.dart';

import '../monitorings/cache_alert_manager.dart';
import '../monitorings/cache_monitoring.dart';
import '../interfaces/disposable.dart';
import '../interfaces/thread_safe_cache.dart';

/// **Async-safe LRU (Least Recently Used) Cache with Monitoring**
///
/// This class extends [ThreadSafeCache] and serializes concurrent async calls
/// on the same cache instance within the same isolate using `Lock`.
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
    with CacheMonitoring<K, V>
    implements Disposable {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final _lock = Lock();

  /// Cache monitoring alert manager
  ///
  /// This manager triggers alerts when specified thresholds are exceeded.
  late final CacheAlertManager _cacheAlertManager;

  /// **Creates a [MonitoredLRUCache] with a specified maximum size and alert configuration.**
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
  ///   If this size is exceeded, the **least recently used element is removed (LRU policy).**
  /// - **[alertConfig]**: The alert configuration for cache monitoring.
  ///   Alerts will be triggered when the defined thresholds are exceeded.
  ///
  /// ### **Exceptions:**
  /// - **[ArgumentError]**: Thrown when [maxSize] is `0 or less`.
  MonitoredLRUCache({required this.maxSize, CacheAlertConfig? alertConfig}) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
    _cacheAlertManager = CacheAlertManager(
      metrics,
      alertConfig ?? CacheAlertConfig(),
    );
    _cacheAlertManager.monitor();
  }

  /// Returns all the keys currently stored in the cache.
  ///
  /// **This method is async-safe**, taking a snapshot of the cache before returning the keys.
  @override
  Future<Iterable<K>> getKeys() async {
    return await _lock.synchronized(() {
      return Map<K, V>.of(_cache).keys;
    });
  }

  /// Retrieves the value for the specified key.
  ///
  /// - **Records cache hit/miss and measures request latency** via [CacheMonitoring].
  /// - **Implements the LRU policy**, meaning the accessed element is **moved to the end of the list**.
  /// - **Returns `null` if the key does not exist in the cache**.
  ///
  /// **This method is async-safe**.
  @override
  Future<V?> get(K key) async {
    var found = false;
    return await monitoredGet(key, () async {
      return await _lock.synchronized(() {
        if (!_cache.containsKey(key)) return null;
        found = true;
        final value = _cache.remove(key);
        _cache[key] = value as V; // LRU: Move accessed element to the end
        return value;
      });
    }, found: () => found);
  }

  /// Stores the specified key and value in the cache.
  ///
  /// - If the key already exists, `set()` will **update its value** and move it to the end (LRU policy).
  /// - If the cache size exceeds **[maxSize]**, the **least recently used element will be removed** following the LRU rule.
  ///
  /// **This method is async-safe**.
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      if (_cache.containsKey(key)) {
        _cache.remove(
          key,
        ); // Remove existing key and reinsert it to update position
      } else if (_cache.length >= maxSize) {
        _cache.remove(
          _cache.keys.first,
        ); // Remove the least recently used element
        metrics.recordEviction();
      }
      _cache[key] = value;
    });
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
