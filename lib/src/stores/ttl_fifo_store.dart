import 'dart:collection';

import 'cache_store.dart';

/// [CacheStore] backing the TTL-cache family's capacity eviction.
///
/// This is FIFO ordering with one deliberate difference from [FIFOStore]:
/// **updating an existing key refreshes its position to the newest slot**
/// (`put` always does remove-then-reinsert), matching the pre-v3
/// `TTLCache`/`SimpleTTLCache`/`MonitoredTTLCache` contract ("updating an
/// existing key refreshes its insertion order for FIFO capacity eviction
/// purposes"). Reading (`access`/`peek`) never reorders, same as [FIFOStore].
///
/// Plain `FIFOCache`/`SimpleFIFOCache` deliberately do *not* refresh position
/// on update, so this is a distinct policy from [FIFOStore] rather than a
/// duplicate — hence its own store rather than reuse.
class TTLFifoStore<K, V> implements CacheStore<K, V> {
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
  V? access(K key) => _cache[key]; // no reorder on read

  @override
  bool get removesOnAccess => false;

  @override
  void put(K key, V value) {
    _cache.remove(key); // refresh position on update, same as on insert
    _cache[key] = value;
  }

  @override
  (K,)? selectVictim({K? excluding}) {
    for (final k in _cache.keys) {
      if (k != excluding) return (k,);
    }
    return null;
  }

  @override
  (K, V)? evictOne({K? excluding}) {
    for (final k in _cache.keys) {
      if (k != excluding) {
        final value = _cache.remove(k) as V;
        return (k, value);
      }
    }
    return null;
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
