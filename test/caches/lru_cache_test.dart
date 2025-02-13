import 'package:test/test.dart';
import 'package:cacherine/src/caches/lru_cache.dart';

void main() {
  group('LRUCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () async {
      final cache = LRUCache<String, String>(3);
      expect(await cache.get('key1'), isNull);
    });

    test('Data set with set() can be retrieved with get()', () async {
      final cache = LRUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.get('key2'), equals('value2'));
    });

    test('clear() empties the cache', () async {
      final cache = LRUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('LRUCache - LRU Eviction Tests', () {
    test(
        'When the cache exceeds maxSize, LRU eviction removes the least recently used item',
        () async {
      final cache = LRUCache<String, String>(2);

      // Adding key1 and key2
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      // Access key1 to mark it as recently used
      await cache.get('key1');

      // Adding key3 will cause key2 to be evicted
      await cache.set('key3', 'value3');

      expect(await cache.get('key2'), isNull); // key2 should be evicted
      expect(await cache.get('key1'), equals('value1')); // key1 should remain
      expect(await cache.get('key3'), equals('value3')); // key3 should remain
    });

    test('Re-setting the same key places it at the most recent position',
        () async {
      final cache = LRUCache<String, String>(2);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key1', 'new_value1'); // Re-set key1

      // Adding key3 will cause the least recently used key (key2) to be evicted
      await cache.set('key3', 'value3');

      expect(await cache.get('key2'), isNull); // key2 should be evicted
      expect(await cache.get('key1'),
          equals('new_value1')); // key1 should remain with the new value
      expect(await cache.get('key3'), equals('value3')); // key3 should remain
    });
  });

  group('LRUCache - Thread-safety Tests', () {
    test('Parallel set() / get() operations work safely', () async {
      final cache = LRUCache<int, String>(5);

      // Perform 1000 parallel set & get operations
      final futures = List.generate(1000, (i) async {
        await cache.set(i % 5,
            'value$i'); // Values for keys 0 to 4 will be continuously updated
        return await cache.get(i % 5); // Check if value can be retrieved
      });

      await Future.wait(futures);

      // Ensure only 5 items remain in the cache
      expect(cache.getKeys().length, equals(5));

      // At least one key from 0 to 4 should be present in the cache
      final keys = cache.getKeys();
      expect(keys, containsAll([0, 1, 2, 3, 4]));
    });

    test('Parallel clear() calls completely clear the cache', () async {
      final cache = LRUCache<String, String>(5);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3');

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

  group('LRUCache - Error Handling', () {
    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(() => LRUCache<String, String>(0), throwsArgumentError);
      expect(() => LRUCache<String, String>(-1), throwsArgumentError);
    });
  });
}
