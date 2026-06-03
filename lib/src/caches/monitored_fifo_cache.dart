import 'dart:async';
import 'dart:collection';

import 'package:synchronized/synchronized.dart';

import '../monitorings/cache_alert_manager.dart';
import '../monitorings/cache_monitoring.dart';
import '../interfaces/disposable.dart';
import '../interfaces/thread_safe_cache.dart';

/// **Async-safe FIFO (First In, First Out) Cache with Monitoring**
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
/// This cache implements the **FIFO eviction policy**, and:
/// - When the cache size exceeds `maxSize`, the oldest element is removed.
class MonitoredFIFOCache<K, V> extends ThreadSafeCache<K, V>
    with CacheMonitoring<K, V>
    implements Disposable {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final _lock = Lock();

  /// Cache monitoring alert manager
  ///
  /// This manager triggers alerts when specified thresholds are exceeded.
  late final CacheAlertManager _cacheAlertManager;

  /// **Creates a [MonitoredFIFOCache] with a specified maximum size and alert configuration.**
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
  ///   If this size is exceeded, the oldest element will be removed based on the FIFO policy.
  /// - **[alertConfig]**: The alert configuration for cache monitoring.
  ///   Alerts will be triggered when the defined thresholds are exceeded.
  ///
  /// ### **Exceptions:**
  /// - **[ArgumentError]**: Thrown when [maxSize] is `0 or less`.
  MonitoredFIFOCache({required this.maxSize, CacheAlertConfig? alertConfig}) {
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
  /// - **The priority of data is not changed by FIFO** (the order of deletion is unchanged when calling `get()`).
  /// - Returns **`null` if the key does not exist in the cache**.
  ///
  /// **This method is async-safe**.
  @override
  Future<V?> get(K key) async {
    var found = false;
    return await monitoredGet(key, () async {
      return await _lock.synchronized(() {
        found = _cache.containsKey(key);
        return _cache[key];
      });
    }, found: () => found);
  }

  /// Retrieves [key] without changing FIFO order or recording metrics.
  ///
  /// **This method is async-safe**.
  @override
  Future<V?> peek(K key) async {
    return await _lock.synchronized(() => _cache[key]);
  }

  /// Checks whether [key] exists in the cache without recording hit/miss metrics.
  ///
  /// **This method is async-safe**.
  @override
  Future<bool> containsKey(K key) async {
    return await _lock.synchronized(() => _cache.containsKey(key));
  }

  /// Stores the specified key and value in the cache.
  ///
  /// - If the key already exists, `set()` will **update its value** without changing its position.
  /// - If the cache size exceeds **[maxSize]**, the oldest element will be removed based on the FIFO policy.
  ///
  /// **This method is async-safe**.
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      if (!_cache.containsKey(key) && _cache.length >= maxSize) {
        _cache.remove(
          _cache.keys.first,
        ); // Remove the oldest element based on FIFO policy
        metrics.recordEviction();
      }
      _cache[key] = value; // Update value (position remains unchanged)
    });
  }

  @override
  Future<V> getOrCompute(K key, FutureOr<V> Function() valueFactory) async {
    var found = false;
    return await monitoredGet(key, () async {
          return await _lock.synchronized(() async {
            if (_cache.containsKey(key)) {
              found = true;
              return _cache[key] as V;
            }
            final value = await valueFactory();
            if (_cache.length >= maxSize) {
              _cache.remove(_cache.keys.first);
              metrics.recordEviction();
            }
            _cache[key] = value;
            return value;
          });
        }, found: () => found)
        as V;
  }

  /// Removes the entry with the given key from the cache.
  ///
  /// - If the key existed, records a manual eviction via [CacheMonitoring].
  /// - If the key does not exist, this call is a no-op.
  ///
  /// **This method is async-safe.**
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
  /// **This method is async-safe.**
  @override
  Future<void> clear() async {
    await _lock.synchronized(_cache.clear);
  }

  @override
  void dispose() => _cacheAlertManager.dispose();

  /// Returns a string representation of the current state of the cache.
  ///
  /// - Outputs the **key-value pairs** stored in the cache.
  ///
  /// **Note:** `toString()` is synchronous and does not acquire the internal
  /// lock. Treat the result as diagnostic output for a point-in-time view.
  @override
  String toString() {
    final snapshot = Map.of(_cache); // Take a snapshot of the cache
    return snapshot.toString();
  }
}
