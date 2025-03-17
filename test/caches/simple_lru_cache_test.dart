import 'package:test/test.dart';
import 'package:cacherine/src/caches/simple_lru_cache.dart';

void main() {
  group('SimpleLRUCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () {
      final cache = SimpleLRUCache<String, String>(3);
      expect(cache.get('key1'), isNull);
    });

    test('Data set with set() can be retrieved using get()', () {
      final cache = SimpleLRUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      expect(cache.get('key1'), equals('value1'));
      expect(cache.get('key2'), equals('value2'));
    });

    test('clear() empties the cache', () {
      final cache = SimpleLRUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.clear();

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('SimpleLRUCache - LRU Eviction Tests', () {
    test(
      'When the cache exceeds maxSize, LRU eviction removes the least recently used item',
      () {
        final cache = SimpleLRUCache<String, String>(2);

        // Add key1 and key2
        cache.set('key1', 'value1');
        cache.set('key2', 'value2');

        // Access key1 to increase its usage count
        cache.get('key1');

        // Add key3, causing the cache to exceed maxSize
        cache.set(
          'key3',
          'value3',
        ); // key2 is the least recently used, so it will be evicted

        // Check if key2 was evicted
        expect(cache.get('key2'), isNull); // key2 should be evicted
        expect(
          cache.get('key1'),
          equals('value1'),
        ); // key1 should remain since it was accessed
        expect(
          cache.get('key3'),
          equals('value3'),
        ); // key3 should remain since it was newly added
      },
    );

    test(
      'When the same key is set again, it is placed at the most recent position',
      () {
        final cache = SimpleLRUCache<String, String>(2);
        cache.set('key1', 'value1');
        cache.set('key2', 'value2');
        cache.set(
          'key1',
          'new_value1',
        ); // key1 should be placed at the most recent position

        cache.set(
          'key3',
          'value3',
        ); // The least recently used 'key2' will be evicted

        expect(cache.get('key2'), isNull); // key2 should be evicted
        expect(
          cache.get('key1'),
          equals('new_value1'),
        ); // key1 should remain with the new value
        expect(
          cache.get('key3'),
          equals('value3'),
        ); // key3 should remain since it was newly added
      },
    );
  });

  group('SimpleLRUCache - Error Handling', () {
    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(() => SimpleLRUCache<String, String>(0), throwsArgumentError);
      expect(() => SimpleLRUCache<String, String>(-1), throwsArgumentError);
    });
  });
}
