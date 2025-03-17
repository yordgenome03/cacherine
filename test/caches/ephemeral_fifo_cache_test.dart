import 'package:test/test.dart';
import 'package:cacherine/src/caches/ephemeral_fifo_cache.dart';

void main() {
  group('EphemeralFIFOCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      expect(await cache.get('key1'), isNull);
    });

    test('set() data can be retrieved with get()', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      expect(await cache.get('key1'), equals('value1'));
    });

    test('Data retrieved with get() is removed from the cache', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      expect(await cache.get('key1'), equals('value1'));
      expect(
        await cache.get('key1'),
        isNull,
      ); // It should be removed after retrieval
    });

    test('clear() empties the cache', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('EphemeralFIFOCache - FIFO Eviction Tests', () {
    test(
      'When the cache exceeds maxSize, FIFO eviction removes the oldest item',
      () async {
        final cache = EphemeralFIFOCache<String, String>(2);
        await cache.set('key1', 'value1');
        await cache.set('key2', 'value2');
        await cache.set('key3', 'value3'); // key1 should be evicted (FIFO)

        expect(await cache.get('key1'), isNull); // key1 should be removed
        expect(await cache.get('key2'), equals('value2'));
        expect(await cache.get('key3'), equals('value3'));
      },
    );

    test('Setting the same key with set() does not change the order', () async {
      final cache = EphemeralFIFOCache<String, String>(2);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set(
        'key1',
        'new_value1',
      ); // key1 is placed at the most recent position

      await cache.set(
        'key3',
        'value3',
      ); // The oldest key, key2, should be evicted

      expect(await cache.get('key2'), isNull); // key2 should be removed
      expect(await cache.get('key1'), equals('new_value1'));
      expect(await cache.get('key3'), equals('value3'));
    });
  });

  group('EphemeralFIFOCache - Thread-safety Tests', () {
    test('Parallel set() / get() operations work safely', () async {
      final cache = EphemeralFIFOCache<int, String>(5);

      // Perform 1000 parallel set & get operations
      final futures = List.generate(1000, (i) async {
        await cache.set(
          i % 5,
          'value$i',
        ); // keys 0 to 4 will be updated continuously
        return await cache.get(
          i % 5,
        ); // Check if value can be retrieved (and is deleted immediately after)
      });

      // Wait for all async operations to complete
      await Future.wait(futures);

      // Confirm that no values are left in the cache
      expect(cache.getKeys().isEmpty, isTrue);
    });

    test('Parallel clear() calls remove all data', () async {
      final cache = EphemeralFIFOCache<String, String>(5);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3');

      // Perform parallel clear() calls
      await Future.wait([cache.clear(), cache.clear(), cache.clear()]);

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(await cache.get('key3'), isNull);
      expect(cache.getKeys(), isEmpty);
    });

    test(
      'Calling toString() during parallel processing does not cause errors',
      () async {
        final cache = EphemeralFIFOCache<int, String>(5);
        await cache.set(1, 'value1');
        await cache.set(2, 'value2');
        await cache.set(3, 'value3');

        // Perform parallel get() and toString() calls
        final futures = List.generate(1000, (i) async {
          await cache.get(i % 3);
          return cache.toString();
        });

        final results = await Future.wait(futures);
        expect(
          results.length,
          equals(1000),
        ); // All toString() calls should work without errors
      },
    );
  });

  group('EphemeralFIFOCache - Error Handling', () {
    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(() => EphemeralFIFOCache<String, String>(0), throwsArgumentError);
      expect(() => EphemeralFIFOCache<String, String>(-1), throwsArgumentError);
    });
  });
}
