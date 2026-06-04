import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

class _DefaultSimpleCache<K, V> extends SimpleCache<K, V> {
  final Map<K, V> _cache = {};

  @override
  Iterable<K> getKeys() => _cache.keys.toList();

  @override
  V? get(K key) => _cache[key];

  @override
  bool containsKey(K key) => _cache.containsKey(key);

  @override
  void set(K key, V value) {
    _cache[key] = value;
  }

  @override
  void remove(K key) {
    _cache.remove(key);
  }

  @override
  void clear() {
    _cache.clear();
  }
}

class _DefaultThreadSafeCache<K, V> extends ThreadSafeCache<K, V> {
  final Map<K, V> _cache = {};

  @override
  Future<Iterable<K>> getKeys() async => _cache.keys.toList();

  @override
  Future<V?> get(K key) async => _cache[key];

  @override
  Future<bool> containsKey(K key) async => _cache.containsKey(key);

  @override
  Future<void> set(K key, V value) async {
    _cache[key] = value;
  }

  @override
  Future<void> remove(K key) async {
    _cache.remove(key);
  }

  @override
  Future<void> clear() async {
    _cache.clear();
  }
}

class _DefaultThreadSafeTTLCache<K, V>
    extends ThreadSafeTTLCacheInterface<K, V> {
  final Map<K, V> _cache = {};
  final Map<K, Duration?> setTtls = {};

  @override
  Future<Iterable<K>> getKeys() async => _cache.keys.toList();

  @override
  Future<V?> get(K key) async => _cache[key];

  @override
  Future<bool> containsKey(K key) async => _cache.containsKey(key);

  @override
  Future<int> purgeExpired() async => 0;

  @override
  Future<void> set(K key, V value, {Duration? ttl}) async {
    _cache[key] = value;
    setTtls[key] = ttl;
  }

  @override
  Future<void> remove(K key) async {
    _cache.remove(key);
    setTtls.remove(key);
  }

  @override
  Future<void> clear() async {
    _cache.clear();
    setTtls.clear();
  }
}

void main() {
  group('default peek()', () {
    test('SimpleCache default delegates to get()', () {
      final cache = _DefaultSimpleCache<String, String?>();

      cache.set('present', null);
      cache.set('value', 'stored');

      expect(cache.peek('present'), isNull);
      expect(cache.containsKey('present'), isTrue);
      expect(cache.peek('value'), equals('stored'));
      expect(cache.peek('missing'), isNull);
    });

    test('ThreadSafeCache default delegates to get()', () async {
      final cache = _DefaultThreadSafeCache<String, String?>();

      await cache.set('present', null);
      await cache.set('value', 'stored');

      expect(await cache.peek('present'), isNull);
      expect(await cache.containsKey('present'), isTrue);
      expect(await cache.peek('value'), equals('stored'));
      expect(await cache.peek('missing'), isNull);
    });
  });

  group('SimpleCache.getOrSet()', () {
    final factories = <String, SimpleCache<String, String?> Function()>{
      'SimpleFIFOCache': () => SimpleFIFOCache<String, String?>(2),
      'SimpleEphemeralFIFOCache': () =>
          SimpleEphemeralFIFOCache<String, String?>(2),
      'SimpleLRUCache': () => SimpleLRUCache<String, String?>(2),
      'SimpleMRUCache': () => SimpleMRUCache<String, String?>(2),
      'SimpleLFUCache': () => SimpleLFUCache<String, String?>(2),
    };

    for (final entry in factories.entries) {
      test('${entry.key} returns existing stored null without computing', () {
        final cache = entry.value();
        var computes = 0;

        cache.set('key', null);

        expect(
          cache.getOrSet('key', () {
            computes++;
            return 'computed';
          }),
          isNull,
        );
        expect(computes, equals(0));
      });

      test('${entry.key} computes missing value once and stores it', () {
        final cache = entry.value();
        var computes = 0;

        final value = cache.getOrSet('key', () {
          computes++;
          return 'computed';
        });

        expect(value, equals('computed'));
        expect(computes, equals(1));
        expect(cache.containsKey('key'), isTrue);
      });
    }
  });

  group('ThreadSafeCache.getOrCompute()', () {
    final factories = <String, ThreadSafeCache<String, String?> Function()>{
      'FIFOCache': () => FIFOCache<String, String?>(2),
      'EphemeralFIFOCache': () => EphemeralFIFOCache<String, String?>(2),
      'LRUCache': () => LRUCache<String, String?>(2),
      'MRUCache': () => MRUCache<String, String?>(2),
      'LFUCache': () => LFUCache<String, String?>(2),
      'MonitoredFIFOCache': () =>
          MonitoredFIFOCache<String, String?>(maxSize: 2),
      'MonitoredEphemeralFIFOCache': () =>
          MonitoredEphemeralFIFOCache<String, String?>(maxSize: 2),
      'MonitoredLRUCache': () => MonitoredLRUCache<String, String?>(maxSize: 2),
      'MonitoredMRUCache': () => MonitoredMRUCache<String, String?>(maxSize: 2),
      'MonitoredLFUCache': () => MonitoredLFUCache<String, String?>(maxSize: 2),
    };

    for (final entry in factories.entries) {
      test(
        '${entry.key} returns existing stored null without computing',
        () async {
          final cache = entry.value();
          addTearDown(() {
            if (cache case Disposable disposable) disposable.dispose();
          });
          var computes = 0;

          await cache.set('key', null);

          expect(
            await cache.getOrCompute('key', () {
              computes++;
              return 'computed';
            }),
            isNull,
          );
          expect(computes, equals(0));
        },
      );

      test(
        '${entry.key} serializes concurrent computations per instance',
        () async {
          final cache = entry.value();
          addTearDown(() {
            if (cache case Disposable disposable) disposable.dispose();
          });
          var computes = 0;

          final results = await Future.wait([
            cache.getOrCompute('key', () async {
              computes++;
              await Future<void>.delayed(const Duration(milliseconds: 1));
              return 'computed';
            }),
            cache.getOrCompute('key', () {
              computes++;
              return 'other';
            }),
          ]);

          expect(results, equals(['computed', 'computed']));
          expect(computes, equals(1));
        },
      );
    }

    test(
      'monitored getOrCompute records miss for compute and hit for reuse',
      () async {
        final cache = MonitoredFIFOCache<String, String>(maxSize: 2);
        addTearDown(cache.dispose);

        expect(await cache.getOrCompute('key', () => 'computed'), 'computed');
        expect(await cache.getOrCompute('key', () => 'other'), 'computed');

        expect(cache.metrics.misses, equals(1));
        expect(cache.metrics.hits, equals(1));
      },
    );

    test(
      'default implementation returns existing value and computes missing value',
      () async {
        final cache = _DefaultThreadSafeCache<String, String?>();
        var computes = 0;

        await cache.set('present', null);

        expect(
          await cache.getOrCompute('present', () {
            computes++;
            return 'computed';
          }),
          isNull,
        );
        expect(
          await cache.getOrCompute('missing', () {
            computes++;
            return 'computed';
          }),
          equals('computed'),
        );

        expect(computes, equals(1));
        expect(await cache.get('missing'), equals('computed'));
      },
    );

    test(
      'capacity eviction branches run when getOrCompute inserts into full caches',
      () async {
        final caches = <String, ThreadSafeCache<String, String> Function()>{
          'FIFOCache': () => FIFOCache(2),
          'EphemeralFIFOCache': () => EphemeralFIFOCache(2),
          'LRUCache': () => LRUCache(2),
          'MRUCache': () => MRUCache(2),
          'LFUCache': () => LFUCache(2),
          'MonitoredFIFOCache': () => MonitoredFIFOCache(maxSize: 2),
          'MonitoredEphemeralFIFOCache': () =>
              MonitoredEphemeralFIFOCache(maxSize: 2),
          'MonitoredLRUCache': () => MonitoredLRUCache(maxSize: 2),
          'MonitoredMRUCache': () => MonitoredMRUCache(maxSize: 2),
          'MonitoredLFUCache': () => MonitoredLFUCache(maxSize: 2),
        };

        for (final entry in caches.entries) {
          final cache = entry.value();
          addTearDown(() {
            if (cache case Disposable disposable) disposable.dispose();
          });

          await cache.set('a', 'A');
          await cache.set('b', 'B');

          if (entry.key.contains('MRU') || entry.key.contains('LFU')) {
            expect(await cache.get('a'), equals('A'));
          }

          expect(await cache.getOrCompute('c', () => 'C'), equals('C'));
          expect(await cache.containsKey('c'), isTrue);
          expect((await cache.getKeys()).length, equals(2));

          final evictions = switch (cache) {
            MonitoredFIFOCache<String, String>() =>
              cache.metrics
                  .snapshot(const Duration(minutes: 1))
                  .evictionsPerMinute,
            MonitoredEphemeralFIFOCache<String, String>() =>
              cache.metrics
                  .snapshot(const Duration(minutes: 1))
                  .evictionsPerMinute,
            MonitoredLRUCache<String, String>() =>
              cache.metrics
                  .snapshot(const Duration(minutes: 1))
                  .evictionsPerMinute,
            MonitoredMRUCache<String, String>() =>
              cache.metrics
                  .snapshot(const Duration(minutes: 1))
                  .evictionsPerMinute,
            MonitoredLFUCache<String, String>() =>
              cache.metrics
                  .snapshot(const Duration(minutes: 1))
                  .evictionsPerMinute,
            _ => null,
          };

          if (evictions != null) {
            expect(evictions, equals(1), reason: entry.key);
          }
        }
      },
    );
  });

  group('TTL getOrSet/getOrCompute()', () {
    DateTime now = DateTime(2024);
    DateTime clock() => now;

    setUp(() {
      now = DateTime(2024);
    });

    test('SimpleTTLCacheInterface applies ttl override to computed value', () {
      final SimpleTTLCacheInterface<String, String> cache = SimpleTTLCache(
        ttl: const Duration(seconds: 30),
        clock: clock,
      );

      cache.getOrSet('short', () => 'value', ttl: const Duration(seconds: 5));
      now = now.add(const Duration(seconds: 10));

      expect(cache.get('short'), isNull);
    });

    test(
      'ThreadSafeTTLCacheInterface applies ttl override to computed value',
      () async {
        final ThreadSafeTTLCacheInterface<String, String> cache = TTLCache(
          ttl: const Duration(seconds: 30),
          clock: clock,
        );

        await cache.getOrCompute(
          'short',
          () => 'value',
          ttl: const Duration(seconds: 5),
        );
        now = now.add(const Duration(seconds: 10));

        expect(await cache.get('short'), isNull);
      },
    );

    test('SimpleTTLCacheInterface putIfAbsent forwards ttl override', () {
      final SimpleTTLCacheInterface<String, String> cache = SimpleTTLCache(
        ttl: const Duration(seconds: 30),
        clock: clock,
      );

      expect(
        cache.putIfAbsent(
          'short',
          () => 'value',
          ttl: const Duration(seconds: 5),
        ),
        equals('value'),
      );
      now = now.add(const Duration(seconds: 10));

      expect(cache.get('short'), isNull);
    });

    test('SimpleTTLCacheInterface update forwards ttl override', () {
      final SimpleTTLCacheInterface<String, String> cache = SimpleTTLCache(
        ttl: const Duration(seconds: 30),
        clock: clock,
      );

      cache.set('short', 'old');
      expect(
        cache.update(
          'short',
          (value) => '$value-new',
          ttl: const Duration(seconds: 5),
        ),
        equals('old-new'),
      );
      now = now.add(const Duration(seconds: 10));

      expect(cache.get('short'), isNull);
    });

    test(
      'ThreadSafeTTLCacheInterface putIfAbsent forwards ttl override',
      () async {
        final ThreadSafeTTLCacheInterface<String, String> cache = TTLCache(
          ttl: const Duration(seconds: 30),
          clock: clock,
        );

        expect(
          await cache.putIfAbsent(
            'short',
            () => 'value',
            ttl: const Duration(seconds: 5),
          ),
          equals('value'),
        );
        now = now.add(const Duration(seconds: 10));

        expect(await cache.get('short'), isNull);
      },
    );

    test('ThreadSafeTTLCacheInterface update forwards ttl override', () async {
      final ThreadSafeTTLCacheInterface<String, String> cache = TTLCache(
        ttl: const Duration(seconds: 30),
        clock: clock,
      );

      await cache.set('short', 'old');
      expect(
        await cache.update(
          'short',
          (value) async => '$value-new',
          ttl: const Duration(seconds: 5),
        ),
        equals('old-new'),
      );
      now = now.add(const Duration(seconds: 10));

      expect(await cache.get('short'), isNull);
    });

    test(
      'ThreadSafeTTLCacheInterface default implementation forwards ttl override',
      () async {
        final cache = _DefaultThreadSafeTTLCache<String, String?>();
        var computes = 0;

        await cache.set('present', null);

        expect(
          await cache.getOrCompute('present', () {
            computes++;
            return 'computed';
          }, ttl: const Duration(seconds: 5)),
          isNull,
        );
        expect(cache.setTtls['present'], isNull);

        expect(
          await cache.getOrCompute('missing', () {
            computes++;
            return 'computed';
          }, ttl: const Duration(seconds: 5)),
          equals('computed'),
        );

        expect(computes, equals(1));
        expect(cache.setTtls['missing'], equals(const Duration(seconds: 5)));
      },
    );

    test('MonitoredTTLCache records getOrCompute miss and hit', () async {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 30),
        clock: clock,
        alertConfig: CacheAlertConfig(notifyCallback: (_) {}),
      );
      addTearDown(cache.dispose);

      expect(await cache.getOrCompute('key', () => 'value'), equals('value'));
      expect(await cache.getOrCompute('key', () => 'other'), equals('value'));

      expect(cache.metrics.misses, equals(1));
      expect(cache.metrics.hits, equals(1));
    });

    test('TTLCache serializes concurrent computations per instance', () async {
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 30),
        clock: clock,
      );
      var computes = 0;

      final results = await Future.wait([
        cache.getOrCompute('key', () async {
          computes++;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return 'computed';
        }),
        cache.getOrCompute('key', () {
          computes++;
          return 'other';
        }),
      ]);

      expect(results, equals(['computed', 'computed']));
      expect(computes, equals(1));
    });

    test(
      'MonitoredTTLCache serializes concurrent computations per instance',
      () async {
        final cache = MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: 30),
          clock: clock,
          alertConfig: CacheAlertConfig(notifyCallback: (_) {}),
        );
        addTearDown(cache.dispose);
        var computes = 0;

        final results = await Future.wait([
          cache.getOrCompute('key', () async {
            computes++;
            await Future<void>.delayed(const Duration(milliseconds: 1));
            return 'computed';
          }),
          cache.getOrCompute('key', () {
            computes++;
            return 'other';
          }),
        ]);

        expect(results, equals(['computed', 'computed']));
        expect(computes, equals(1));
      },
    );

    test(
      'TTLCache getOrCompute validates ttl and replaces expired entries',
      () async {
        final cache = TTLCache<String, String>(
          ttl: const Duration(seconds: 30),
          clock: clock,
        );

        await expectLater(
          () =>
              cache.getOrCompute('invalid', () => 'value', ttl: Duration.zero),
          throwsArgumentError,
        );

        await cache.set('key', 'old', ttl: const Duration(seconds: 5));
        now = now.add(const Duration(seconds: 10));

        expect(await cache.getOrCompute('key', () => 'new'), equals('new'));
        expect(await cache.get('key'), equals('new'));
      },
    );

    test(
      'TTLCache getOrCompute removes expired entries before capacity eviction',
      () async {
        final cache = TTLCache<String, String>(
          ttl: const Duration(seconds: 5),
          maxSize: 2,
          clock: clock,
        );

        await cache.set('expired', 'old');
        await cache.set('live', 'live', ttl: const Duration(seconds: 30));
        now = now.add(const Duration(seconds: 10));

        expect(await cache.getOrCompute('new', () => 'new'), equals('new'));
        expect(await cache.getKeys(), equals(['live', 'new']));
      },
    );

    test(
      'MonitoredTTLCache getOrCompute validates ttl and records expired eviction',
      () async {
        final cache = MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: 30),
          clock: clock,
          alertConfig: CacheAlertConfig(notifyCallback: (_) {}),
        );
        addTearDown(cache.dispose);

        await expectLater(
          () =>
              cache.getOrCompute('invalid', () => 'value', ttl: Duration.zero),
          throwsArgumentError,
        );

        await cache.set('key', 'old', ttl: const Duration(seconds: 5));
        now = now.add(const Duration(seconds: 10));

        expect(await cache.getOrCompute('key', () => 'new'), equals('new'));
        expect(cache.metrics.misses, equals(1));
        expect(
          cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
          equals(1),
        );
      },
    );

    test(
      'MonitoredTTLCache getOrCompute records expired cleanup during capacity check',
      () async {
        final cache = MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: 5),
          maxSize: 2,
          clock: clock,
          alertConfig: CacheAlertConfig(notifyCallback: (_) {}),
        );
        addTearDown(cache.dispose);

        await cache.set('expired', 'old');
        await cache.set('live', 'live', ttl: const Duration(seconds: 30));
        now = now.add(const Duration(seconds: 10));

        expect(await cache.getOrCompute('new', () => 'new'), equals('new'));
        expect(await cache.getKeys(), equals(['live', 'new']));
        expect(
          cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
          equals(1),
        );
      },
    );
  });
}
