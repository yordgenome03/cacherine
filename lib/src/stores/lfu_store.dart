import 'dart:collection';

import 'cache_store.dart';

final class _LFUNode<K, V> extends LinkedListEntry<_LFUNode<K, V>> {
  K key;
  V value;
  int freq;

  _LFUNode(this.key, this.value, this.freq);
}

/// [CacheStore] backing the LFU eviction policy: the entry with the lowest
/// access frequency is evicted first; entries with equal frequency break ties
/// by recency (least-recently-touched within that frequency evicted first).
///
/// Ports the frequency-bucket structure (`_keyMap` + `_freqMap` + `_minFreq`)
/// from the pre-v3 `SimpleLFUCache`/`LFUCache` unchanged, so eviction and
/// promotion stay O(1) amortized.
class LFUStore<K, V> implements CacheStore<K, V> {
  final HashMap<K, _LFUNode<K, V>> _keyMap = HashMap();
  final HashMap<int, LinkedList<_LFUNode<K, V>>> _freqMap = HashMap();
  int _minFreq = 0;

  @override
  int get length => _keyMap.length;

  @override
  Iterable<K> get keys => _keyMap.keys;

  @override
  bool containsKey(K key) => _keyMap.containsKey(key);

  @override
  V? peek(K key) => _keyMap[key]?.value;

  @override
  V? access(K key) {
    final node = _keyMap[key];
    if (node == null) return null;
    _promoteFreq(node);
    return node.value;
  }

  @override
  void put(K key, V value) {
    final existing = _keyMap[key];
    if (existing != null) {
      // Preserve frequency on update; only refresh recency within the bucket
      // (matches the pre-v3 SimpleLFUCache.set()-on-existing-key contract).
      existing.value = value;
      _refreshInBucket(existing);
      return;
    }
    final node = _LFUNode(key, value, 1);
    _keyMap[key] = node;
    _freqMap.putIfAbsent(1, LinkedList<_LFUNode<K, V>>.new).addFirst(node);
    _minFreq = 1;
  }

  // Increments node frequency and moves it to the next bucket. Updates
  // _minFreq if the vacated bucket was the minimum and is now empty.
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

  // Moves node to the head of its current frequency bucket (recency update)
  // without changing its frequency or _minFreq.
  void _refreshInBucket(_LFUNode<K, V> node) {
    final bucket = _freqMap[node.freq]!;
    node.unlink();
    bucket.addFirst(node);
  }

  @override
  K? selectVictim({K? excluding}) {
    final node = _selectVictimNode(excluding: excluding);
    return node?.key;
  }

  @override
  (K, V)? evictOne({K? excluding}) {
    final node = _selectVictimNode(excluding: excluding);
    if (node == null) return null;
    node.unlink();
    final bucket = _freqMap[node.freq]!;
    if (bucket.isEmpty) _freqMap.remove(node.freq);
    _keyMap.remove(node.key);
    return (node.key, node.value);
  }

  // Walks frequency buckets starting at _minFreq, scanning each bucket from
  // its tail (least-recently-touched) backward, so a bucket whose *only*
  // occupant is the excluded key correctly falls through to the next
  // occupied (higher) frequency bucket instead of reporting "nothing to
  // evict."
  _LFUNode<K, V>? _selectVictimNode({K? excluding}) {
    if (_keyMap.isEmpty) return null;
    var freq = _minFreq;
    while (true) {
      final bucket = _freqMap[freq];
      if (bucket != null && bucket.isNotEmpty) {
        var node = bucket.last;
        while (true) {
          if (node.key != excluding) return node;
          final prev = node.previous;
          if (prev == null) break;
          node = prev;
        }
      }
      int? nextFreq;
      for (final f in _freqMap.keys) {
        if (f > freq && (nextFreq == null || f < nextFreq)) nextFreq = f;
      }
      if (nextFreq == null) return null;
      freq = nextFreq;
    }
  }

  @override
  bool remove(K key) {
    final node = _keyMap.remove(key);
    if (node == null) return false;
    final bucket = _freqMap[node.freq]!;
    node.unlink();
    if (bucket.isEmpty) {
      _freqMap.remove(node.freq);
      if (_keyMap.isEmpty) _minFreq = 0;
      // If items remain, _minFreq may be stale, but put() always resets it to
      // 1 before the next insertion-triggered eviction, so no O(n)
      // recomputation is needed (matches the pre-v3 implementation).
    }
    return true;
  }

  @override
  void clear() {
    _keyMap.clear();
    _freqMap.clear();
    _minFreq = 0;
  }
}
