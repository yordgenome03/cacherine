import 'dart:collection';

import 'cache_store.dart';

/// [CacheStore] backing the Ephemeral-FIFO eviction policy: same ordering as
/// [FIFOStore], but reading an entry (`access`) removes it — retrieved data
/// cannot be read twice. [peek] still reads without removing.
class EphemeralFIFOStore<K, V> implements CacheStore<K, V> {
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
  V? access(K key) => _cache.remove(key); // removed on read

  @override
  void put(K key, V value) {
    _cache[key] = value;
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
