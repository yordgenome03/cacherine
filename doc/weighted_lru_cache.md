# Weighted LRU Cache

## 1. Introduction

Weighted LRU Cache is a variant of the LRU (Least Recently Used) Cache that bounds the cache by a caller-supplied **weight** (e.g. an estimated byte size) per entry, instead of — or alongside — a simple entry *count*.

Entry-count-only bounding (`maxSize`) works well when entries are roughly uniform in size, but falls short when entries vary enormously in size: sizing `maxSize` for the common, light case leaves memory effectively unbounded whenever a handful of heavy entries land in the cache, while sizing it conservatively for the heavy case wastes cache slots — and hurts hit rate — for the common case.

## 2. Weighted LRU Cache Mechanism

### 2.1 Basic Concepts

A Weighted LRU Cache consists of the same elements as a regular LRU Cache, plus:

- **Weight**: A per-entry cost, computed by a `weigher` function `(key, value) -> int` supplied at construction time, or an explicit value passed to `set()`.
- **maxWeight**: The maximum total weight the cache may hold.
- **maxSize** _(optional)_: An additional cap on the number of entries, enforced alongside `maxWeight`.

### 2.2 Eviction Policy

1. **Evict the least recently used data**
   - When storing a new entry would push the cache's total weight above `maxWeight` (or, if `maxSize` is set, its entry count above `maxSize`), the least recently used entries are evicted — one at a time, oldest first — until the new entry fits.
2. **An entry that can never fit is not cached**
   - If a single entry's own weight exceeds `maxWeight`, it cannot fit under any circumstances, so it is discarded rather than cached.

## 3. Workflow

### 3.1 Data Retrieval (`get` operation)

Same as [LRU Cache](lru_cache.md): the accessed entry moves to the most-recently-used position; returns `null` if absent.

### 3.2 Data Insertion (`set` operation)

1. Compute the entry's weight via `weigher(key, value)`, unless an explicit `weight` argument is given.
2. If the entry's own weight exceeds `maxWeight`, discard it — it is not stored, and an existing entry under that key (if any) is left untouched.
3. While storing the entry would exceed `maxWeight` (or `maxSize`, if set), evict the least recently used entry.
4. Add the new key-value pair and record its weight.

Updating an existing key never evicts anything purely because of the update's entry count (only its weight delta can trigger eviction of *other* entries), and the entry being written is never evicted as its own "victim."

## 4. Example Usage

```dart
import 'package:cacherine/cacherine.dart';

void main() {
  // Bound the cache to 1 MB of estimated byte size.
  final cache = SimpleWeightedLRUCache<String, List<int>>(
    maxWeight: 1024 * 1024,
    weigher: (key, value) => value.length,
  );

  cache.set('small', List.filled(100, 0));
  cache.set('large', List.filled(900 * 1024, 0));

  print(cache.currentWeight); // Sum of the weights of the stored entries
}
```

An explicit `weight` can be supplied per call, overriding the `weigher` for that entry — useful when the cost depends on how the value was produced rather than its final shape:

```dart
cache.set('built-from-string', geometry, weight: estimatedBytesForThisBuild);
```

**Cached values should be treated as immutable once stored.** The weight recorded for an entry is computed once, at `set()` time, and never recomputed. If a stored value is later mutated in place such that its "true" weight would change, the cache's internal weight ledger silently drifts from reality. Re-`set()` the key (with an explicit `weight:` override if desired) to make the cache re-account for it.

## 5. Available Variants

- [`SimpleWeightedLRUCache<K, V>`](../lib/src/caches/simple_weighted_lru_cache.dart): Synchronous, single-threaded use.
- [`WeightedLRUCache<K, V>`](../lib/src/caches/weighted_lru_cache.dart): Async-safe, serializes concurrent calls within the same isolate.
- [`MonitoredWeightedLRUCache<K, V>`](../lib/src/caches/monitored_weighted_lru_cache.dart): Async-safe, with built-in performance monitoring — see [Monitored Cache](monitored_cache.md).

## 6. Composing Weight with Other Policies

Weight-based bounding is not LRU-specific — it is a general capability of the underlying [`Cache`/`AsyncCache`/`MonitoredCache` engine](../README.md#api-reference), which every named cache class in this package is a thin facade over. A cache combining weight with TTL expiry, or with a different eviction policy (FIFO, MRU, LFU), can be built directly without a dedicated named class:

```dart
final weightedTtlCache = AsyncCache<String, List<int>>(
  Cache(
    store: LRUStore<String, List<int>>(),
    weigher: (key, value) => value.length,
    maxWeight: 1024 * 1024,
    ttl: const Duration(minutes: 10),
  ),
);
```
