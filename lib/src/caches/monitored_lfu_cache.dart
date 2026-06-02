import 'dart:collection';
import 'package:synchronized/synchronized.dart';

import '../monitorings/cache_alert_manager.dart';
import '../monitorings/cache_monitoring.dart';
import '../interfaces/disposable.dart';
import '../interfaces/thread_safe_cache.dart';

final class _LFUNode<K, V> extends LinkedListEntry<_LFUNode<K, V>> {
  K key;
  V value;
  int freq;

  _LFUNode(this.key, this.value, this.freq);
}

/// **Async-safe LFU (Least Frequently Used) Cache with Monitoring**
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
/// This cache implements the **LFU eviction policy**, and:
/// - When the cache size exceeds `maxSize`, the **least frequently used element is removed**.
class MonitoredLFUCache<K, V> extends ThreadSafeCache<K, V>
    with CacheMonitoring<K, V>
    implements Disposable {
  final int maxSize;
  final HashMap<K, _LFUNode<K, V>> _keyMap = HashMap();
  final HashMap<int, LinkedList<_LFUNode<K, V>>> _freqMap = HashMap();
  int _minFreq = 0;
  final _lock = Lock();

  /// Cache monitoring alert manager
  ///
  /// This manager triggers alerts when specified thresholds are exceeded.
  late final CacheAlertManager _cacheAlertManager;

  /// **Creates a [MonitoredLFUCache] with a specified maximum size and alert configuration.**
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
  ///   If this size is exceeded, the least frequently used element will be removed based on the LFU policy.
  /// - **[alertConfig]**: The alert configuration for cache monitoring.
  ///   Alerts will be triggered when the defined thresholds are exceeded.
  ///
  /// ### **Exceptions:**
  /// - **[ArgumentError]**: Thrown when [maxSize] is `0 or less`.
  MonitoredLFUCache({
    required this.maxSize,
    CacheAlertConfig alertConfig = const CacheAlertConfig(),
  }) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
    _cacheAlertManager = CacheAlertManager(metrics, alertConfig);
    _cacheAlertManager.monitor();
  }

  /// Returns all the keys currently stored in the cache.
  ///
  /// **This method is async-safe**, taking a snapshot of the cache before returning the keys.
  @override
  Future<Iterable<K>> getKeys() async {
    return await _lock.synchronized(() {
      return _keyMap.keys.toList();
    });
  }

  void _promoteFreq(_LFUNode<K, V> node) {
    final oldFreq = node.freq;
    final oldBucket = _freqMap[oldFreq]!;
    node.unlink();
    if (oldBucket.isEmpty) {
      _freqMap.remove(oldFreq);
      if (oldFreq == _minFreq) _minFreq = oldFreq + 1;
    }
    node.freq = oldFreq + 1;
    _freqMap
        .putIfAbsent(node.freq, LinkedList<_LFUNode<K, V>>.new)
        .addFirst(node);
  }

  void _refreshInBucket(_LFUNode<K, V> node) {
    final bucket = _freqMap[node.freq]!;
    node.unlink();
    bucket.addFirst(node);
  }

  /// Retrieves the value for the specified key and increments its usage count.
  ///
  /// - **Records cache hit/miss and measures request latency** via [CacheMonitoring].
  /// - **Returns `null` if the key does not exist in the cache**.
  ///
  /// **This method is async-safe**.
  @override
  Future<V?> get(K key) async {
    return await monitoredGet(key, () async {
      return await _lock.synchronized(() {
        final node = _keyMap[key];
        if (node == null) return null;
        _promoteFreq(node);
        return node.value;
      });
    });
  }

  /// Stores the specified key and value in the cache.
  ///
  /// - If the key already exists, `set()` will **update its value** without resetting its usage count.
  /// - If the cache size exceeds **[maxSize]**, the least frequently used element will be removed based on the LFU policy.
  ///
  /// **This method is async-safe**.
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      final existing = _keyMap[key];
      if (existing != null) {
        existing.value = value;
        _refreshInBucket(existing);
        return;
      }
      if (_keyMap.length >= maxSize) {
        _evictLFUEntry();
        metrics.recordEviction();
      }
      final node = _LFUNode(key, value, 1);
      _keyMap[key] = node;
      _freqMap.putIfAbsent(1, LinkedList<_LFUNode<K, V>>.new).addFirst(node);
      _minFreq = 1;
    });
  }

  /// Performs eviction using the LFU (Least Frequently Used) policy.
  void _evictLFUEntry() {
    if (_keyMap.isEmpty) return;

    final evictBucket = _freqMap[_minFreq]!;
    final victim = evictBucket.last;
    victim.unlink();
    if (evictBucket.isEmpty) _freqMap.remove(_minFreq);
    _keyMap.remove(victim.key);
  }

  /// Removes the entry with the given key from the cache.
  ///
  /// - If the key existed, records a manual eviction via [CacheMonitoring].
  /// - If the key does not exist, this call is a no-op.
  /// - The frequency counter for the key is also discarded.
  ///
  /// **This method is async-safe**.
  @override
  Future<void> remove(K key) async {
    await _lock.synchronized(() {
      final node = _keyMap.remove(key);
      if (node != null) {
        final bucket = _freqMap[node.freq]!;
        node.unlink();
        if (bucket.isEmpty) {
          _freqMap.remove(node.freq);
          if (_keyMap.isEmpty) _minFreq = 0;
        }
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
    await _lock.synchronized(() {
      _keyMap.clear();
      _freqMap.clear();
      _minFreq = 0;
    });
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
    return Map.fromEntries(
      _keyMap.values.toList().map((node) => MapEntry(node.key, node.value)),
    ).toString();
  }
}
