import 'dart:async';
import 'dart:collection';
import 'package:synchronized/synchronized.dart';

import '../interfaces/thread_safe_cache.dart';

final class _LFUNode<K, V> extends LinkedListEntry<_LFUNode<K, V>> {
  K key;
  V value;
  int freq;

  _LFUNode(this.key, this.value, this.freq);
}

/// **Async-safe LFU (Least Frequently Used) Cache**
///
/// This class extends [ThreadSafeCache] and serializes concurrent async calls
/// on the same cache instance within the same isolate using `Lock`.
///
/// **Exception:** [toString] is synchronous and does not acquire the lock.
/// It returns a point-in-time snapshot of the cache contents but is not
/// covered by the async-safety guarantee. See [toString] for details.
///
/// **Adopts an LFU (Least Frequently Used) eviction policy**,
/// meaning **when the cache exceeds `maxSize`, the least frequently used element is removed**.
class LFUCache<K, V> extends ThreadSafeCache<K, V> {
  final int maxSize;
  final HashMap<K, _LFUNode<K, V>> _keyMap = HashMap();
  final HashMap<int, LinkedList<_LFUNode<K, V>>> _freqMap = HashMap();
  int _minFreq = 0;
  final _lock = Lock();

  /// **Creates an instance of [LFUCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, **the least frequently used item is removed** following the LFU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  LFUCache(this.maxSize) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
  }

  /// Returns all keys currently stored in the cache.
  ///
  /// **Note:** The iteration order is unspecified (backed by [HashMap]).
  /// Do not rely on insertion order or any other stable ordering.
  ///
  /// **This method is async-safe.**
  @override
  Future<Iterable<K>> getKeys() async {
    return await _lock.synchronized(() => _keyMap.keys.toList());
  }

  // Increments node frequency and moves it to the next bucket. Updates _minFreq
  // if the vacated bucket was the minimum and is now empty.
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

  // Moves node to the head of its current frequency bucket (LRU recency
  // update) without changing its frequency or _minFreq. Called by set() to
  // record that the key was touched, enabling correct LRU tiebreak on eviction.
  void _refreshInBucket(_LFUNode<K, V> node) {
    final bucket = _freqMap[node.freq]!;
    node.unlink();
    bucket.addFirst(node);
  }

  /// Retrieves the value associated with the specified key and increments its usage count.
  ///
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **This method is async-safe.**
  @override
  Future<V?> get(K key) async {
    return await _lock.synchronized(() {
      final node = _keyMap[key];
      if (node == null) return null;
      _promoteFreq(node);
      return node.value;
    });
  }

  /// Retrieves [key] without incrementing its frequency.
  ///
  /// **This method is async-safe.**
  @override
  Future<V?> peek(K key) async {
    return await _lock.synchronized(() => _keyMap[key]?.value);
  }

  /// Checks whether [key] exists in the cache without incrementing its frequency.
  ///
  /// **This method is async-safe.**
  @override
  Future<bool> containsKey(K key) async {
    return await _lock.synchronized(() => _keyMap.containsKey(key));
  }

  /// Stores the specified key-value pair in the cache.
  ///
  /// - If `set()` is called on an existing key, **the value is updated**,
  ///   **its usage count is not reset**, and **its recency is refreshed**
  ///   (the entry moves to the most-recently-used position within its
  ///   frequency bucket). This means a `set()` call protects the entry from
  ///   being chosen as the eviction victim among same-frequency entries.
  /// - If the cache exceeds **[maxSize]**, the **least frequently used element is removed** following the LFU policy.
  ///   Among entries with the same frequency, the least recently used is evicted.
  ///
  /// **This method is async-safe.**
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
        assert(
          _freqMap.containsKey(_minFreq),
          'Eviction reached with stale _minFreq=$_minFreq not present in _freqMap. '
          'Any code path that triggers eviction must go through the new-key '
          'insertion branch, which resets _minFreq=1.',
        );
        final evictBucket = _freqMap[_minFreq]!;
        final victim = evictBucket.last;
        victim.unlink();
        if (evictBucket.isEmpty) _freqMap.remove(_minFreq);
        _keyMap.remove(victim.key);
      }
      final node = _LFUNode(key, value, 1);
      _keyMap[key] = node;
      _freqMap.putIfAbsent(1, LinkedList<_LFUNode<K, V>>.new).addFirst(node);
      _minFreq = 1;
    });
  }

  @override
  Future<V> getOrCompute(K key, FutureOr<V> Function() valueFactory) async {
    return await _lock.synchronized(() async {
      final existing = _keyMap[key];
      if (existing != null) {
        _promoteFreq(existing);
        return existing.value;
      }
      final value = await valueFactory();
      if (_keyMap.length >= maxSize) {
        final evictBucket = _freqMap[_minFreq]!;
        final victim = evictBucket.last;
        victim.unlink();
        if (evictBucket.isEmpty) _freqMap.remove(_minFreq);
        _keyMap.remove(victim.key);
      }
      final node = _LFUNode(key, value, 1);
      _keyMap[key] = node;
      _freqMap.putIfAbsent(1, LinkedList<_LFUNode<K, V>>.new).addFirst(node);
      _minFreq = 1;
      return value;
    });
  }

  /// Removes the entry with the given key from the cache.
  ///
  /// - If the key does not exist, this call is a no-op.
  /// - The frequency counter for the key is also discarded.
  ///
  /// **This method is async-safe.**
  @override
  Future<void> remove(K key) async {
    await _lock.synchronized(() {
      final node = _keyMap.remove(key);
      if (node == null) return;
      final bucket = _freqMap[node.freq]!;
      node.unlink();
      if (bucket.isEmpty) {
        _freqMap.remove(node.freq);
        if (_keyMap.isEmpty) _minFreq = 0;
        // If items remain, _minFreq may be stale, but set() always resets it
        // to 1 before the next eviction, so no O(n) recomputation is needed.
      }
    });
  }

  /// Clears the cache, removing all stored data.
  ///
  /// **This method is async-safe.**
  @override
  Future<void> clear() async {
    await _lock.synchronized(() {
      _keyMap.clear();
      _freqMap.clear();
      _minFreq = 0;
    });
  }

  /// Returns a string representation of the current cache state.
  ///
  /// - Outputs **key-value pairs** currently stored in the cache as a string.
  /// - The order of pairs is unspecified (backed by [HashMap]).
  ///
  /// **Note:** `toString()` is synchronous and does not acquire the internal
  /// lock — it is the one method that does not honor the async-safety
  /// contract. The snapshot of keys and values is taken atomically within
  /// Dart's single-threaded execution model, so the snapshot itself cannot
  /// race with a concurrent async operation. However, the result reflects a
  /// point-in-time view: a concurrent `set`/`remove`/`clear` that is awaiting
  /// the lock may change the cache immediately after this call returns.
  @override
  String toString() {
    return Map.fromEntries(
      _keyMap.values.toList().map((n) => MapEntry(n.key, n.value)),
    ).toString();
  }
}
