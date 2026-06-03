import 'dart:async';

import 'thread_safe_cache.dart';

/// **Async-safe TTL Cache Interface**
///
/// Extends [ThreadSafeCache] with per-entry TTL support.
///
/// Use this interface when code needs an async-safe cache abstraction that can
/// override expiry duration for individual entries.
abstract class ThreadSafeTTLCacheInterface<K, V> extends ThreadSafeCache<K, V> {
  /// **Stores the specified key-value pair with an optional per-entry TTL.**
  ///
  /// - If [ttl] is omitted, the cache implementation's default TTL is used.
  /// - If the key already exists, its value and expiry are updated.
  @override
  Future<void> set(K key, V value, {Duration? ttl});

  /// **Returns the existing value for [key], or computes, stores, and returns a new one.**
  ///
  /// When a new value is stored, [ttl] overrides the implementation's default
  /// TTL for that entry.
  @override
  Future<V> getOrCompute(
    K key,
    FutureOr<V> Function() valueFactory, {
    Duration? ttl,
  }) async {
    if (await containsKey(key)) {
      return await get(key) as V;
    }
    final value = await valueFactory();
    await set(key, value, ttl: ttl);
    return value;
  }
}
