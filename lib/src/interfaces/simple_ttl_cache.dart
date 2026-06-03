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
}
