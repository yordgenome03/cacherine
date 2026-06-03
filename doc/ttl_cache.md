# TTL Cache

## 1. Introduction

TTL (Time-To-Live) Cache is a cache that automatically treats entries as absent once a configured duration has elapsed since they were stored. Unlike capacity-based eviction policies (LRU, FIFO, etc.), TTL Cache invalidates data based on age, making it suitable for scenarios where data has a bounded validity window — such as auth tokens, API responses, or computed values with known freshness requirements.

## 2. TTLCache Mechanism

### 2.1 Basic Concepts

A `TTLCache` stores each entry together with an **expiry timestamp** computed at insertion time:

- **Key**: Uniquely identifies the cached data.
- **Value**: The actual data.
- **Expiry**: `DateTime` = insertion time + TTL. Once the clock passes this point, the entry is treated as absent.

### 2.2 Expiry Policy

| Mechanism | When it runs | What it does |
|-----------|--------------|--------------|
| **Lazy eviction** | On every `get()` call | Returns `null` and removes the entry if its TTL has elapsed |
| **Background sweep** | Periodically (when `sweepInterval` is set) | Removes all expired entries from memory without waiting for `get()` |

Lazy eviction is the correctness guarantee — the cache is always accurate. The background sweep is purely a memory optimisation for use cases where keys may expire without ever being accessed again.

`SimpleTTLCache` provides the same expiry, per-entry TTL, `containsKey()`, and optional `maxSize` behavior for synchronous single-threaded usage. It does not start a background sweep timer and does not implement `Disposable`; expired entries are removed lazily or ignored by read APIs.

Use `SimpleTTLCacheInterface` or `ThreadSafeTTLCacheInterface` when you need a cache abstraction that preserves access to the per-entry `ttl:` override.

### 2.3 Global TTL vs Per-Entry TTL Override

```
TTLCache(ttl: Duration(minutes: 10))   // global default for all set() calls
cache.set('fast', value, ttl: Duration(seconds: 30))  // override for one entry
```

When `ttl:` is omitted in `set()`, the global TTL applies. When provided, it overrides the global value for that entry only.

### 2.4 Optional Capacity Limit (FIFO eviction)

When `maxSize` is specified, `set()` enforces a cap on the number of **live** (non-expired) entries. If adding a new key would exceed the cap, the oldest-inserted live entry is evicted first (FIFO order from `LinkedHashMap`). Expired entries are excluded from this count — they are swept before the cap is evaluated.

## 3. Workflow

### 3.1 Data Retrieval (`get` operation)

1. If the key does not exist → return `null`.
2. If the key exists but its TTL has elapsed → remove the entry, return `null` (lazy eviction).
3. If the key exists and is still within its TTL → return the value.

### 3.2 Existence Check (`containsKey` operation)

1. If the key does not exist → return `false`.
2. If the key exists but its TTL has elapsed → remove the entry, return `false`.
3. If the key exists and is still within its TTL → return `true`.

Use `containsKey()` to distinguish a missing key from a stored `null` value.

### 3.3 Data Insertion (`set` operation)

1. If the key already exists, remove it first (so the refreshed entry gets a new insertion timestamp, affecting FIFO order).
2. If `maxSize` is set and the number of live entries would reach `maxSize`:
   a. Remove all expired entries (they don't count toward capacity).
   b. If still at or over capacity, remove the oldest-inserted live entry (FIFO).
3. Store the entry with expiry = `clock() + ttl`.

### 3.4 Example: TTLCache Operations and State Changes

Setup: `TTLCache(ttl: Duration(seconds: 10), maxSize: 3)`  
(clock starts at t=0)

1. **t=0 — set A, set B, set C**

   | Key | Expiry |
   |-----|--------|
   | A   | t=10   |
   | B   | t=10   |
   | C   | t=10   |

2. **t=5 — get A** → returns value (TTL has not elapsed)

3. **t=11 — get A** → returns `null`, entry removed (TTL elapsed)

   | Key | Expiry |
   |-----|--------|
   | B   | t=10 (expired, not yet swept) |
   | C   | t=10 (expired, not yet swept) |

4. **t=11 — set D** (maxSize=3, but B and C are expired — live count is 0)

   Expired B and C are cleared first; D is inserted without evicting any live entry.

   | Key | Expiry |
   |-----|--------|
   | D   | t=21   |

## 4. Synchronous Usage

Use `SimpleTTLCache` when you need a synchronous cache and do not need async call serialization:

```dart
final cache = SimpleTTLCache<String, String>(
  ttl: const Duration(minutes: 5),
  maxSize: 100,
);

cache.set('token', 'abc123');
cache.set('rate', '42', ttl: const Duration(seconds: 30));

print(cache.get('token'));
```

## 5. Lifecycle and Disposal

`TTLCache` implements `Disposable`. When a `sweepInterval` is configured, a background `Timer.periodic` is started in the constructor. Call `dispose()` to cancel it and stop further sweeps:

```dart
final cache = TTLCache<String, String>(
  ttl: const Duration(minutes: 5),
  sweepInterval: const Duration(minutes: 1),
);

// ... use the cache ...

cache.dispose(); // cancel sweep timer
```

`dispose()` is idempotent — calling it multiple times is safe. After `dispose()`, `get()` and `set()` continue to work; only the background sweep stops.

## 6. Monitoring

Use `MonitoredTTLCache` when you need TTL expiry together with `CacheMetrics`,
`CacheStatsDashboard`, or alert thresholds. It supports the same TTL options as
`TTLCache` (`ttl`, per-entry `ttl:`, `maxSize`, `sweepInterval`, and `clock`) and
records:

- Hits and misses for `get()` calls.
- Latency for each `get()` call.
- Evictions when entries are removed by expiry, capacity limits, or explicit `remove()` calls.

```dart
final cache = MonitoredTTLCache<String, String>(
  ttl: Duration(minutes: 5),
  maxSize: 100,
);

await cache.set('token', 'abc123');
await cache.get('token');

final snapshot = cache.metrics.snapshot(Duration(minutes: 1));
print(snapshot.hitRate);

cache.dispose();
```

## 7. API Reference

| Method | Description |
|--------|-------------|
| `set(K key, V value, {Duration? ttl})` | Store an entry. `ttl:` overrides the global TTL for this entry. |
| `get(K key)` | Retrieve a value, or `null` if missing or expired (lazy eviction). |
| `containsKey(K key)` | Return whether a non-expired entry exists for the key. Expired entries are removed and return `false`. |
| `getKeys()` | Return only keys whose TTL has not elapsed. |
| `remove(K key)` | Remove a single entry; no-op if absent. |
| `clear()` | Remove all entries. |
| `dispose()` | Cancel the background sweep timer. Idempotent. Supported by `TTLCache` and `MonitoredTTLCache`; not supported by `SimpleTTLCache`. |

## 8. Constructor Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ttl` | `Duration` | Yes | Global TTL applied to all `set()` calls. |
| `maxSize` | `int?` | No | Maximum number of live entries. No limit if omitted. |
| `sweepInterval` | `Duration?` | No | Interval for background expired-entry removal. No sweep if omitted. Supported by `TTLCache` and `MonitoredTTLCache`; not supported by `SimpleTTLCache`. |
| `clock` | `DateTime Function()?` | No | Time source. Defaults to `DateTime.now`. Inject a fake clock in tests. |

## 9. Suitable Use Cases

TTL Cache is well-suited for data with a natural validity window:

- **Auth tokens / session data**: Expire credentials automatically rather than manually invalidating them.
- **External API responses**: Cache results for a bounded duration to reduce upstream load while ensuring freshness.
- **Computed values with bounded validity**: Cache expensive computations that are known to be stale after a fixed interval (e.g., exchange rates, configuration snapshots).
- **Rate-limiting state**: Track per-key counters that should reset after a time window.

## 10. Choosing Between TTLCache and Capacity-Based Caches

| | Capacity-based (FIFO/LRU/etc.) | TTLCache |
|-|-------------------------------|----------|
| **Eviction trigger** | Cache size exceeds limit | Time elapsed |
| **Stale data risk** | Possible — entries live indefinitely | Eliminated — entries auto-expire |
| **Memory bound** | Hard (maxSize) | Soft (expired entries occupy memory until swept or accessed) |
| **Use when** | Data freshness is not a concern | Data has a bounded validity window |

You can combine both: set `maxSize` on `TTLCache` to get a hard memory cap alongside time-based expiry.
