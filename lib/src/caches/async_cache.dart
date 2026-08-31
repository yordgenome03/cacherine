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
  ///
  /// Reentrant so a caller already holding this lock (e.g. a `Monitored*`
  /// legacy facade's `getOrCompute`/`update`, mid-callback) can still call
  /// back into this instance's own overridable [set] to write the result —
  /// letting a downstream subclass's [set] override observe every write —
  /// without deadlocking on itself.
  final lock = Lock(reentrant: true);

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

  /// Stores every entry in [entries]. Writes through this cache's own
  /// (possibly overridden) [set] for each entry — rather than delegating the
  /// whole batch to [Cache.setAll] on [engine] — so a subclass's [set]
  /// override sees every write this makes, under a single lock acquisition
  /// for the whole batch (the lock is reentrant, so each nested [set] call
  /// re-entering it is safe).
  @override
  Future<void> setAll(Map<K, V> entries, {int? weight, Duration? ttl}) {
    engine.validateSetArgs(weight: weight, ttl: ttl);
    return lock.synchronized(() async {
      for (final entry in entries.entries) {
        await set(entry.key, entry.value, weight: weight, ttl: ttl);
      }
    });
  }

  /// The [ThreadSafeCache.getAll] default checks presence and reads each key
  /// with separate [containsKey]/[get] calls, each independently acquiring
  /// the lock; on a TTL-enabled instance each also reads the clock
  /// independently, so an entry can expire (or another call can mutate the
  /// cache) between the two. This override reads each key with a single
  /// [Cache.presentValue] snapshot, under a single lock acquisition for the
  /// whole batch (matching [setAll]) rather than one per key.
  @override
  Future<Map<K, V>> getAll(Iterable<K> keys) {
    return lock.synchronized(() {
      final values = <K, V>{};
      for (final key in keys) {
        final (found, value) = engine.presentValue(key);
        if (found && (value != null || null is V)) {
          values[key] = value as V;
        }
      }
      return values;
    });
  }

  /// The [ThreadSafeCache.removeWhere] default checks presence and peeks each
  /// key with separate [containsKey]/[peek] calls, each independently
  /// acquiring the lock; on a TTL-enabled instance each also reads the clock
  /// independently, so an entry can expire (or another call can mutate the
  /// cache) between the two. This override reads each key with a single
  /// [Cache.presentPeek] snapshot (peek-based, so testing an entry for
  /// removal never perturbs its eviction-policy state), under a single lock
  /// acquisition for the whole batch (matching [setAll]) rather than one per
  /// key — each matched [remove] call re-enters the same lock safely, since
  /// it's reentrant.
  @override
  Future<void> removeWhere(FutureOr<bool> Function(K key, V value) test) {
    return lock.synchronized(() async {
      for (final key in engine.getKeys().toList()) {
        final (found, value) = engine.presentPeek(key);
        if (!found) continue;
        if (await test(key, value as V)) {
          await remove(key);
        }
      }
    });
  }

  /// Checks [Cache.checkWeightRejection] and then writes [key]/[value]
  /// through this cache's own (possibly overridden) [set], returning [value]
  /// — or throws [StateError] if the write would be rejected because its
  /// weight exceeds [Cache.maxWeight]. Passes the already-computed weight
  /// back to [set] explicitly (rather than leaving it to recompute via a
  /// weigher call of its own) and delegates to [set] (rather than writing
  /// through [engine] directly), so a subclass's [set] override still runs
  /// for [getOrCompute]/[update], which — unlike [set] — must report what
  /// was actually cached rather than silently returning a value that never
  /// was. Exposed (not private) so [MonitoredCache]'s overrides of the same
  /// methods can reuse it.
  Future<V> storeOrThrow(K key, V value, {int? weight, Duration? ttl}) async {
    final result = engine.checkWeightRejection(key, value, weight);
    if (result.rejected) {
      throw StateError(
        'Cannot store value for cache key: $key — its weight exceeds '
        'maxWeight and can never fit.',
      );
    }
    await set(key, value, weight: result.weight ?? weight, ttl: ttl);
    return value;
  }

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
      return storeOrThrow(key, value, weight: weight, ttl: ttl);
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
        return storeOrThrow(key, value, weight: weight, ttl: ttl);
      }
      if (ifAbsent == null) {
        throw StateError('Cannot update missing cache key: $key');
      }
      final value = await ifAbsent();
      return storeOrThrow(key, value, weight: weight, ttl: ttl);
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
