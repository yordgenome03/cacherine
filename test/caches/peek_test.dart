import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  group('SimpleCache peek()', () {
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

        expect(cache.peek('present'), isNull);
        expect(cache.containsKey('present'), isTrue);
        expect(cache.peek('missing'), isNull);
        expect(cache.containsKey('missing'), isFalse);
      });
    }
  });

  group('ThreadSafeCache peek()', () {
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

        expect(await cache.peek('present'), isNull);
        expect(await cache.containsKey('present'), isTrue);
        expect(await cache.peek('missing'), isNull);
        expect(await cache.containsKey('missing'), isFalse);
      });
    }
  });

  group('peek() policy side effects', () {
    test('EphemeralFIFOCache peek() does not remove the entry', () async {
      final cache = EphemeralFIFOCache<String, String>(2);

      await cache.set('a', 'A');

      expect(await cache.peek('a'), equals('A'));
      expect(await cache.get('a'), equals('A'));
      expect(await cache.containsKey('a'), isFalse);
    });

    test('LRUCache peek() does not update recency', () async {
      final cache = LRUCache<String, String>(2);

      await cache.set('a', 'A');
      await cache.set('b', 'B');
      expect(await cache.peek('a'), equals('A'));
      await cache.set('c', 'C');

      expect(await cache.containsKey('a'), isFalse);
      expect(await cache.containsKey('b'), isTrue);
      expect(await cache.containsKey('c'), isTrue);
    });

    test('MRUCache peek() does not update recency', () async {
      final cache = MRUCache<String, String>(2);

      await cache.set('a', 'A');
      await cache.set('b', 'B');
      expect(await cache.peek('a'), equals('A'));
      await cache.set('c', 'C');

      expect(await cache.containsKey('a'), isTrue);
      expect(await cache.containsKey('b'), isFalse);
      expect(await cache.containsKey('c'), isTrue);
    });

    test('LFUCache peek() does not increment frequency', () async {
      final cache = LFUCache<String, String>(2);

      await cache.set('a', 'A');
      await cache.set('b', 'B');
      expect(await cache.peek('a'), equals('A'));
      await cache.set('c', 'C');

      expect(await cache.containsKey('a'), isFalse);
      expect(await cache.containsKey('b'), isTrue);
      expect(await cache.containsKey('c'), isTrue);
    });
  });

  group('Monitored caches peek()', () {
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
      test('${entry.key} does not record traffic metrics', () async {
        final cache = entry.value();
        addTearDown(() {
          if (cache case Disposable disposable) {
            disposable.dispose();
          }
        });

        await cache.set('present', null);

        expect(await cache.peek('present'), isNull);
        expect(await cache.containsKey('present'), isTrue);
        expect(await cache.peek('missing'), isNull);

        final metrics = switch (cache) {
          MonitoredFIFOCache<String, String?> c => c.metrics,
          MonitoredEphemeralFIFOCache<String, String?> c => c.metrics,
          MonitoredLRUCache<String, String?> c => c.metrics,
          MonitoredMRUCache<String, String?> c => c.metrics,
          MonitoredLFUCache<String, String?> c => c.metrics,
          _ => throw StateError('Unexpected cache type'),
        };
        expect(metrics.hits, equals(0));
        expect(metrics.misses, equals(0));
        expect(metrics.totalRequests, equals(0));
      });
    }
  });

  group('TTL peek()', () {
    DateTime now = DateTime(2024, 1, 1);
    DateTime clock() => now;

    setUp(() {
      now = DateTime(2024, 1, 1);
    });

    test('SimpleTTLCache removes expired keys lazily', () {
      final cache = SimpleTTLCache<String, String?>(
        ttl: const Duration(seconds: 10),
        clock: clock,
      );

      cache.set('present', null);

      expect(cache.peek('present'), isNull);
      expect(cache.containsKey('present'), isTrue);

      now = now.add(const Duration(seconds: 11));

      expect(cache.peek('present'), isNull);
      expect(cache.getKeys(), isNot(contains('present')));
    });

    test('TTLCache removes expired keys lazily', () async {
      final cache = TTLCache<String, String?>(
        ttl: const Duration(seconds: 10),
        clock: clock,
      );

      await cache.set('present', null);

      expect(await cache.peek('present'), isNull);
      expect(await cache.containsKey('present'), isTrue);

      now = now.add(const Duration(seconds: 11));

      expect(await cache.peek('present'), isNull);
      expect(await cache.getKeys(), isNot(contains('present')));
    });

    test('MonitoredTTLCache does not record hit or miss metrics', () async {
      final cache = MonitoredTTLCache<String, String?>(
        ttl: const Duration(seconds: 10),
        clock: clock,
      );
      addTearDown(cache.dispose);

      await cache.set('present', null);

      expect(await cache.peek('present'), isNull);
      expect(await cache.containsKey('present'), isTrue);
      expect(await cache.peek('missing'), isNull);
      expect(cache.metrics.hits, equals(0));
      expect(cache.metrics.misses, equals(0));
      expect(cache.metrics.totalRequests, equals(0));

      now = now.add(const Duration(seconds: 11));

      expect(await cache.peek('present'), isNull);
      expect(await cache.getKeys(), isNot(contains('present')));
      expect(cache.metrics.hits, equals(0));
      expect(cache.metrics.misses, equals(0));
      expect(cache.metrics.totalRequests, equals(0));
      expect(
        cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
        equals(1),
      );
    });
  });
}
