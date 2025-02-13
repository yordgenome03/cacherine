# cacherine

[![Pub Version](https://img.shields.io/pub/v/cacherine.svg)](https://pub.dev/packages/cacherine)

`cacherine` is a simple and flexible memory cache library for Dart. It provides basic caching algorithms such as FIFO, LRU, MRU, and LFU. Both single-threaded and async-enabled versions are available to handle different usage scenarios.

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

## API Reference

[FIFOCache<K, V>](lib/src/caches/fifo_cache.dart): FIFO-based cache
[EphemeralFIFOCache<K, V>](lib/src/caches/ephemeral_fifo_cache.dart): FIFO-based cache where the key is removed after being accessed (One-Time Read Cache)
[LRUCache<K, V>](lib/src/caches/lru_cache.dart): Cache that retains the least recently used items
[MRUCache<K, V>](lib/src/caches/mru_cache.dart): Cache that retains the most recently used items
[LFUCache<K, V>](lib/src/caches/lfu_cache.dart): Cache that removes the least frequently used items

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

This project is licensed under the BSD-3-Clause License - see the [LICENSE](LICENSE) file for details.
