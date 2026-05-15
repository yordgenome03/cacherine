import 'package:test/test.dart';
import 'package:cacherine/src/caches/simple_lfu_cache.dart';

void main() {
  group('SimpleLFUCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () {
      final cache = SimpleLFUCache<String, String>(3);
      expect(cache.get('key1'), isNull);
    });

    test('Data set with set() can be retrieved using get()', () {
      final cache = SimpleLFUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      expect(cache.get('key1'), equals('value1'));
      expect(cache.get('key2'), equals('value2'));
    });

    test('clear() empties the cache', () {
      final cache = SimpleLFUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.clear();

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('SimpleLFUCache - LFU Eviction Tests', () {
    test(
      'When the cache exceeds maxSize, LFU eviction removes the least frequently used item',
      () {
        final cache = SimpleLFUCache<String, String>(2);

        // First, add key1 and key2
        cache.set('key1', 'value1');
        cache.set('key2', 'value2');

        // Increase the usage count of key1 by calling get()
        cache.get('key1');

        // Add key3, causing the cache to exceed maxSize
        cache.set(
          'key3',
          'value3',
        ); // key2 will be evicted since it is the least frequently used

        // Check that key2 was evicted
        expect(cache.get('key2'), isNull); // key2 should have been evicted
        expect(
          cache.get('key1'),
          equals('value1'),
        ); // key1 should remain since it is more frequently used
        expect(
          cache.get('key3'),
          equals('value3'),
        ); // key3 should remain as it was newly added
      },
    );

    test(
      'When the same key is set again, it is placed at the most recent position',
      () {
        final cache = SimpleLFUCache<String, String>(2);
        cache.set('key1', 'value1');
        cache.set('key2', 'value2');
        cache.set(
          'key1',
          'new_value1',
        ); // key1 should be placed at the most recent position

        cache.set(
          'key3',
          'value3',
        ); // The least frequently used 'key2' will be evicted

        expect(cache.get('key2'), isNull); // key2 should have been evicted
        expect(
          cache.get('key1'),
          equals('new_value1'),
        ); // key1 should remain with the new value
        expect(
          cache.get('key3'),
          equals('value3'),
        ); // key3 should remain as it was newly added
      },
    );

    test(
      'set() on an existing key when cache is full does not evict any entry',
      () {
        final cache = SimpleLFUCache<String, String>(2);
        cache.set('key1', 'value1');
        cache.set('key2', 'value2');

        cache.set('key1', 'new_value1');

        expect(cache.get('key1'), equals('new_value1'));
        expect(cache.get('key2'), equals('value2'));
        expect(cache.getKeys().length, equals(2));
      },
    );

    test('set() on an existing key does not reset its usage count', () {
      final cache = SimpleLFUCache<String, String>(2);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      // Boost key1's usage count
      cache.get('key1');
      cache.get('key1');

      // Update key1 — count must be preserved, not reset to 1
      cache.set('key1', 'updated');

      // Inserting key3 forces eviction; key2 (count 1) must go, not key1 (count 3)
      cache.set('key3', 'value3');

      expect(cache.get('key2'), isNull);
      expect(cache.get('key1'), equals('updated'));
      expect(cache.get('key3'), equals('value3'));
    });
  });

  group('SimpleLFUCache - Error Handling', () {
    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(() => SimpleLFUCache<String, String>(0), throwsArgumentError);
      expect(() => SimpleLFUCache<String, String>(-1), throwsArgumentError);
    });
  });

  group('SimpleLFUCache - toString()', () {
    test('toString() returns key-value pairs as a string', () {
      final cache = SimpleLFUCache<String, String>(3);
      cache.set('a', '1');
      cache.set('b', '2');
      final result = cache.toString();
      expect(result, contains('a'));
      expect(result, contains('1'));
      expect(result, contains('b'));
      expect(result, contains('2'));
    });
  });

  group('SimpleLFUCache - remove()', () {
    test('remove() existing key makes get() return null', () {
      final cache = SimpleLFUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.remove('key1');
      expect(cache.get('key1'), isNull);
      expect(cache.getKeys(), isNot(contains('key1')));
    });

    test('remove() non-existent key is a no-op', () {
      final cache = SimpleLFUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.remove('missing');
      expect(cache.get('key1'), equals('value1'));
      expect(cache.getKeys().length, equals(1));
    });

    test(
      'remove() discards frequency counter so LFU ordering is unaffected',
      () {
        final cache = SimpleLFUCache<String, String>(2);
        cache.set('key1', 'value1');
        cache.set('key2', 'value2');
        cache.get('key2'); // key2 freq=2, key1 freq=1
        cache.remove('key1');
        // Re-add key1 — should start fresh with freq=1
        cache.set('key1', 'new1');
        // key1 (freq=1) is LFU; inserting key3 should evict key1
        cache.set('key3', 'value3');
        expect(cache.get('key1'), isNull);
        expect(cache.get('key2'), equals('value2'));
        expect(cache.get('key3'), equals('value3'));
      },
    );
  });
}
