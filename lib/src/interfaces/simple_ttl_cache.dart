import 'simple_cache.dart';

/// **Simple TTL Cache Interface**
///
/// Extends [SimpleCache] with per-entry TTL support.
///
/// Use this interface when code needs a synchronous cache abstraction that can
/// override expiry duration for individual entries.
abstract class SimpleTTLCacheInterface<K, V> extends SimpleCache<K, V> {
  /// **Stores the specified key-value pair with an optional per-entry TTL.**
  ///
  /// - If [ttl] is omitted, the cache implementation's default TTL is used.
  /// - If the key already exists, its value and expiry are updated.
  @override
  void set(K key, V value, {Duration? ttl});

  /// **Returns the existing value for [key], or stores and returns a new one.**
  ///
  /// When a new value is stored, [ttl] overrides the implementation's default
  /// TTL for that entry.
  @override
  V getOrSet(K key, V Function() valueFactory, {Duration? ttl}) {
    if (containsKey(key)) {
      return get(key) as V;
    }
    final value = valueFactory();
    set(key, value, ttl: ttl);
    return value;
  }
}
