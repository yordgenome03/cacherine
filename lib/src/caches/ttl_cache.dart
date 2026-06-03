import 'dart:async';
import 'dart:collection';

import 'package:synchronized/synchronized.dart';

import '../interfaces/disposable.dart';
import '../interfaces/thread_safe_cache.dart';

class _TTLEntry<V> {
  final V value;
  final DateTime expiry;
  _TTLEntry(this.value, this.expiry);
}

/// **Thread-safe TTL (Time-To-Live) Cache**
///
/// Entries are automatically treated as absent once their TTL has elapsed.
/// Expiry is checked lazily on [get]; an optional background sweep can remove
/// expired entries proactively to reclaim memory.
///
/// Implements [Disposable] — call [dispose] to cancel the sweep timer.
class TTLCache<K, V> extends ThreadSafeCache<K, V> implements Disposable {
  final Duration _globalTTL;
  final int? _maxSize;
  final DateTime Function() _clock;

  final LinkedHashMap<K, _TTLEntry<V>> _cache = LinkedHashMap();
  final _lock = Lock();
  Timer? _sweepTimer;

  /// Creates a [TTLCache].
  ///
  /// - [ttl]: Default expiry duration for all entries stored via [set].
  /// - [maxSize]: Optional capacity limit; the oldest-inserted live entry is
  ///   evicted (FIFO) when the limit is exceeded.
  /// - [sweepInterval]: When provided, a background timer fires at this interval
  ///   and removes all expired entries.
  /// - [clock]: Injectable time source for testing; defaults to [DateTime.now].
  ///
  /// When [maxSize] is configured and the cache is at capacity, [set] scans all
  /// entries to remove expired data before applying FIFO eviction.
  TTLCache({
    required Duration ttl,
    int? maxSize,
    Duration? sweepInterval,
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
    if (sweepInterval != null && sweepInterval <= Duration.zero) {
      throw ArgumentError('sweepInterval must be greater than zero.');
    }
    if (sweepInterval != null) {
      _sweepTimer = Timer.periodic(sweepInterval, (_) => _sweep());
    }
  }

  void _sweep() {
    // Called from timer callback — must be synchronous; Lock is reentrant-safe.
    _lock.synchronized(() {
      final now = _clock();
      _cache.removeWhere((_, entry) => !entry.expiry.isAfter(now));
    });
  }

  void _evictIfNeeded() {
    final maxSize = _maxSize;
    // Skip the scan entirely when below capacity — the common case.
    if (maxSize == null || _cache.length < maxSize) return;
    final now = _clock();
    // Full scan required: expired entries anywhere in the map must not count
    // toward capacity, so we cannot safely stop at the first live entry.
    _cache.removeWhere((_, entry) => !entry.expiry.isAfter(now));
    while (_cache.length >= maxSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  @override
  Future<Iterable<K>> getKeys() async {
    return await _lock.synchronized(() {
      final now = _clock();
      return _cache.entries
          .where((e) => e.value.expiry.isAfter(now))
          .map((e) => e.key)
          .toList();
    });
  }

  @override
  Future<V?> get(K key) async {
    return await _lock.synchronized(() {
      final entry = _cache[key];
      if (entry == null) return null;
      if (!entry.expiry.isAfter(_clock())) {
        _cache.remove(key);
        return null;
      }
      return entry.value;
    });
  }

  @override
  Future<bool> containsKey(K key) async {
    return await _lock.synchronized(() {
      final entry = _cache[key];
      if (entry == null) return false;
      if (!entry.expiry.isAfter(_clock())) {
        _cache.remove(key);
        return false;
      }
      return true;
    });
  }

  /// Stores [key]/[value] in the cache.
  ///
  /// - [ttl]: Per-entry TTL override. When omitted, the global TTL is used.
  /// - If the key already exists, its value and expiry are updated and its
  ///   insertion order is refreshed (it becomes the newest entry for FIFO purposes).
  @override
  Future<void> set(K key, V value, {Duration? ttl}) async {
    if (ttl != null && ttl <= Duration.zero) {
      throw ArgumentError('ttl must be greater than zero.');
    }
    await _lock.synchronized(() {
      _cache.remove(key); // Refresh insertion order on update.
      _evictIfNeeded();
      _cache[key] = _TTLEntry(value, _clock().add(ttl ?? _globalTTL));
    });
  }

  @override
  Future<void> remove(K key) async {
    await _lock.synchronized(() {
      _cache.remove(key);
    });
  }

  @override
  Future<void> clear() async {
    await _lock.synchronized(_cache.clear);
  }

  @override
  void dispose() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
  }
}
