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
