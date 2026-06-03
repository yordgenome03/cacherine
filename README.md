# cacherine

[![Pub Version](https://img.shields.io/pub/v/cacherine.svg)](https://pub.dev/packages/cacherine)
[![Dart CI](https://github.com/yordgenome03/cacherine/actions/workflows/ci.yaml/badge.svg)](https://github.com/yordgenome03/cacherine/actions/workflows/ci.yaml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/yordgenome03/cacherine/badge)](https://deps.dev/project/github/yordgenome03%2Fcacherine)
[![codecov](https://codecov.io/gh/yordgenome03/cacherine/branch/main/graph/badge.svg)](https://codecov.io/gh/yordgenome03/cacherine)
[![Dart Documentation](https://img.shields.io/badge/dartdoc-latest-blue)](https://pub.dev/documentation/cacherine/latest/)
[![GitHub issues](https://img.shields.io/github/issues/yordgenome03/cacherine)](https://github.com/yordgenome03/cacherine/issues)
[![GitHub pull requests](https://img.shields.io/github/issues-pr/yordgenome03/cacherine)](https://github.com/yordgenome03/cacherine/pulls)

<p align="center">
  <img src="https://github.com/user-attachments/assets/2a42a018-61cb-4ef7-a3d8-a0cafe923328" alt="cacherine logo" width="300"/>
</p>

`cacherine` is a simple and flexible memory cache library for Dart. It provides caching algorithms such as FIFO, LRU, MRU, LFU, and TTL-based expiry. Both synchronous and async-safe versions are available to handle different usage scenarios.

If you want to choose the best cache algorithm for your app, you can use **MonitoredCache** in your development environment. It helps you monitor performance metrics (such as hit/miss rates, latency, and eviction alerts) so you can make data-driven decisions and optimize the algorithm you use.

## Why cacherine?

Dart/Flutter does not have a built-in caching solution similar to `NSCache` in Swift.  
`cacherine` was created to provide a lightweight and flexible in-memory cache with common caching strategies like FIFO, LRU, MRU, and LFU.

Whether you need a simple synchronous cache or an async-compatible solution that serializes concurrent async calls within the same isolate, `cacherine` offers an easy-to-use API.

## Features

- **FIFO** (First In, First Out)
  — [Learn more](doc/fifo_cache.md)
- **EphemeralFIFO** (FIFO-based cache where keys are removed after being accessed)
  — [Learn more](doc/ephemeral_fifo_cache.md)
- **LRU** (Least Recently Used)
  — [Learn more](doc/lru_cache.md)
- **MRU** (Most Recently Used)
  — [Learn more](doc/mru_cache.md)
- **LFU** (Least Frequently Used)
  — [Learn more](doc/lfu_cache.md)
- **TTL** (Time-To-Live — entries auto-expire after a configurable duration; optional per-entry TTL override and background sweep)
  — [Learn more](doc/ttl_cache.md)
- **SimpleTTLCache** (synchronous TTL cache for single-threaded usage)
- **MonitoredCache** (Includes performance monitoring with hit/miss rates, latency, and eviction alerts)
  — [Learn more](doc/monitored_cache.md)
- **MonitoredTTLCache** (TTL-based expiry with the same monitoring metrics and alerts as other monitored cache variants)
- **CacheStatsDashboard** (Wraps a MonitoredCache's metrics to provide point-in-time snapshots and periodic streams; `formatDashboard()` renders a Unicode terminal panel)
- **`containsKey()` support** (distinguishes missing keys from stored `null` values without changing cache eviction state)
- **Simple versions (e.g., SimpleFIFOCache) for synchronous usage, and standard versions that serialize concurrent async calls within the same isolate**

## Installation

Check the latest version on [pub.dev](https://pub.dev/packages/cacherine) and add it to your `pubspec.yaml`:

```yaml
dependencies:
  cacherine: ^2.2.0
```

Then, run the following command in your terminal:

```bash
dart pub get
```

## Usage

### Basic Usage (Single-threaded)

```Dart
import 'package:cacherine/cacherine.dart';

void main() {
  final cache = SimpleFIFOCache<String, String>(maxSize: 5);
  cache.set('key1', 'value1');
  print(cache.get('key1')); // 'value1'
}
```

For synchronous single-threaded usage, use `SimpleTTLCache`:

```Dart
import 'package:cacherine/cacherine.dart';

void main() {
  final cache = SimpleTTLCache<String, String>(
    ttl: const Duration(minutes: 5),
    maxSize: 100,
  );

  cache.set('token', 'abc123');
  cache.set('rate', '42', ttl: const Duration(seconds: 30));

  print(cache.get('token')); // 'abc123' (if within TTL)
}
```

### Async Usage (Async support)

```Dart
import 'package:cacherine/cacherine.dart';

void main() async {
  final cache = FIFOCache<String, String>(maxSize: 5);
  await cache.set('key1', 'value1');
  print(await cache.get('key1')); // 'value1'
}
```

Use `getOrSet()` on synchronous caches or `getOrCompute()` on async caches when
you want to populate a missing key from a callback:

```dart
final syncCache = SimpleLRUCache<String, String>(100);
final syncValue = syncCache.getOrSet('profile:42', () => 'computed value');

final ttlCache = TTLCache<String, String>(ttl: const Duration(minutes: 5));
final asyncValue = await ttlCache.getOrCompute(
  'session:42',
  () async {
    return 'computed value';
  },
  ttl: const Duration(minutes: 1),
);
```

### TTL Usage

Entries expire automatically once their TTL elapses. Use `ttl:` on individual `set()` calls to override the global default for a single entry.

```Dart
import 'package:cacherine/cacherine.dart';

void main() async {
  final cache = TTLCache<String, String>(
    ttl: const Duration(minutes: 5),   // global default
    maxSize: 100,                       // optional capacity limit
    sweepInterval: const Duration(minutes: 1), // optional background sweep
  );

  await cache.set('token', 'abc123');                     // expires in 5 min
  await cache.set('rate', '42', ttl: Duration(seconds: 30)); // expires in 30 s

  print(await cache.get('token')); // 'abc123' (if within TTL)

  cache.dispose(); // cancel background sweep timer when done
}
```

### Monitoring Usage

If you want to monitor the performance of your cache and optimize the algorithm, use a monitored cache variant such as `MonitoredLRUCache` or `MonitoredTTLCache`.
[Learn more about MonitoredCache and performance monitoring.](doc/monitored_cache.md)

### Stats Dashboard Usage

`CacheStatsDashboard` wraps any `CacheMetrics` instance (exposed by MonitoredCache variants) to give you typed snapshots and a periodic stream. Use `formatDashboard()` to render a human-readable terminal panel.

```dart
import 'package:cacherine/cacherine.dart';

void main() async {
  final cache = MonitoredLRUCache<String, String>(maxSize: 100);

  // warm up the cache
  await cache.set('key', 'value');
  await cache.get('key');

  // one-shot snapshot over a 1-minute eviction window
  final dashboard = CacheStatsDashboard(cache.metrics);
  final snap = dashboard.snapshot(const Duration(minutes: 1));
  print(formatDashboard(snap));
  // ┌─── Cacherine Dashboard Snapshot ─────────────────────────────┐
  // │ Captured at: 2026-05-15 12:00:00                             │
  // ├───────────────────────────────────────────────────────────────┤
  // │ Traffic:     1 request                                        │
  // │ Hit Rate:    100.0%  [████████████████████]                   │
  // ├───────────────────────────────────────────────────────────────┤
  // │ Latency:     P50: 12µs / P95: 12µs / P99: 12µs               │
  // │ Evictions:   0 / min                                          │
  // └───────────────────────────────────────────────────────────────┘

  // periodic stream — emits every 5 seconds
  final sub = dashboard
      .stream(const Duration(minutes: 1), const Duration(seconds: 5))
      .listen((s) => print(formatDashboard(s)));

  await Future<void>.delayed(const Duration(seconds: 15));
  await sub.cancel();
  cache.dispose();
}
```

## API Contracts

The standard and monitored cache variants use `Future` APIs and an internal lock to serialize concurrent async calls on the same cache instance within the same isolate. They are not shared-memory synchronization primitives across Dart isolates.

`get()` returns `null` when a key is absent. Use `containsKey()` to distinguish a missing key from a stored `null` value, such as `Cache<String, String?>`. `containsKey()` does not update LRU/MRU/LFU access state, does not remove entries from EphemeralFIFO caches, and does not record monitored cache hit/miss metrics. For TTL caches, expired entries return `false`.

`getOrSet()` and `getOrCompute()` use `containsKey()` semantics before reading, so stored `null` values are treated as present. On monitored caches, `getOrCompute()` records one hit when the key already exists and one miss when the callback is used to populate the key.

`getKeys()` returns a snapshot. FIFO and TTL caches return insertion order for live entries. LRU and MRU caches return least-to-most recently used order. Ephemeral FIFO caches omit entries already consumed by `get()`. LFU cache key order is unspecified.

Use `SimpleTTLCacheInterface` or `ThreadSafeTTLCacheInterface` when code needs an abstraction that still exposes per-entry TTL overrides:

```dart
final ThreadSafeTTLCacheInterface<String, String> cache =
    TTLCache(ttl: const Duration(minutes: 5));

await cache.set('token', 'abc123', ttl: const Duration(seconds: 30));
```

`toString()` is synchronous. It returns a point-in-time representation of the cache contents and should be treated as diagnostic output, not as a synchronized cache operation.

Caches that implement `Disposable` own a background timer for sweeping expired
entries, checking alert thresholds, or both. Call `dispose()` when the cache is
no longer needed. It is idempotent; after disposal, cache read/write operations
continue to work, but background sweep and alert monitoring stop.

`CacheMetrics` keeps bounded in-memory samples: the most recent 1,000 latency
samples and 10,000 eviction timestamps. Hit, miss, and total request counters are
not capped. Latency percentiles and eviction rates are calculated from the
retained samples.

## API Reference

- [SimpleFIFOCache<K, V>](lib/src/caches/simple_fifo_cache.dart): Synchronous FIFO-based cache
- [SimpleEphemeralFIFOCache<K, V>](lib/src/caches/simple_ephemeral_fifo_cache.dart): Synchronous Ephemeral FIFO cache
- [SimpleLRUCache<K, V>](lib/src/caches/simple_lru_cache.dart): Synchronous LRU-based cache
- [SimpleMRUCache<K, V>](lib/src/caches/simple_mru_cache.dart): Synchronous MRU-based cache
- [SimpleLFUCache<K, V>](lib/src/caches/simple_lfu_cache.dart): Synchronous LFU-based cache
- [SimpleTTLCache<K, V>](lib/src/caches/simple_ttl_cache.dart): Synchronous TTL-based cache

- [FIFOCache<K, V>](lib/src/caches/fifo_cache.dart): FIFO-based cache
- [EphemeralFIFOCache<K, V>](lib/src/caches/ephemeral_fifo_cache.dart): FIFO-based cache where the key is removed after being accessed (One-Time Read Cache)
- [LRUCache<K, V>](lib/src/caches/lru_cache.dart): Cache that removes the least recently used items
- [MRUCache<K, V>](lib/src/caches/mru_cache.dart): Cache that removes the most recently used items
- [LFUCache<K, V>](lib/src/caches/lfu_cache.dart): Cache that removes the least frequently used items
- [TTLCache<K, V>](lib/src/caches/ttl_cache.dart): Cache with time-based expiry; global TTL with optional per-entry override, lazy eviction, optional background sweep, and optional capacity limit

- [MonitoredFIFOCache<K, V>](lib/src/caches/monitored_fifo_cache.dart): FIFO-based cache with monitoring
- [MonitoredEphemeralFIFOCache<K, V>](lib/src/caches/monitored_ephemeral_fifo_cache.dart): Ephemeral FIFO cache with monitoring
- [MonitoredLRUCache<K, V>](lib/src/caches/monitored_lru_cache.dart): LRU-based cache with monitoring
- [MonitoredMRUCache<K, V>](lib/src/caches/monitored_mru_cache.dart): MRU-based cache with monitoring
- [MonitoredLFUCache<K, V>](lib/src/caches/monitored_lfu_cache.dart): LFU-based cache with monitoring
- [MonitoredTTLCache<K, V>](lib/src/caches/monitored_ttl_cache.dart): TTL-based cache with monitoring

- [CacheStatsDashboard](lib/src/monitorings/cache_stats_dashboard.dart): Wraps `CacheMetrics` to provide `snapshot(Duration window)` and `stream(Duration window, Duration interval)`
- [CacheMetricsSnapshot](lib/src/monitorings/cache_metrics.dart): Typed point-in-time metrics snapshot returned by `CacheMetrics.snapshot(Duration window)`
- [DashboardSnapshot](lib/src/monitorings/cache_stats_dashboard.dart): Immutable point-in-time snapshot (hitRate, missRate, latency percentiles, evictionsPerMinute, totalRequests, capturedAt)
- [formatDashboard()](lib/src/monitorings/cache_stats_dashboard.dart): Renders a `DashboardSnapshot` as a Unicode box-drawing terminal panel

## Contributing

Contributions are welcome! If you find a bug, have a feature request, or want to improve the code, feel free to open an issue or submit a pull request.

### How to Contribute

1. Fork the repository and create a new branch.
2. Make your changes and write tests if necessary.
3. Ensure the code passes all checks (`dart analyze`, `dart test`).
4. Open a pull request and describe your changes.

For major changes, please open an issue first to discuss your proposal.

We appreciate your support in making `cacherine` better! 🚀

## Changelog

All notable changes to this project will be documented in the [CHANGELOG](CHANGELOG.md) file.

See the full changelog [here](CHANGELOG.md).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
