import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
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
  });
}
