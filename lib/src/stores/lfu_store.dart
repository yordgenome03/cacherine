import 'dart:collection';

import 'cache_store.dart';

final class _LFUNode<K, V> extends LinkedListEntry<_LFUNode<K, V>> {
  K key;
  V value;
  int freq;

  _LFUNode(this.key, this.value, this.freq);
}

/// A bucket of same-frequency nodes, itself a node in [LFUStore._bucketList]
/// (kept sorted ascending by [freq]). Chaining buckets this way — rather than
/// keying them in a plain map and rescanning for "next occupied frequency" —
/// is what keeps eviction O(1): a promotion from frequency `f` only ever
/// needs the `f + 1` bucket, which (being the next integer) is always
/// adjacent to `f`'s bucket in this list whenever it must be created.
final class _FreqBucket<K, V> extends LinkedListEntry<_FreqBucket<K, V>> {
  final int freq;
  final LinkedList<_LFUNode<K, V>> nodes = LinkedList();

  _FreqBucket(this.freq);
}

/// [CacheStore] backing the LFU eviction policy: the entry with the lowest
/// access frequency is evicted first; entries with equal frequency break ties
/// by recency (least-recently-touched within that frequency evicted first).
///
/// Frequency buckets are chained into their own doubly-linked list
/// (`_bucketList`, ascending by frequency, indexed by `_bucketByFreq` for O(1)
/// lookup), rather than keyed in a plain map with an O(distinct frequencies)
/// scan to find the next occupied one. Because promotion always moves a node
/// from frequency `f` to `f + 1`, a newly-needed `f + 1` bucket is always
/// inserted immediately after `f`'s bucket — no integer frequency can exist
/// between them — so eviction/promotion/selection are all O(1) worst case,
/// including with an `excluding` key (only possible via the composable
/// `Cache` engine's weight/TTL-driven eviction loop): a bucket whose only
/// occupant is the excluded key is simply skipped via `bucket.next`, no
/// rescan required.
class LFUStore<K, V> implements CacheStore<K, V> {
  final HashMap<K, _LFUNode<K, V>> _keyMap = HashMap();
  final HashMap<int, _FreqBucket<K, V>> _bucketByFreq = HashMap();
  final LinkedList<_FreqBucket<K, V>> _bucketList = LinkedList();

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
  bool get removesOnAccess => false;

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
    var bucket = _bucketByFreq[1];
    if (bucket == null) {
      bucket = _FreqBucket(1);
      _bucketByFreq[1] = bucket;
      _bucketList.addFirst(bucket); // freq 1 is always the global minimum
    }
    bucket.nodes.addFirst(node);
  }

  // Increments node frequency and moves it to the next bucket, creating that
  // bucket (immediately after the current one) if it doesn't exist yet.
  void _promoteFreq(_LFUNode<K, V> node) {
    final oldFreq = node.freq;
    final oldBucket = _bucketByFreq[oldFreq]!;
    node.unlink();

    final newFreq = oldFreq + 1;
    var newBucket = _bucketByFreq[newFreq];
    if (newBucket == null) {
      newBucket = _FreqBucket(newFreq);
      oldBucket.insertAfter(newBucket);
      _bucketByFreq[newFreq] = newBucket;
    }
    node.freq = newFreq;
    newBucket.nodes.addFirst(node);

    if (oldBucket.nodes.isEmpty) {
      _bucketByFreq.remove(oldFreq);
      oldBucket.unlink();
    }
  }

  // Moves node to the head of its current frequency bucket (recency update)
  // without changing its frequency.
  void _refreshInBucket(_LFUNode<K, V> node) {
    final bucket = _bucketByFreq[node.freq]!;
    node.unlink();
    bucket.nodes.addFirst(node);
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
    _removeNode(node);
    return (node.key, node.value);
  }

  // Walks frequency buckets starting at the lowest occupied one, scanning
  // each bucket from its tail (least-recently-touched) backward, so a bucket
  // whose *only* occupant is the excluded key correctly falls through to
  // `bucket.next` — the next occupied (higher) frequency bucket — instead of
  // reporting "nothing to evict." Since `excluding` is a single key, it can
  // block at most one bucket, so this is O(1) worst case, not a rescan.
  _LFUNode<K, V>? _selectVictimNode({K? excluding}) {
    var bucket = _bucketList.isEmpty ? null : _bucketList.first;
    while (bucket != null) {
      var node = bucket.nodes.isEmpty ? null : bucket.nodes.last;
      while (node != null) {
        if (node.key != excluding) return node;
        node = node.previous;
      }
      bucket = bucket.next;
    }
    return null;
  }

  void _removeNode(_LFUNode<K, V> node) {
    final bucket = _bucketByFreq[node.freq]!;
    node.unlink();
    _keyMap.remove(node.key);
    if (bucket.nodes.isEmpty) {
      _bucketByFreq.remove(node.freq);
      bucket.unlink();
    }
  }

  @override
  bool remove(K key) {
    final node = _keyMap[key];
    if (node == null) return false;
    _removeNode(node);
    return true;
  }

  @override
  void clear() {
    _keyMap.clear();
    _bucketByFreq.clear();
    _bucketList.clear();
  }
}
