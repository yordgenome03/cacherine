import 'dart:collection';

import 'cache_store.dart';

final class _MRUNode<K, V> extends LinkedListEntry<_MRUNode<K, V>> {
  final K key;
  V value;
  _MRUNode(this.key, this.value);
}

/// [CacheStore] backing the MRU eviction policy: reading or writing an entry
/// moves it to the most-recently-used position, same as [LRUStore], but the
/// *most*-recently-used entry (the tail of the order) is evicted first.
///
/// Backed by a doubly-linked list (`_order`) rather than a `LinkedHashMap`, so
/// `selectVictim`/`evictOne` walking backwards past an excluded tail node
/// (e.g. the key currently being written, mid-eviction-loop, in
/// `Cache._write`) costs O(1) per hop via `previous` pointers, rather than
/// materializing every key into a `List` on each call.
class MRUStore<K, V> implements CacheStore<K, V> {
  final HashMap<K, _MRUNode<K, V>> _index = HashMap();
  final LinkedList<_MRUNode<K, V>> _order = LinkedList();

  @override
  int get length => _index.length;

  @override
  Iterable<K> get keys => _order.map((n) => n.key);

  @override
  bool containsKey(K key) => _index.containsKey(key);

  @override
  V? peek(K key) => _index[key]?.value;

  @override
  V? access(K key) {
    final node = _index[key];
    if (node == null) return null;
    node.unlink();
    _order.add(node); // move to the most-recently-used (tail) position
    return node.value;
  }

  @override
  bool get removesOnAccess => false;

  @override
  void put(K key, V value) {
    final existing = _index[key];
    if (existing != null) {
      existing.unlink();
      existing.value = value;
      _order.add(existing);
      return;
    }
    final node = _MRUNode(key, value);
    _index[key] = node;
    _order.add(node);
  }

  @override
  (K,)? selectVictim({K? excluding}) {
    final node = _findVictim(excluding);
    return node == null ? null : (node.key,);
  }

  @override
  (K, V)? evictOne({K? excluding}) {
    final node = _findVictim(excluding);
    if (node == null) return null;
    node.unlink();
    _index.remove(node.key);
    return (node.key, node.value);
  }

  _MRUNode<K, V>? _findVictim(K? excluding) {
    var node = _order.isEmpty ? null : _order.last;
    while (node != null) {
      if (node.key != excluding) return node;
      node = node.previous;
    }
    return null;
  }

  @override
  bool remove(K key) {
    final node = _index.remove(key);
    if (node == null) return false;
    node.unlink();
    return true;
  }

  @override
  void clear() {
    _index.clear();
    _order.clear();
  }
}
