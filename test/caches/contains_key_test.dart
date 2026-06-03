import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  group('SimpleCache containsKey()', () {
    final factories = <String, SimpleCache<String, String?> Function()>{
      'SimpleFIFOCache': () => SimpleFIFOCache<String, String?>(2),
      'SimpleEphemeralFIFOCache': () =>
          SimpleEphemeralFIFOCache<String, String?>(2),
      'SimpleLRUCache': () => SimpleLRUCache<String, String?>(2),
      'SimpleMRUCache': () => SimpleMRUCache<String, String?>(2),
      'SimpleLFUCache': () => SimpleLFUCache<String, String?>(2),
    };

    for (final entry in factories.entries) {
      test('${entry.key} distinguishes stored null from missing key', () {
        final cache = entry.value();

        cache.set('present', null);

        expect(cache.get('present'), isNull);
        if (entry.key == 'SimpleEphemeralFIFOCache') {
          cache.set('present', null);
        }
        expect(cache.containsKey('present'), isTrue);
        expect(cache.containsKey('missing'), isFalse);

        cache.remove('present');

        expect(cache.containsKey('present'), isFalse);
      });
    }
  });

  group('ThreadSafeCache containsKey()', () {
    final factories = <String, ThreadSafeCache<String, String?> Function()>{
      'FIFOCache': () => FIFOCache<String, String?>(2),
      'EphemeralFIFOCache': () => EphemeralFIFOCache<String, String?>(2),
      'LRUCache': () => LRUCache<String, String?>(2),
      'MRUCache': () => MRUCache<String, String?>(2),
      'LFUCache': () => LFUCache<String, String?>(2),
    };

    for (final entry in factories.entries) {
      test('${entry.key} distinguishes stored null from missing key', () async {
        final cache = entry.value();

        await cache.set('present', null);

        expect(await cache.get('present'), isNull);
        if (entry.key == 'EphemeralFIFOCache') {
          await cache.set('present', null);
        }
        expect(await cache.containsKey('present'), isTrue);
        expect(await cache.containsKey('missing'), isFalse);

        await cache.remove('present');

        expect(await cache.containsKey('present'), isFalse);
      });
    }
  });

  group('Monitored caches containsKey()', () {
    final factories = <String, ThreadSafeCache<String, String?> Function()>{
      'MonitoredFIFOCache': () =>
          MonitoredFIFOCache<String, String?>(maxSize: 2),
      'MonitoredEphemeralFIFOCache': () =>
          MonitoredEphemeralFIFOCache<String, String?>(maxSize: 2),
      'MonitoredLRUCache': () => MonitoredLRUCache<String, String?>(maxSize: 2),
      'MonitoredMRUCache': () => MonitoredMRUCache<String, String?>(maxSize: 2),
      'MonitoredLFUCache': () => MonitoredLFUCache<String, String?>(maxSize: 2),
    };

    for (final entry in factories.entries) {
      test('${entry.key} distinguishes stored null from missing key', () async {
        final cache = entry.value();
        addTearDown(() {
          if (cache case Disposable disposable) {
            disposable.dispose();
          }
        });

        await cache.set('present', null);

        expect(await cache.get('present'), isNull);
        if (entry.key == 'MonitoredEphemeralFIFOCache') {
          await cache.set('present', null);
        }
        expect(await cache.containsKey('present'), isTrue);
        expect(await cache.containsKey('missing'), isFalse);

        await cache.remove('present');

        expect(await cache.containsKey('present'), isFalse);
      });
    }

    test(
      'MonitoredFIFOCache containsKey() does not record hits or misses',
      () async {
        final cache = MonitoredFIFOCache<String, String?>(maxSize: 2);
        addTearDown(cache.dispose);

        await cache.set('present', null);

        expect(await cache.containsKey('present'), isTrue);
        expect(await cache.containsKey('missing'), isFalse);
        expect(cache.metrics.hits, equals(0));
        expect(cache.metrics.misses, equals(0));
      },
    );
  });

  group('containsKey() policy side effects', () {
    test(
      'EphemeralFIFOCache containsKey() does not remove the entry',
      () async {
        final cache = EphemeralFIFOCache<String, String>(2);

        await cache.set('a', 'A');

        expect(await cache.containsKey('a'), isTrue);
        expect(await cache.get('a'), equals('A'));
        expect(await cache.containsKey('a'), isFalse);
      },
    );

    test('LRUCache containsKey() does not update recency', () async {
      final cache = LRUCache<String, String>(2);

      await cache.set('a', 'A');
      await cache.set('b', 'B');
      expect(await cache.containsKey('a'), isTrue);
      await cache.set('c', 'C');

      expect(await cache.containsKey('a'), isFalse);
      expect(await cache.containsKey('b'), isTrue);
      expect(await cache.containsKey('c'), isTrue);
    });

    test('MRUCache containsKey() does not update recency', () async {
      final cache = MRUCache<String, String>(2);

      await cache.set('a', 'A');
      await cache.set('b', 'B');
      expect(await cache.containsKey('a'), isTrue);
      await cache.set('c', 'C');

      expect(await cache.containsKey('a'), isTrue);
      expect(await cache.containsKey('b'), isFalse);
      expect(await cache.containsKey('c'), isTrue);
    });

    test('LFUCache containsKey() does not increment frequency', () async {
      final cache = LFUCache<String, String>(2);

      await cache.set('a', 'A');
      await cache.set('b', 'B');
      expect(await cache.containsKey('a'), isTrue);
      await cache.set('c', 'C');

      expect(await cache.containsKey('a'), isFalse);
      expect(await cache.containsKey('b'), isTrue);
      expect(await cache.containsKey('c'), isTrue);
    });
  });

  group('TTL containsKey()', () {
    DateTime now = DateTime(2024, 1, 1);
    DateTime clock() => now;

    setUp(() {
      now = DateTime(2024, 1, 1);
    });

    test('TTLCache returns false for expired keys', () async {
      final cache = TTLCache<String, String?>(
        ttl: const Duration(seconds: 10),
        clock: clock,
      );

      await cache.set('present', null);

      expect(await cache.containsKey('present'), isTrue);

      now = now.add(const Duration(seconds: 11));

      expect(await cache.containsKey('present'), isFalse);
      expect(await cache.getKeys(), isNot(contains('present')));
    });

    test('MonitoredTTLCache returns false for expired keys', () async {
      final cache = MonitoredTTLCache<String, String?>(
        ttl: const Duration(seconds: 10),
        clock: clock,
      );
      addTearDown(cache.dispose);

      await cache.set('present', null);

      expect(await cache.containsKey('present'), isTrue);

      now = now.add(const Duration(seconds: 11));

      expect(await cache.containsKey('present'), isFalse);
      expect(cache.metrics.hits, equals(0));
      expect(cache.metrics.misses, equals(0));
      expect(
        cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
        equals(1),
      );
    });
  });
}
