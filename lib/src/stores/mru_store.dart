import 'dart:collection';

import 'cache_store.dart';

/// [CacheStore] backing the MRU eviction policy: reading or writing an entry
/// moves it to the most-recently-used position, same as [LRUStore], but the
/// *most*-recently-used entry (the tail of the map) is evicted first.
class MRUStore<K, V> implements CacheStore<K, V> {
  final LinkedHashMap<K, V> _cache = LinkedHashMap();

  @override
  int get length => _cache.length;

  @override
  Iterable<K> get keys => _cache.keys;

  @override
  bool containsKey(K key) => _cache.containsKey(key);

  @override
  V? peek(K key) => _cache[key];

  @override
  V? access(K key) {
    if (!_cache.containsKey(key)) return null;
    final value = _cache.remove(key) as V;
    _cache[key] = value; // mark as "most recently used"
    return value;
  }

  @override
  void put(K key, V value) {
    _cache.remove(key);
    _cache[key] = value;
  }

  @override
  K? selectVictim({K? excluding}) {
    if (_cache.isEmpty) return null;
    final last = _cache.keys.last;
    if (last != excluding) return last;
    // The MRU victim itself is excluded — walk backwards for the next one.
    final list = _cache.keys.toList(growable: false);
    for (var i = list.length - 2; i >= 0; i--) {
      if (list[i] != excluding) return list[i];
    }
    return null;
  }

  @override
  (K, V)? evictOne({K? excluding}) {
    final victim = selectVictim(excluding: excluding);
    if (victim == null) return null;
    final value = _cache.remove(victim) as V;
    return (victim, value);
  }

  @override
  bool remove(K key) {
    if (!_cache.containsKey(key)) return false;
    _cache.remove(key);
    return true;
  }

  @override
  void clear() => _cache.clear();
}
