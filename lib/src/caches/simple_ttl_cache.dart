import 'dart:collection';

import '../interfaces/simple_ttl_cache.dart';

class _SimpleTTLEntry<V> {
  final V value;
  final DateTime expiry;

  _SimpleTTLEntry(this.value, this.expiry);
}

/// **Non-thread-safe TTL (Time-To-Live) Cache**
///
/// Entries are automatically treated as absent once their TTL has elapsed.
/// Expiry is checked lazily on [get] and [containsKey].
///
/// This class is designed for use in **single-threaded environments**
/// or scenarios where **concurrent access is not required**.
/// Since it is not thread-safe and does not perform synchronization,
/// **use `TTLCache` if async-safe access is needed.**
class SimpleTTLCache<K, V> extends SimpleTTLCacheInterface<K, V> {
  final Duration _globalTTL;
  final int? _maxSize;
  final DateTime Function() _clock;

  final LinkedHashMap<K, _SimpleTTLEntry<V>> _cache = LinkedHashMap();

  /// Creates a [SimpleTTLCache].
  ///
  /// - [ttl]: Default expiry duration for all entries stored via [set].
  /// - [maxSize]: Optional capacity limit; the oldest-inserted live entry is
  ///   evicted (FIFO) when the limit is exceeded.
  /// - [clock]: Injectable time source for testing; defaults to [DateTime.now].
  ///
  /// **Throws [ArgumentError] if [ttl] is zero or negative.**
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleTTLCache({
    required Duration ttl,
    int? maxSize,
    DateTime Function()? clock,
  }) : _globalTTL = ttl,
       _maxSize = maxSize,
       _clock = clock ?? DateTime.now {
    if (ttl <= Duration.zero) {
      throw ArgumentError('ttl must be greater than zero.');
    }
    if (maxSize != null && maxSize <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
  }

  bool _isExpired(_SimpleTTLEntry<V> entry) => !entry.expiry.isAfter(_clock());

  void _removeExpiredEntries() {
    final now = _clock();
    _cache.removeWhere((_, entry) => !entry.expiry.isAfter(now));
  }

  void _evictIfNeeded() {
    final maxSize = _maxSize;
    if (maxSize == null || _cache.length < maxSize) return;

    _removeExpiredEntries();
    while (_cache.length >= maxSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Returns all non-expired keys currently stored in the cache.
  ///
  /// **This method is not thread-safe.**
  @override
  Iterable<K> getKeys() {
    final now = _clock();
    return _cache.entries
        .where((e) => e.value.expiry.isAfter(now))
        .map((e) => e.key)
        .toList();
  }

  /// Retrieves the value associated with the specified key.
  ///
  /// - Returns `null` if the key does not exist or has expired.
  /// - Removes expired entries lazily.
  ///
  /// **This method is not thread-safe.**
  @override
  V? get(K key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (_isExpired(entry)) {
      _cache.remove(key);
      return null;
    }
    return entry.value;
  }

  /// Retrieves [key] without changing insertion order.
  ///
  /// Expired entries are removed lazily and treated as absent.
  ///
  /// **This method is not thread-safe.**
  @override
  V? peek(K key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (_isExpired(entry)) {
      _cache.remove(key);
      return null;
    }
    return entry.value;
  }

  /// Checks whether [key] exists and has not expired.
  ///
  /// Use this method to distinguish a present key with a `null` value from an
  /// absent or expired key.
  ///
  /// **This method is not thread-safe.**
  @override
  bool containsKey(K key) {
    final entry = _cache[key];
    if (entry == null) return false;
    if (_isExpired(entry)) {
      _cache.remove(key);
      return false;
    }
    return true;
  }

  /// Stores [key]/[value] in the cache.
  ///
  /// - [ttl]: Per-entry TTL override. When omitted, the global TTL is used.
  /// - If the key already exists, its value and expiry are updated and its
  ///   insertion order is refreshed (it becomes the newest entry for FIFO purposes).
  ///
  /// **This method is not thread-safe.**
  @override
  void set(K key, V value, {Duration? ttl}) {
    if (ttl != null && ttl <= Duration.zero) {
      throw ArgumentError('ttl must be greater than zero.');
    }

    _cache.remove(key);
    _evictIfNeeded();
    _cache[key] = _SimpleTTLEntry(value, _clock().add(ttl ?? _globalTTL));
  }

  /// Removes the entry with the given key from the cache.
  ///
  /// - If the key does not exist, this call is a no-op.
  ///
  /// **This method is not thread-safe.**
  @override
  void remove(K key) {
    _cache.remove(key);
  }

  /// Clears all data stored in the cache.
  ///
  /// **This method is not thread-safe.**
  @override
  void clear() {
    _cache.clear();
  }

  /// Returns a string representation of the current live cache state.
  ///
  /// Expired entries are excluded from the returned representation.
  ///
  /// **This method is not thread-safe.**
  @override
  String toString() {
    final liveEntries = <K, V>{};
    final now = _clock();
    for (final entry in _cache.entries) {
      if (entry.value.expiry.isAfter(now)) {
        liveEntries[entry.key] = entry.value.value;
      }
    }
    return liveEntries.toString();
  }
}
