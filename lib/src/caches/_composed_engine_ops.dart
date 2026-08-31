import 'dart:async';

import 'async_cache.dart';
import 'cache.dart';

/// **Shared control flow for a facade composing (not extending) an engine.**
///
/// Every legacy facade (`LRUCache`, `MRUCache`, `FIFOCache`, `LFUCache`,
/// `EphemeralFIFOCache`, `TTLCache`) composes an internal engine instead of
/// extending it, specifically to keep its
/// original, narrower public method signatures (no `weight`/`ttl` parameters
/// where the facade doesn't support them) — seeing each facade's own class
/// doc comment for why. That composition means `getOrCompute`/`update` can't
/// simply delegate to the engine's own `getOrCompute`/`update`: doing so
/// would write through the engine's `set()`, bypassing a subclass's override
/// of the *facade's* `set()`. Every one of these facades therefore
/// hand-rolled the identical "hold the lock, check presence atomically,
/// compute-or-update, write through this class's own `set`" sequence — these
/// two functions are that sequence, extracted once. Their `Monitored*`
/// counterparts additionally need `CacheMonitoring`'s `monitoredGet`, so the
/// same sequence is duplicated as `monitoredGetOrCompute`/`monitoredUpdate`
/// on the `CacheMonitoring` mixin instead of reusing these directly.
///
/// [engine] is the facade's composed [AsyncCache]. [writeThrough] must call
/// the facade's own (possibly overridden) `set` — not `engine.set` directly
/// — so a subclass's `set` override still sees every write this makes.
Future<V> composedGetOrCompute<K, V>(
  AsyncCache<K, V> engine,
  K key,
  FutureOr<V> Function() valueFactory,
  Future<void> Function(K key, V value) writeThrough,
) {
  return engine.lock.synchronized(() async {
    final (found, existing) = engine.engine.presentValue(key);
    if (found) return existing as V;
    final value = await valueFactory();
    await writeThrough(key, value);
    return value;
  });
}

/// The [composedGetOrCompute] counterpart for `update`. See its doc comment.
Future<V> composedUpdate<K, V>(
  AsyncCache<K, V> engine,
  K key,
  FutureOr<V> Function(V value) update, {
  required Future<void> Function(K key, V value) writeThrough,
  FutureOr<V> Function()? ifAbsent,
}) {
  return engine.lock.synchronized(() async {
    final (found, existing) = engine.engine.presentValue(key);
    if (found) {
      final value = await update(existing as V);
      await writeThrough(key, value);
      return value;
    }
    if (ifAbsent == null) {
      throw StateError('Cannot update missing cache key: $key');
    }
    final value = await ifAbsent();
    await writeThrough(key, value);
    return value;
  });
}

/// Sync counterpart of [composedGetOrCompute], for a facade composing a
/// synchronous [Cache] engine (used by `SimpleTTLCache`).
V syncComposedGetOrSet<K, V>(
  Cache<K, V> engine,
  K key,
  V Function() valueFactory,
  void Function(K key, V value) writeThrough,
) {
  final (found, existing) = engine.presentValue(key);
  if (found) return existing as V;
  final value = valueFactory();
  writeThrough(key, value);
  return value;
}

/// The [syncComposedGetOrSet] counterpart for `update`. See its doc comment.
V syncComposedUpdate<K, V>(
  Cache<K, V> engine,
  K key,
  V Function(V value) update, {
  required void Function(K key, V value) writeThrough,
  V Function()? ifAbsent,
}) {
  final (found, existing) = engine.presentValue(key);
  if (found) {
    final value = update(existing as V);
    writeThrough(key, value);
    return value;
  }
  if (ifAbsent == null) {
    throw StateError('Cannot update missing cache key: $key');
  }
  final value = ifAbsent();
  writeThrough(key, value);
  return value;
}
