import 'package:cacherine/src/caches/fifo_cache.dart';
import 'package:test/test.dart';

void main() {
  group('FIFOCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () async {
      final cache = FIFOCache<String, String>(3);
      expect(await cache.get('key1'), isNull);
    });

    test('Data set with set() can be retrieved with get()', () async {
      final cache = FIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.get('key2'), equals('value2'));
    });

    test('clear() empties the cache', () async {
      final cache = FIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });

    test('getKeys() works correctly (returns current keys)', () async {
      final cache = FIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3');

      expect(cache.getKeys(), containsAll(['key1', 'key2', 'key3']));

      await cache.set('key4', 'value4'); // 'key1' will be removed
      expect(cache.getKeys(), containsAll(['key2', 'key3', 'key4']));
      expect(cache.getKeys(), isNot(contains('key1'))); // 'key1' is removed
    });

    test('Cache string representation (testing toString())', () async {
      final cache = FIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3');

      final cacheString = cache.toString();
      expect(cacheString, contains('key1: value1'));
      expect(cacheString, contains('key2: value2'));
      expect(cacheString, contains('key3: value3'));
    });
  });

  group('FIFOCache - FIFO Eviction Tests', () {
    test(
        'When the cache exceeds maxSize, FIFO eviction removes the oldest item',
        () async {
      final cache = FIFOCache<String, String>(2);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3'); // key1 should be evicted

      expect(await cache.get('key1'), isNull); // key1 should be removed
      expect(await cache.get('key2'), equals('value2'));
      expect(await cache.get('key3'), equals('value3'));
    });

    test('Setting the same key again with set() does not change the order',
        () async {
      final cache = FIFOCache<String, String>(2);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key1', 'new_value1'); // Order does not change

      await cache.set('key3', 'value3'); // key2 will be evicted (FIFO order)

      expect(await cache.get('key2'), isNull); // key2 should be removed
      expect(await cache.get('key1'),
          equals('new_value1')); // key1 should remain with new value
      expect(await cache.get('key3'), equals('value3')); // key3 should be set
    });
  });

  group('FIFOCache - Thread-safety Tests', () {
    test('Parallel set() / get() operations work safely', () async {
      final cache = FIFOCache<int, String>(5);

      // Perform 1000 parallel set & get operations
      final futures = List.generate(1000, (i) async {
        await cache.set(i % 5,
            'value$i'); // values for keys 0 to 4 will be continuously updated
        return await cache.get(i % 5); // Check if value can be retrieved
      });

      // Wait for all async operations to complete
      await Future.wait(futures);

      // Confirm that only 5 items remain in the cache
      expect(cache.getKeys().length, equals(5));

      // keys 0 to 4 should exist in the cache
      final keys = cache.getKeys();
      expect(keys, containsAll([0, 1, 2, 3, 4]));
    });

    test('Parallel clear() calls remove all data', () async {
      final cache = FIFOCache<String, String>(5);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3');

      // Perform parallel clear() calls
      await Future.wait([
        cache.clear(),
        cache.clear(),
        cache.clear(),
      ]);

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(await cache.get('key3'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('FIFOCache - Error Handling', () {
    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(() => FIFOCache<String, String>(0), throwsArgumentError);
      expect(() => FIFOCache<String, String>(-1), throwsArgumentError);
    });
  });
}
