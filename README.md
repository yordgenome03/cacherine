# cacherine

[![Pub Version](https://img.shields.io/pub/v/cacherine.svg)](https://pub.dev/packages/cacherine)
[![Dart CI](https://github.com/yordgenome03/cacherine/actions/workflows/ci.yaml/badge.svg)](https://github.com/yordgenome03/cacherine/actions/workflows/ci.yaml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/yordgenome03/cacherine/badge)](https://deps.dev/project/github/yordgenome03%2Fcacherine)
[![codecov](https://codecov.io/gh/yordgenome03/cacherine/branch/main/graph/badge.svg)](https://codecov.io/gh/yordgenome03/cacherine)
[![Dart Documentation](https://img.shields.io/badge/dartdoc-latest-blue)](https://pub.dev/documentation/cacherine/latest/)
[![GitHub issues](https://img.shields.io/github/issues/yordgenome03/cacherine)](https://github.com/yordgenome03/cacherine/issues)
[![GitHub pull requests](https://img.shields.io/github/issues-pr/yordgenome03/cacherine)](https://github.com/yordgenome03/cacherine/pulls)

`cacherine` is a simple and flexible memory cache library for Dart. It provides basic caching algorithms such as FIFO, LRU, MRU, and LFU. Both single-threaded and async-enabled versions are available to handle different usage scenarios.

If you want to choose the best cache algorithm for your app, you can use **MonitoredCache** in your development environment. It helps you monitor performance metrics (such as hit/miss rates, latency, and eviction alerts) so you can make data-driven decisions and optimize the algorithm you use.

## Why cacherine?

Dart/Flutter does not have a built-in caching solution similar to `NSCache` in Swift.  
`cacherine` was created to provide a lightweight and flexible in-memory cache with common caching strategies like FIFO, LRU, MRU, and LFU.

Whether you need a simple single-threaded cache or an async-compatible solution for concurrent environments, `cacherine` offers an easy-to-use API.

## Features

- **FIFO** (First In, First Out)
- **EphemeralFIFO** (FIFO-based cache where keys are removed after being accessed)
- **LRU** (Least Recently Used)
- **MRU** (Most Recently Used)
- **LFU** (Least Frequently Used)
- **MonitoredCache** (Includes performance monitoring with hit/miss rates, latency, and eviction alerts) — [Learn more](doc/monitored_cache.md)
- **Simple versions (e.g., SimpleFIFOCache) for single-threaded usage, and standard versions for multi-threaded environments**

## Installation

Check the latest version on [pub.dev](https://pub.dev/packages/cacherine) and add it to your `pubspec.yaml`:

```yaml
dependencies:
  cacherine: ^latest_version
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

### Async Usage (Async support)

```Dart
import 'package:cacherine/cacherine.dart';

void main() async {
  final cache = FIFOCache<String, String>(maxSize: 5);
  await cache.set('key1', 'value1');
  print(await cache.get('key1')); // 'value1'
}
```

### Monitoring Usage

If you want to monitor the performance of your cache and optimize the algorithm, use MonitoredCache.
[Learn more about MonitoredCache and performance monitoring.](doc/monitored_cache.md)

## API Reference

- [FIFOCache<K, V>](lib/src/caches/fifo_cache.dart): FIFO-based cache
- [EphemeralFIFOCache<K, V>](lib/src/caches/ephemeral_fifo_cache.dart): FIFO-based cache where the key is removed after being accessed (One-Time Read Cache)
- [LRUCache<K, V>](lib/src/caches/lru_cache.dart): Cache that retains the least recently used items
- [MRUCache<K, V>](lib/src/caches/mru_cache.dart): Cache that retains the most recently used items
- [LFUCache<K, V>](lib/src/caches/lfu_cache.dart): Cache that removes the least frequently used items

- [MonitoredFIFOCache<K, V>](lib/src/caches/monitored_ephemeral_fifo_cache.dart): FIFO-based cache with monitoring
- [MonitoredEphemeralFIFOCache<K, V>](lib/src/caches/monitored_fifo_cache.dart): Ephemeral FIFO cache with monitoring
- [MonitoredLRUCache<K, V>](lib/src/caches/monitored_lru_cache.dart): LRU-based cache with monitoring
- [MonitoredMRUCache<K, V>](lib/src/caches/monitored_mru_cache.dart): MRU-based cache with monitoring
- [MonitoredLFUCache<K, V>](lib/src/caches/monitored_lfu_cache.dart): LFU-based cache with monitoring

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
