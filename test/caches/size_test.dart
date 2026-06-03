import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  group('SimpleCache size state', () {
    final factories = <String, SimpleCache<String, String> Function()>{
      'SimpleFIFOCache': () => SimpleFIFOCache<String, String>(2),
      'SimpleEphemeralFIFOCache': () =>
          SimpleEphemeralFIFOCache<String, String>(2),
      'SimpleLRUCache': () => SimpleLRUCache<String, String>(2),
      'SimpleMRUCache': () => SimpleMRUCache<String, String>(2),
      'SimpleLFUCache': () => SimpleLFUCache<String, String>(2),
    };

    for (final entry in factories.entries) {
      test('${entry.key} reports size and emptiness', () {
        final cache = entry.value();

        expect(cache.size, equals(0));
        expect(cache.isEmpty, isTrue);
        expect(cache.isNotEmpty, isFalse);

        cache.set('a', 'A');
        cache.set('b', 'B');
        cache.set('c', 'C');

        expect(cache.size, equals(2));
        expect(cache.isEmpty, isFalse);
        expect(cache.isNotEmpty, isTrue);

        cache.remove('c');

        expect(cache.size, equals(1));

        cache.clear();

        expect(cache.size, equals(0));
        expect(cache.isEmpty, isTrue);
      });
    }

    test('SimpleEphemeralFIFOCache size excludes consumed entries', () {
      final cache = SimpleEphemeralFIFOCache<String, String>(2);

      cache.set('a', 'A');
      cache.set('b', 'B');
      expect(cache.get('a'), equals('A'));

      expect(cache.size, equals(1));
      expect(cache.isNotEmpty, isTrue);
    });
  });

  group('ThreadSafeCache size state', () {
    final factories = <String, ThreadSafeCache<String, String> Function()>{
      'FIFOCache': () => FIFOCache<String, String>(2),
      'EphemeralFIFOCache': () => EphemeralFIFOCache<String, String>(2),
      'LRUCache': () => LRUCache<String, String>(2),
      'MRUCache': () => MRUCache<String, String>(2),
      'LFUCache': () => LFUCache<String, String>(2),
    };

    for (final entry in factories.entries) {
      test('${entry.key} reports size and emptiness', () async {
        final cache = entry.value();

        expect(await cache.size, equals(0));
        expect(await cache.isEmpty, isTrue);
        expect(await cache.isNotEmpty, isFalse);

        await cache.set('a', 'A');
        await cache.set('b', 'B');
        await cache.set('c', 'C');

        expect(await cache.size, equals(2));
        expect(await cache.isEmpty, isFalse);
        expect(await cache.isNotEmpty, isTrue);

        await cache.remove('c');

        expect(await cache.size, equals(1));

        await cache.clear();

        expect(await cache.size, equals(0));
        expect(await cache.isEmpty, isTrue);
      });
    }

    test('EphemeralFIFOCache size excludes consumed entries', () async {
      final cache = EphemeralFIFOCache<String, String>(2);

      await cache.set('a', 'A');
      await cache.set('b', 'B');
      expect(await cache.get('a'), equals('A'));

      expect(await cache.size, equals(1));
      expect(await cache.isNotEmpty, isTrue);
    });
  });

  group('TTL size state', () {
    DateTime now = DateTime(2024, 1, 1);
    DateTime clock() => now;

    setUp(() {
      now = DateTime(2024, 1, 1);
    });

    test('SimpleTTLCache counts only live entries', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: clock,
      );

      cache.set('short', 'A', ttl: const Duration(seconds: 5));
      cache.set('long', 'B');

      expect(cache.size, equals(2));

      now = now.add(const Duration(seconds: 6));

      expect(cache.size, equals(1));
      expect(cache.isEmpty, isFalse);

      now = now.add(const Duration(seconds: 5));

      expect(cache.size, equals(0));
      expect(cache.isEmpty, isTrue);
    });

    test('TTLCache counts only live entries', () async {
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: clock,
      );

      await cache.set('short', 'A', ttl: const Duration(seconds: 5));
      await cache.set('long', 'B');

      expect(await cache.size, equals(2));

      now = now.add(const Duration(seconds: 6));

      expect(await cache.size, equals(1));
      expect(await cache.isEmpty, isFalse);

      now = now.add(const Duration(seconds: 5));

      expect(await cache.size, equals(0));
      expect(await cache.isEmpty, isTrue);
    });

    test(
      'MonitoredTTLCache counts only live entries without traffic metrics',
      () async {
        final cache = MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: 10),
          clock: clock,
        );
        addTearDown(cache.dispose);

        await cache.set('short', 'A', ttl: const Duration(seconds: 5));
        await cache.set('long', 'B');

        expect(await cache.size, equals(2));

        now = now.add(const Duration(seconds: 6));

        expect(await cache.size, equals(1));
        expect(await cache.isNotEmpty, isTrue);
        expect(cache.metrics.hits, equals(0));
        expect(cache.metrics.misses, equals(0));
        expect(cache.metrics.totalRequests, equals(0));
      },
    );
  });

  group('Monitored cache size state', () {
    final factories = <String, ThreadSafeCache<String, String> Function()>{
      'MonitoredFIFOCache': () => MonitoredFIFOCache(maxSize: 2),
      'MonitoredEphemeralFIFOCache': () =>
          MonitoredEphemeralFIFOCache(maxSize: 2),
      'MonitoredLRUCache': () => MonitoredLRUCache(maxSize: 2),
      'MonitoredMRUCache': () => MonitoredMRUCache(maxSize: 2),
      'MonitoredLFUCache': () => MonitoredLFUCache(maxSize: 2),
    };

    for (final entry in factories.entries) {
      test('${entry.key} does not record traffic metrics', () async {
        final cache = entry.value();
        addTearDown(() {
          if (cache case Disposable disposable) {
            disposable.dispose();
          }
        });

        await cache.set('a', 'A');
        await cache.set('b', 'B');

        expect(await cache.size, equals(2));
        expect(await cache.isEmpty, isFalse);
        expect(await cache.isNotEmpty, isTrue);

        final metrics = switch (cache) {
          MonitoredFIFOCache<String, String> c => c.metrics,
          MonitoredEphemeralFIFOCache<String, String> c => c.metrics,
          MonitoredLRUCache<String, String> c => c.metrics,
          MonitoredMRUCache<String, String> c => c.metrics,
          MonitoredLFUCache<String, String> c => c.metrics,
          _ => throw StateError('Unexpected cache type'),
        };
        expect(metrics.hits, equals(0));
        expect(metrics.misses, equals(0));
        expect(metrics.totalRequests, equals(0));
      });
    }
  });
}
