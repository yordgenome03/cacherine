import 'dart:collection';

import 'cache_store.dart';

/// [CacheStore] backing [LRUStore]'s eviction policy: reading or writing an
/// entry moves it to the most-recently-used position; the least-recently-used
/// entry (the head of the map) is evicted first.
class LRUStore<K, V> implements CacheStore<K, V> {
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
    _cache[key] = value; // move to most-recently-used
    return value;
  }

  @override
  void put(K key, V value) {
    _cache.remove(key); // no-op if absent; drops old position if present
    _cache[key] = value; // (re)insert at the most-recently-used position
  }

  @override
  K? selectVictim({K? excluding}) {
    for (final k in _cache.keys) {
      if (k != excluding) return k;
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
