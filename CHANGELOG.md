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

- Adjusted SDK constraint floor to `>=3.6.0` (minimum required by `lints ^5.1.1`)
- Raised `synchronized` dependency from `^3.3.1` to `^3.4.0` to match the exact resolved version in the lock file (`3.4.0+1`)
- Updated `lints` dev dependency from `^5.0.0` to `^5.1.1` to align with the revised SDK baseline
- Raised `test` dev dependency from `^1.25.8` to `^1.31.0` (resolved: 1.31.1)
- Removed `dart_code_metrics ^5.7.6` (incompatible with the `analyzer` versions required by modern test tooling)
- CI: Added matrix testing across Dart 3.6.0 and stable; updated GitHub Actions to v4; optimized permissions and tightened job timeouts
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
