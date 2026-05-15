import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  group('MonitoredLFUCache Tests', () {
    final CacheAlertConfig config = CacheAlertConfig(notifyCallback: (_) {});

    test('Stored data should be retrievable', () async {
      final cache = MonitoredLFUCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );

      await cache.set('key1', 'value1');
      expect(
        await cache.get('key1'),
        equals('value1'),
      ); // Retrieved successfully
    });

    test(
      'LFU eviction should remove the least frequently used element when maxSize is exceeded',
      () async {
        final cache = MonitoredLFUCache<String, String>(
          maxSize: 2,
          alertConfig: config,
        );

        await cache.set('key1', 'value1');
        await cache.set('key2', 'value2');
        await cache.get('key1'); // Increase usage count for key1
        await cache.set(
          'key3',
          'value3',
        ); // 'key2' should be removed (least used)

        expect(await cache.get('key2'), isNull); // 'key2' should be evicted
        expect(
          await cache.get('key1'),
          equals('value1'),
        ); // Still exists due to usage count
        expect(await cache.get('key3'), equals('value3'));
      },
    );

    test(
      'Cache should maintain data integrity under concurrent access',
      () async {
        final cache = MonitoredLFUCache<int, int>(
          maxSize: 10,
          alertConfig: config,
        );

        final futures = List.generate(100, (i) async {
          await cache.set(i, i * 10);
          final value = await cache.get(i);
          expect(
            value,
            anyOf(isNull, equals(i * 10)),
          ); // Either retrieved or already removed
        });

        await Future.wait(futures);
      },
    );

    test('Cache hit/miss rates should be correctly recorded', () async {
      final cache = MonitoredLFUCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );

      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      await cache.get('key1'); // Cache hit
      await cache.get('key3'); // Cache miss
      await cache.get('key2'); // Cache hit

      final metrics = cache.metrics;
      expect(metrics.hits, equals(2));
      expect(metrics.misses, equals(1));
    });

    test('clear() should remove all cache entries', () async {
      final cache = MonitoredLFUCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );

      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });

    test(
      'set() on an existing key when cache is full does not evict any entry',
      () async {
        final cache = MonitoredLFUCache<String, String>(
          maxSize: 2,
          alertConfig: config,
        );
        await cache.set('key1', 'value1');
        await cache.set('key2', 'value2');

        await cache.set('key1', 'new_value1');

        expect(await cache.get('key1'), equals('new_value1'));
        expect(await cache.get('key2'), equals('value2'));
        expect(cache.getKeys().length, equals(2));
      },
    );

    test(
      'set() on an existing key preserves its usage count',
      () async {
        final cache = MonitoredLFUCache<String, String>(
          maxSize: 2,
          alertConfig: config,
        );
        await cache.set('key1', 'value1');
        await cache.set('key2', 'value2');

        // Boost key1's usage count
        await cache.get('key1');
        await cache.get('key1');

        // Update key1 — count must be preserved, not reset to 1
        await cache.set('key1', 'updated');

        // Inserting key3 forces eviction; key2 (count 1) must go, not key1 (count 3)
        await cache.set('key3', 'value3');

        expect(await cache.get('key2'), isNull);
        expect(await cache.get('key1'), equals('updated'));
        expect(await cache.get('key3'), equals('value3'));
      },
    );

    test('Should throw an exception if maxSize is 0 or negative', () {
      expect(
        () =>
            MonitoredLFUCache<String, String>(maxSize: 0, alertConfig: config),
        throwsArgumentError,
      );
    });
  });
}
