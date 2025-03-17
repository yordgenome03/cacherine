import 'package:test/test.dart';
import 'package:cacherine/src/caches/simple_mru_cache.dart';

void main() {
  group('SimpleMRUCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () {
      final cache = SimpleMRUCache<String, String>(3);
      expect(cache.get('key1'), isNull);
    });

    test('Data set with set() can be retrieved using get()', () {
      final cache = SimpleMRUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      expect(cache.get('key1'), equals('value1'));
      expect(cache.get('key2'), equals('value2'));
    });

    test('clear() empties the cache', () {
      final cache = SimpleMRUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.clear();

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('SimpleMRUCache - MRU Eviction Tests', () {
    test(
      'When the cache exceeds maxSize, MRU eviction removes the most recently used item',
      () {
        final cache = SimpleMRUCache<String, String>(2);

        // Add key1 and key2
        cache.set('key1', 'value1');
        cache.set('key2', 'value2');

        // Access key1 to increase its usage count
        cache.get('key1');

        // Add key3, causing the cache to exceed maxSize
        cache.set(
          'key3',
          'value3',
        ); // key1 is the most recently used and should be evicted

        // Verify that key1 is evicted
        expect(cache.get('key1'), isNull); // key1 should be evicted
        expect(
          cache.get('key2'),
          equals('value2'),
        ); // key2 should remain as it was used
        expect(
          cache.get('key3'),
          equals('value3'),
        ); // key3 should remain as it was newly added
      },
    );

    test('', () {
      final cache = SimpleMRUCache<String, String>(2);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key1', 'new_value1');

      cache.set('key3', 'value3');

      expect(cache.get('key1'), isNull); // key2 should be evicted
      expect(cache.get('key2'), equals('value2'));
      expect(
        cache.get('key3'),
        equals('value3'),
      ); // key3 should remain as it was newly added
    });
  });

  group('SimpleMRUCache - Error Handling', () {
    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(() => SimpleMRUCache<String, String>(0), throwsArgumentError);
      expect(() => SimpleMRUCache<String, String>(-1), throwsArgumentError);
    });
  });
}
