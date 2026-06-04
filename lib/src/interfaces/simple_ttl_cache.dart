import 'simple_cache.dart';

/// **Simple TTL Cache Interface**
///
/// Extends [SimpleCache] with per-entry TTL support.
///
/// Use this interface when code needs a synchronous cache abstraction that can
/// override expiry duration for individual entries.
abstract class SimpleTTLCacheInterface<K, V> extends SimpleCache<K, V> {
  /// **Removes expired entries and returns how many entries were removed.**
  int purgeExpired();

  /// **Stores the specified key-value pair with an optional per-entry TTL.**
  ///
  /// - If [ttl] is omitted, the cache implementation's default TTL is used.
  /// - If the key already exists, its value and expiry are updated.
  @override
  void set(K key, V value, {Duration? ttl});

  /// **Stores all key-value pairs from [entries].**
  ///
  /// - If [ttl] is omitted, the cache implementation's default TTL is used.
  /// - If a key already exists, its value and expiry are updated.
  @override
  void setAll(Map<K, V> entries, {Duration? ttl}) {
    for (final entry in entries.entries) {
      set(entry.key, entry.value, ttl: ttl);
    }
  }

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

  /// **Stores and returns a value only when [key] is absent.**
  ///
  /// When a new value is stored, [ttl] overrides the implementation's default
  /// TTL for that entry.
  @override
  V putIfAbsent(K key, V Function() valueFactory, {Duration? ttl}) =>
      getOrSet(key, valueFactory, ttl: ttl);

  /// **Updates the value for [key] and returns the new value.**
  ///
  /// When a value is stored, [ttl] overrides the implementation's default TTL
  /// for that entry.
  @override
  V update(
    K key,
    V Function(V value) update, {
    V Function()? ifAbsent,
    Duration? ttl,
  }) {
    if (containsKey(key)) {
      final value = update(get(key) as V);
      set(key, value, ttl: ttl);
      return value;
    }
    if (ifAbsent == null) {
      throw StateError('Cannot update missing cache key: $key');
    }
    final value = ifAbsent();
    set(key, value, ttl: ttl);
    return value;
  }
}
