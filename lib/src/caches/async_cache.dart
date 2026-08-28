import 'dart:async';

import 'package:synchronized/synchronized.dart';

import '../interfaces/thread_safe_cache.dart';
import 'cache.dart';

/// **Composable, async-safe cache engine.**
///
/// Wraps a [Cache] with a [Lock] from `package:synchronized`, serializing
/// concurrent async calls on the same instance within the same isolate —
/// the same relationship every `Simple*Cache`/`*Cache` pair in this package
/// has. See [Cache] for the composable capacity/weight/TTL configuration this
/// exposes.
///
/// **`getOrCompute`/`update` hold this instance's lock across the awaited
/// `valueFactory`/`update` callback**, so concurrent callers on *other* keys
/// are blocked too (the lock is per-instance, not per-key). This buys
/// atomicity (no duplicate computation for a racing missing key) at that
/// cost — avoid running slow work (e.g. a network request) directly inside
/// the callback; fetch outside the cache and call [set] instead if other
/// callers on this instance need to stay responsive.
class AsyncCache<K, V> extends ThreadSafeCache<K, V> {
  AsyncCache(this.engine);

  final Cache<K, V> engine;

  /// Shared with [MonitoredCache] (not private) so its compound operations
  /// (e.g. `remove` + metrics recording) serialize on the same lock as every
  /// other operation on this instance.
  final lock = Lock();

  /// The entry-count cap this instance was configured with, if any. See
  /// [Cache.maxSize].
  int? get maxSize => engine.maxSize;

  /// The sum of the weights of all entries currently stored, if weighing is
  /// enabled (always `0` otherwise).
  Future<int> get currentWeight =>
      lock.synchronized(() => engine.currentWeight);

  @override
  Future<Iterable<K>> getKeys() =>
      lock.synchronized(() => engine.getKeys().toList());

  @override
  Future<V?> get(K key) => lock.synchronized(() => engine.get(key));

  @override
  Future<V?> peek(K key) => lock.synchronized(() => engine.peek(key));

  @override
  Future<bool> containsKey(K key) =>
      lock.synchronized(() => engine.containsKey(key));

  /// Stores [key]/[value]. See [Cache.set] for the meaning of [weight] and
  /// [ttl], and the exceptions this can throw.
  @override
  Future<void> set(K key, V value, {int? weight, Duration? ttl}) =>
      lock.synchronized(() => engine.set(key, value, weight: weight, ttl: ttl));

  @override
  Future<void> setAll(Map<K, V> entries, {int? weight, Duration? ttl}) =>
      lock.synchronized(() => engine.setAll(entries, weight: weight, ttl: ttl));

  @override
  Future<V> getOrCompute(
    K key,
    FutureOr<V> Function() valueFactory, {
    int? weight,
    Duration? ttl,
  }) async {
    engine.validateSetArgs(weight: weight, ttl: ttl);
    return await lock.synchronized(() async {
      final (found, existing) = engine.presentValue(key);
      if (found) return existing as V;
      final value = await valueFactory();
      engine.set(key, value, weight: weight, ttl: ttl);
      return value;
    });
  }

  @override
  Future<V> putIfAbsent(
    K key,
    FutureOr<V> Function() valueFactory, {
    int? weight,
    Duration? ttl,
  }) => getOrCompute(key, valueFactory, weight: weight, ttl: ttl);

  @override
  Future<V> update(
    K key,
    FutureOr<V> Function(V value) update, {
    FutureOr<V> Function()? ifAbsent,
    int? weight,
    Duration? ttl,
  }) async {
    engine.validateSetArgs(weight: weight, ttl: ttl);
    return await lock.synchronized(() async {
      final (found, existing) = engine.presentValue(key);
      if (found) {
        final value = await update(existing as V);
        engine.set(key, value, weight: weight, ttl: ttl);
        return value;
      }
      if (ifAbsent == null) {
        throw StateError('Cannot update missing cache key: $key');
      }
      final value = await ifAbsent();
      engine.set(key, value, weight: weight, ttl: ttl);
      return value;
    });
  }

  @override
  Future<void> remove(K key) async {
    await lock.synchronized(() => engine.removeIfPresent(key));
  }

  @override
  Future<void> clear() => lock.synchronized(engine.clear);

  /// Removes all currently-expired entries and returns how many were
  /// removed. A no-op returning `0` if TTL is not configured.
  Future<int> purgeExpired() => lock.synchronized(engine.purgeExpired);

  /// **Note:** `toString()` is synchronous and does not acquire the lock.
  /// Treat the result as diagnostic output for a point-in-time view.
  @override
  String toString() => engine.toString();
}
