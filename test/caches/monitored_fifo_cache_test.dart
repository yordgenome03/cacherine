import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  group('MonitoredFIFOCache Tests', () {
    final CacheAlertConfig config = CacheAlertConfig(notifyCallback: (_) {});

    test('Stored data should be retrievable', () async {
      final cache = MonitoredFIFOCache<String, String>(
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
      'FIFO eviction should remove the oldest element when maxSize is exceeded',
      () async {
        final cache = MonitoredFIFOCache<String, String>(
          maxSize: 2,
          alertConfig: config,
        );

        await cache.set('key1', 'value1');
        await cache.set('key2', 'value2');
        await cache.set('key3', 'value3'); // 'key1' should be removed

        expect(await cache.get('key1'), isNull); // 'key1' should be evicted
        expect(await cache.get('key2'), equals('value2'));
        expect(await cache.get('key3'), equals('value3'));
      },
    );

    test(
      'Cache should maintain data integrity under concurrent access',
      () async {
        final cache = MonitoredFIFOCache<int, int>(
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
      final cache = MonitoredFIFOCache<String, String>(
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

    test(
      'get() records a stored null as a hit without changing FIFO order',
      () async {
        final cache = MonitoredFIFOCache<String, String?>(
          maxSize: 2,
          alertConfig: config,
        );

        await cache.set('key1', null);
        await cache.set('key2', 'value2');
        expect(await cache.get('key1'), isNull);
        await cache.set('key3', 'value3');

        expect(cache.metrics.hits, equals(1));
        expect(cache.metrics.misses, equals(0));
        expect(await cache.getKeys(), containsAll(['key2', 'key3']));
        expect(await cache.getKeys(), isNot(contains('key1')));
      },
    );

    test('clear() should remove all cache entries', () async {
      final cache = MonitoredFIFOCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );

      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(await cache.getKeys(), isEmpty);
    });

    test(
      'set() on an existing key when cache is full does not evict any entry',
      () async {
        final cache = MonitoredFIFOCache<String, String>(
          maxSize: 2,
          alertConfig: config,
        );
        await cache.set('key1', 'value1');
        await cache.set('key2', 'value2');

        // Update the non-oldest key (key2). With the buggy implementation that
        // lacked the containsKey guard, key1 (oldest) would be evicted here.
        await cache.set('key2', 'new_value2');

        expect(await cache.get('key1'), equals('value1'));
        expect(await cache.get('key2'), equals('new_value2'));
        expect((await cache.getKeys()).length, equals(2));
      },
    );

    test('Should throw an exception if maxSize is 0 or negative', () {
      expect(
        () =>
            MonitoredFIFOCache<String, String>(maxSize: 0, alertConfig: config),
        throwsArgumentError,
      );
    });
  });

  group('MonitoredFIFOCache - remove()', () {
    final config = CacheAlertConfig(notifyCallback: (_) {});

    test('remove() existing key records eviction in metrics', () async {
      final cache = MonitoredFIFOCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );
      await cache.set('key1', 'value1');
      await cache.remove('key1');
      expect(await cache.get('key1'), isNull);
      final stats = cache.metrics.getRecentStats(const Duration(minutes: 1));
      expect(stats['evictions_per_minute'], equals(1));
    });

    test('remove() non-existent key does not record eviction', () async {
      final cache = MonitoredFIFOCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );
      await cache.remove('missing');
      final stats = cache.metrics.getRecentStats(const Duration(minutes: 1));
      expect(stats['evictions_per_minute'], equals(0));
    });

    test('capacity eviction via set() records eviction in metrics', () async {
      final cache = MonitoredFIFOCache<String, String>(
        maxSize: 2,
        alertConfig: config,
      );
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3'); // triggers FIFO eviction of key1
      final stats = cache.metrics.getRecentStats(const Duration(minutes: 1));
      expect(stats['evictions_per_minute'], equals(1));
    });

    test('dispose() implements Disposable and stops the timer', () {
      final cache = MonitoredFIFOCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );
      expect(cache, isA<Disposable>());
      expect(cache.dispose, returnsNormally);
    });
  });
}
