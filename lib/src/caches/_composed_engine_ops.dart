import 'dart:async';

import 'async_cache.dart';
import 'cache.dart';

/// **Shared control flow for a non-TTL legacy facade composing (not
/// extending) an [AsyncCache] engine.**
///
/// `LRUCache`, `MRUCache`, `FIFOCache`, `LFUCache`, and `EphemeralFIFOCache`
/// compose an internal engine instead of extending it, specifically to keep
/// their original, narrower public method signatures (no `weight`/`ttl`
/// parameters) — see each facade's own class doc comment for why. That
/// composition means `getOrCompute`/`update` can't simply delegate to the
/// engine's own `getOrCompute`/`update`: doing so would write through the
/// engine's `set()`, bypassing a subclass's override of the *facade's*
/// `set()`. Every one of these facades therefore hand-rolled the identical
/// "hold the lock, check presence, compute-or-update, write through this
/// class's own `set`" sequence — these two functions are that sequence,
/// extracted once.
///
/// The presence check and read are dispatched through [containsKey]/[get] —
/// the facade's own (possibly overridden) methods — rather than reading the
/// composed engine directly. None of these five facades configure a `ttl`
/// or `weigher`, so there is no check-then-fetch race for `containsKey`+
/// `get` to reintroduce (the whole sequence already runs under one
/// continuously-held, reentrant lock acquisition below); dispatching through
/// them instead lets a downstream subclass's `get`/`containsKey` override
/// (e.g. added logging, validation, or a different read side effect) see
/// every read `getOrCompute`/`update` performs, matching the un-overridden
/// `ThreadSafeCache.getOrCompute`/`update` defaults these facades stood in
/// for, and reusing `get`'s own read-side-effect semantics (LRU/MRU
/// reordering, LFU frequency promotion, or — for `EphemeralFIFOCache` —
/// consuming the entry) exactly as a plain `get` call would.
///
/// **`TTLCache` does NOT use these** — its `getOrCompute`/`update` must read
/// via [Cache.presentValue] (a single clock snapshot) instead, to avoid the
/// TTL check-then-fetch race a separate `containsKey`+`get` call pair would
/// reintroduce; see its own `getOrCompute`/`update` for that atomic-snapshot
/// version of this same control flow.
///
/// [engine] is the facade's composed [AsyncCache], used only to acquire its
/// [AsyncCache.lock] — [containsKey]/[get]/[writeThrough] must all be the
/// facade's own (possibly overridden) methods, not `engine`'s, so a
/// subclass override of any of them still sees every call this makes.
Future<V> composedGetOrCompute<K, V>(
  AsyncCache<K, V> engine,
  K key,
  Future<bool> Function(K key) containsKey,
  Future<V?> Function(K key) get,
  FutureOr<V> Function() valueFactory,
  Future<void> Function(K key, V value) writeThrough,
) {
  return engine.lock.synchronized(() async {
    if (await containsKey(key)) return (await get(key)) as V;
    final value = await valueFactory();
    await writeThrough(key, value);
    return value;
  });
}

/// The [composedGetOrCompute] counterpart for `update`. See its doc comment.
Future<V> composedUpdate<K, V>(
  AsyncCache<K, V> engine,
  K key,
  Future<bool> Function(K key) containsKey,
  Future<V?> Function(K key) get,
  FutureOr<V> Function(V value) update, {
  required Future<void> Function(K key, V value) writeThrough,
  FutureOr<V> Function()? ifAbsent,
}) {
  return engine.lock.synchronized(() async {
    if (await containsKey(key)) {
      final value = await update((await get(key)) as V);
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

/// Sync counterpart of [composedGetOrCompute], for `SimpleTTLCache`, which
/// composes a synchronous [Cache] engine. Unlike the async facades above,
/// `SimpleTTLCache` DOES need [Cache.presentValue]'s atomic single-clock
/// snapshot (it has a `ttl`), so — unlike [composedGetOrCompute] — this
/// reads the engine directly rather than dispatching through
/// `containsKey`/`get`; see `SimpleTTLCache`'s own doc comments.
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
