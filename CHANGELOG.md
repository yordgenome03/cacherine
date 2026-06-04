## 2.4.0 - Conditional Mutation Helpers and Bulk Operations

### New Features

- Added `putIfAbsent()`, `update()`, and `removeWhere()` default APIs to simple, async-safe, and TTL cache interfaces.
- Added TTL-aware `putIfAbsent()` and `update()` overloads so new or updated entries can receive per-entry TTL overrides through TTL abstractions.
- Added `getAll()`, `setAll()`, and `removeAll()` bulk operation APIs to simple, async-safe, and TTL cache interfaces.
- Added TTL-aware `setAll()` overloads so batches can receive a shared per-entry TTL override through TTL abstractions.

### Documentation

- Documented conditional mutation helpers and clarified `getOrCompute()` same-instance serialization semantics.
- Documented bulk operation helpers and their cache policy side effects.

### Maintenance

- Added injectable clock support to `CacheMetrics` for deterministic eviction-window and dashboard tests.
- Expanded contract coverage for conditional mutation helpers, bulk operations, TTL helper forwarding, and TTL `getOrCompute()` concurrent computation behavior.

## 2.3.0 - Peek, Occupancy APIs, and TTL Purge Cleanup

### Documentation

- Expanded the runnable example and README cache-aside snippets to cover both `getOrSet()` and TTL-aware `getOrCompute()`.
- Documented the non-mutating `peek()` API across README and cache guides.
- Documented occupancy APIs (`size`, `isEmpty`, and `isNotEmpty`) across README and cache guides.
- Documented explicit TTL expiry cleanup with `purgeExpired()`.

### New Features

- Added `peek()` to simple, async-safe, monitored, and TTL cache variants so callers can read values without updating cache eviction state.
- Added `size`, `isEmpty`, and `isNotEmpty` to simple, async-safe, monitored, and TTL cache variants so callers can inspect cache occupancy without materializing keys directly.
- Added `purgeExpired()` to `SimpleTTLCache`, `TTLCache`, `MonitoredTTLCache`, and the TTL cache interfaces so callers can explicitly remove expired TTL entries and inspect how many were removed.

### Maintenance

- Updated dependency constraints for `synchronized` and `lints` to the newest resolvable versions for the current SDK range.
- Added regression coverage for `peek()` nullable-value behavior, policy side effects, monitored traffic metrics, and TTL expiry.
- Added regression coverage for cache occupancy APIs across standard, simple, monitored, ephemeral, and TTL caches.
- Added regression coverage for explicit TTL expiry cleanup and monitored eviction metrics.

## 2.2.0 - Simple TTL Cache, Cache-Aside Helpers, and Contract Coverage

### New Features

- **SimpleTTLCache**: Added a synchronous TTL cache variant with global and per-entry TTL, lazy expiry, `containsKey()`, optional `maxSize`, and FIFO capacity eviction.
- **TTL cache interfaces**: Added `SimpleTTLCacheInterface` and `ThreadSafeTTLCacheInterface` so abstract cache references can still expose per-entry TTL overrides.
- **Cache-aside population**: Added `getOrSet()` to simple caches and `getOrCompute()` to async-safe caches, including TTL per-entry override support through TTL-specific interfaces.

### Documentation

- Added runnable package examples covering `SimpleTTLCache`, `TTLCache`, and monitored cache dashboard snapshots.
- Documented synchronous TTL usage in the README and TTL guide.
- Documented TTL-specific interfaces for callers that need per-entry expiry through cache abstractions.
- Documented `getKeys()` ordering contracts, `Disposable` lifecycle behavior, and bounded `CacheMetrics` sample storage.

### Maintenance

- Added regression coverage for `SimpleTTLCache`, `TTLCache`, and `MonitoredTTLCache` through the new TTL-specific interfaces.
- Added regression coverage for cache-aside population, `dispose()` idempotency, post-dispose operations, and `getKeys()` ordering contracts.

## 2.1.0 - Monitored TTL Cache, containsKey API, and Monitoring Improvements

### New Features

- **MonitoredTTLCache**: Added a monitored TTL cache variant with hit/miss and latency metrics, eviction tracking for expiry/capacity/manual removals, alert support, and the same TTL configuration options as `TTLCache`.
- **containsKey() API**: Added `containsKey()` to simple, async-safe, monitored, and TTL cache variants so callers can distinguish stored `null` values from missing keys without mutating eviction state.
- **CacheMetricsSnapshot**: Added a typed `CacheMetrics.snapshot(Duration window)` API with hit/miss rates, latency percentiles, eviction rate, total requests, and capture time.
- **Monitored cache constructors**: Made `CacheAlertConfig` optional for monitored cache variants by providing a default no-op alert callback and default thresholds.

### Performance

- **MonitoredLFUCache**: Replaced O(n) eviction scans with frequency buckets for constant-time LFU eviction.
- **CacheMetrics**: Reused a single sorted latency snapshot when computing multiple percentiles for metrics snapshots and dashboards.
- **TTLCache**: Added a capacity benchmark to quantify expired-entry cleanup and FIFO capacity enforcement costs.

### Bug Fixes

- **Nullable monitored values**: Fixed monitored caches so stored `null` values are recorded as hits when the key exists.
- **TTLCache**: Validates `sweepInterval` and per-entry TTL values so zero or negative intervals fail fast.
- **CacheStatsDashboard**: Migrated dashboard snapshots to the typed metrics snapshot source for consistent captured timestamps and metric values.

### Documentation

- Clarified async-safe cache contracts and isolate boundaries for `ThreadSafeCache` implementations.
- Documented `containsKey()` semantics, nullable value behavior, and TTL expiry behavior.
- Documented MonitoredTTLCache usage in the TTL guide and README.
- Clarified monitored cache `toString()` output as diagnostic point-in-time state.

### Maintenance

- Split CI formatting suggestions into a separate least-privilege Reviewdog job.
- Reduced default workflow token permissions to read-only for CI jobs.
- Added regression coverage for nullable cached values, `containsKey()` policy side effects, monitored cache constructors, metrics snapshots, and MonitoredTTLCache expiry paths.

## 2.0.1 - LFU Performance Improvements, Bug Fixes, and Maintenance

### Performance

- **LFUCache**: Replaced O(n) eviction scan with an O(1) frequency-bucket structure. Eviction is now constant-time regardless of cache size.
- **LFUCache**: Eliminated O(n) `_minFreq` recomputation in `remove()`. The minimum-frequency pointer is now maintained incrementally.

### Bug Fixes

- **LFUCache**: `toString()` now eagerly snapshots `_keyMap` before formatting, preventing a data-race window between the map read and string construction in async contexts.

### Documentation

- **LFUCache**: Class-level note added clarifying that `toString()` is not covered by the lock-based thread-safety guarantee; result is a point-in-time snapshot.
- **LFUCache**: Documented unspecified iteration order for `getKeys()` and `toString()`.
- **LRUCache / MRUCache**: Documented LRU-recency-refresh behavior of `set()` on an existing key and the tiebreak semantics.

### Maintenance

- Adjusted SDK constraint floor to `>=3.8.0` (minimum required by `synchronized ^3.4.0`)
- Kept `synchronized` at `^3.3.1` (resolves to 3.4.0+1 in practice, which requires SDK >=3.8.0)
- Updated `lints` dev dependency from `^5.0.0` to `^5.1.1` to align with the revised SDK baseline
- Raised `test` dev dependency from `^1.25.8` to `^1.31.0` (resolved: 1.31.1)
- Removed `dart_code_metrics ^5.7.6` (incompatible with the `analyzer` versions required by modern test tooling)
- CI: Added matrix testing across Dart 3.8.0 and stable; updated GitHub Actions to v4; optimized permissions and tightened job timeouts; added Reviewdog-based format suggestions on PR
- Added `.fvm/` and `.fvmrc` to `.gitignore`
- No public API changes; no breaking changes

## 2.0.0 - CacheStatsDashboard, TTLCache, and Lifecycle Management

### New Features

- **CacheStatsDashboard**: New class that wraps `CacheMetrics` to produce typed `DashboardSnapshot` objects for terminal-ready metric display.
- **TTLCache**: Added a standalone cache implementation supporting Time-To-Live (TTL) for both global and per-entry expiry.
- **Disposable Interface**: Introduced a standard `Disposable` interface to handle resource cleanup (timers, controllers) across monitored and TTL caches.
- **DashboardSnapshot**: Immutable value type capturing `hitRate`, `missRate`, latency percentiles (`p50`, `p95`, `p99`), `evictionsPerMinute`, `totalRequests`, and `capturedAt`.
- **formatDashboard()**: New top-level function that renders a `DashboardSnapshot` as a Unicode box-drawing terminal panel with adaptive unit formatting (µs, ms, s).

### Breaking Changes

- **Interface Implementation**: All `Monitored*` caches and `TTLCache` now implement `Disposable`. Callers managing these instances should call `.dispose()` to prevent timer leaks.
- `CacheStatsDashboard.snapshot(Duration window)` now throws `ArgumentError` for zero or negative `window` values (previously undefined behaviour propagated from `CacheMetrics.getRecentStats`).
- `CacheStatsDashboard.stream(Duration window, Duration interval)` now throws `ArgumentError` for zero or negative `interval` values.

## 1.1.5 - Bug Fixes

- Fixed spurious eviction in FIFO `set()` when updating an existing key.
- Fixed unawaited `Future` in LFU/MRU eviction causing silent async errors.
- Fixed LFU `set()` incorrectly resetting usage count and spuriously evicting when updating an existing key.
- Fixed unbounded memory growth in `CacheMetrics` by capping stored latency samples.
- Fixed miss latency silently discarded in `CacheMetrics`/`CacheMonitoring`.
- Fixed incorrect cache descriptions for LRU and MRU.

## 1.1.4 - Add Project Logo to README

- Added project logo to README header for improved visual branding.

## 1.1.3 - Add Cache Algorithm Documentation

- Added documentation for Cache algorithms to the README.
- Updated Dart SDK constraints to require version 3.7.2 or higher in `pubspec.yaml`.

## 1.1.2 - Add Badges to README

- Added the following badges to the README:
  - Dart CI Badge
  - OpenSSF Scorecard Badge
  - Codecov Badge
  - Documentation Badge

## 1.1.1 - Maintenance and Dependency Updates

- Renamed `docs` directory to `doc` to comply with pub.dev package layout convention.
- Updated dependencies:
  - Resolved version constraints for `lints`, `synchronized`, and `js` packages.
- Refactored project structure for improved consistency across environments.
- No functionality changes; preparation for release and ongoing maintenance.

## 1.1.0 - Introduce MonitoredCache with Performance Metrics

### New Features

- **MonitoredCache**: Added a new cache variant with built-in performance monitoring.
  - Tracks **hit rate, miss rate, request latency, and eviction events**.
  - Provides percentile-based latency insights (e.g., **p95, p99**).
  - Includes an **alert system** that triggers warnings when performance thresholds are exceeded.
  - Supports **FIFO, LRU, MRU, LFU**, and **EphemeralFIFO** strategies.
- **Updated README**:
  - Introduced MonitoredCache as a tool for **debugging and optimizing cache selection**.
  - Added **API references** and **usage instructions** for monitored caches.
  - Provided a link to **detailed documentation** in `docs/monitored_cache.md`.

This update enables developers to **analyze cache performance in real-time** and choose the optimal caching strategy based on actual usage patterns.

## 1.0.2 - Improve package description

- Updated the `description` field in `pubspec.yaml` to meet `pub.dev` requirements.
- Expanded the package description to provide a clearer explanation of its functionality and target use cases.

## 1.0.1 - Fix description in pubspec.yaml

- Updated the `description` field in `pubspec.yaml` to provide a more specific and accurate explanation of the package's functionality.

## 1.0.0 - Initial release

- First release of `cacherine` package on pub.dev
- Provides basic memory cache implementations: FIFO, LRU, MRU, and LFU
- Includes two types of cache implementations:
  - Simple, single-threaded usage
  - Async-enabled versions for concurrent environments
- Designed to provide flexible, easy-to-use caching solutions for Dart applications

This is the first stable release. Feedback and contributions are welcome!
