import 'dart:async';
import 'dart:collection';

import 'package:synchronized/synchronized.dart';

import '../interfaces/disposable.dart';
import '../interfaces/thread_safe_ttl_cache.dart';
import '../monitorings/cache_alert_manager.dart';
import '../monitorings/cache_monitoring.dart';

class _TTLEntry<V> {
  final V value;
  final DateTime expiry;

  _TTLEntry(this.value, this.expiry);
}

/// **Async-safe TTL (Time-To-Live) Cache with Monitoring**
///
/// Entries are treated as absent once their TTL has elapsed. Expired entries
/// are removed lazily on [get], proactively by an optional background sweep,
/// and during capacity checks when [maxSize] is configured.
///
/// This cache records hit/miss latency through [CacheMonitoring] and records
/// eviction events when entries are removed due to expiry, capacity limits, or
/// explicit [remove] calls.
class MonitoredTTLCache<K, V> extends ThreadSafeTTLCacheInterface<K, V>
    with CacheMonitoring<K, V>
    implements Disposable {
  final Duration _globalTTL;
  final int? _maxSize;
  final DateTime Function() _clock;

  final LinkedHashMap<K, _TTLEntry<V>> _cache = LinkedHashMap();
  final _lock = Lock();
  Timer? _sweepTimer;

  late final CacheAlertManager _cacheAlertManager;

  /// Creates a [MonitoredTTLCache].
  ///
  /// - [ttl]: Default expiry duration for entries stored via [set].
  /// - [maxSize]: Optional capacity limit; the oldest inserted live entry is
  ///   evicted when the limit is exceeded.
  /// - [sweepInterval]: Optional background interval for removing expired
  ///   entries.
  /// - [clock]: Injectable time source for testing; defaults to [DateTime.now].
  /// - [alertConfig]: Optional alert configuration for monitoring thresholds.
  MonitoredTTLCache({
    required Duration ttl,
    int? maxSize,
    Duration? sweepInterval,
    DateTime Function()? clock,
    CacheAlertConfig? alertConfig,
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

    _cacheAlertManager = CacheAlertManager(
      metrics,
      alertConfig ?? CacheAlertConfig(),
    );
    _cacheAlertManager.monitor();

    if (sweepInterval != null) {
      _sweepTimer = Timer.periodic(sweepInterval, (_) => _sweep());
    }
  }

  void _sweep() {
    unawaited(
      _lock.synchronized(() {
        final evicted = _removeExpired(_clock());
        _recordEvictions(evicted);
      }),
    );
  }

  int _removeExpired(DateTime now) {
    var evicted = 0;
    _cache.removeWhere((_, entry) {
      final expired = !entry.expiry.isAfter(now);
      if (expired) evicted++;
      return expired;
    });
    return evicted;
  }

  void _evictIfNeeded() {
    final maxSize = _maxSize;
    if (maxSize == null || _cache.length < maxSize) return;

    final expiredEvictions = _removeExpired(_clock());
    _recordEvictions(expiredEvictions);

    var capacityEvictions = 0;
    while (_cache.length >= maxSize) {
      _cache.remove(_cache.keys.first);
      capacityEvictions++;
    }
    _recordEvictions(capacityEvictions);
  }

  void _recordEvictions(int count) {
    for (var i = 0; i < count; i++) {
      metrics.recordEviction();
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
    var found = false;
    return await monitoredGet(key, () async {
      return await _lock.synchronized(() {
        final entry = _cache[key];
        if (entry == null) return null;
        if (!entry.expiry.isAfter(_clock())) {
          _cache.remove(key);
          metrics.recordEviction();
          return null;
        }
        found = true;
        return entry.value;
      });
    }, found: () => found);
  }

  @override
  Future<bool> containsKey(K key) async {
    return await _lock.synchronized(() {
      final entry = _cache[key];
      if (entry == null) return false;
      if (!entry.expiry.isAfter(_clock())) {
        _cache.remove(key);
        metrics.recordEviction();
        return false;
      }
      return true;
    });
  }

  /// Stores [key]/[value] in the cache.
  ///
  /// - [ttl]: Per-entry TTL override. When omitted, the global TTL is used.
  /// - Updating an existing key refreshes its insertion order for FIFO capacity
  ///   eviction purposes.
  @override
  Future<void> set(K key, V value, {Duration? ttl}) async {
    if (ttl != null && ttl <= Duration.zero) {
      throw ArgumentError('ttl must be greater than zero.');
    }
    await _lock.synchronized(() {
      _cache.remove(key);
      _evictIfNeeded();
      _cache[key] = _TTLEntry(value, _clock().add(ttl ?? _globalTTL));
    });
  }

  @override
  Future<V> getOrCompute(
    K key,
    FutureOr<V> Function() valueFactory, {
    Duration? ttl,
  }) async {
    if (ttl != null && ttl <= Duration.zero) {
      throw ArgumentError('ttl must be greater than zero.');
    }
    var found = false;
    return await monitoredGet(key, () async {
          return await _lock.synchronized(() async {
            final entry = _cache[key];
            final now = _clock();
            if (entry != null) {
              if (entry.expiry.isAfter(now)) {
                found = true;
                return entry.value;
              }
              _cache.remove(key);
              metrics.recordEviction();
            }
            final value = await valueFactory();
            _evictIfNeeded();
            _cache[key] = _TTLEntry(value, _clock().add(ttl ?? _globalTTL));
            return value;
          });
        }, found: () => found)
        as V;
  }

  @override
  Future<void> remove(K key) async {
    await _lock.synchronized(() {
      if (_cache.remove(key) != null) {
        metrics.recordEviction();
      }
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
    _cacheAlertManager.dispose();
  }

  @override
  String toString() {
    final now = _clock();
    final snapshot = Map.fromEntries(
      _cache.entries
          .where((e) => e.value.expiry.isAfter(now))
          .map((e) => MapEntry(e.key, e.value.value)),
    );
    return snapshot.toString();
  }
}
