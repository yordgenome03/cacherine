import 'package:test/test.dart';
import 'package:cacherine/src/caches/simple_fifo_cache.dart';

void main() {
  group('SimpleFIFOCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () {
      final cache = SimpleFIFOCache<String, String>(3);
      expect(cache.get('key1'), isNull);
    });

    test('Data set with set() can be retrieved with get()', () {
      final cache = SimpleFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      expect(cache.get('key1'), equals('value1'));
      expect(cache.get('key2'), equals('value2'));
    });

    test('clear() empties the cache', () {
      final cache = SimpleFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.clear();

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('SimpleFIFOCache - FIFO Eviction Tests', () {
    test(
        'When the cache exceeds maxSize, FIFO eviction removes the oldest item',
        () {
      final cache = SimpleFIFOCache<String, String>(2);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key3', 'value3'); // key1 should be evicted

      expect(cache.get('key1'), isNull); // key1 should be evicted
      expect(cache.get('key2'), equals('value2'));
      expect(cache.get('key3'), equals('value3'));
    });

    test(
        'When the same key is set again, it is placed at the most recent position',
        () {
      final cache = SimpleFIFOCache<String, String>(2);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key1', 'new_value1'); // key1 is placed at the newest position

      cache.set('key3', 'value3'); // key2, being the oldest, should be evicted

      expect(cache.get('key2'), isNull); // key2 should be evicted
      expect(cache.get('key1'), equals('new_value1'));
      expect(cache.get('key3'), equals('value3'));
    });
  });

  group('SimpleFIFOCache - Additional Behavior Validation', () {
    test('Behavior with maxSize=1 (always keeps only the most recent item)',
        () {
      final cache = SimpleFIFOCache<String, String>(1);
      cache.set('key1', 'value1');
      expect(cache.get('key1'), equals('value1'));

      cache.set(
          'key2', 'value2'); // 'key1' should be evicted, only 'key2' remains
      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), equals('value2'));
    });

    test('Retrieving a non-existing key returns null', () {
      final cache = SimpleFIFOCache<String, String>(3);
      expect(cache.get('non_existing_key'), isNull);
    });

    test('getKeys() correctly returns the current keys', () {
      final cache = SimpleFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key3', 'value3');

      expect(cache.getKeys(), containsAll(['key1', 'key2', 'key3']));

      cache.set('key4', 'value4'); // 'key1' should be evicted
      expect(cache.getKeys(), containsAll(['key2', 'key3', 'key4']));
      expect(
          cache.getKeys(), isNot(contains('key1'))); // 'key1' should be evicted
    });

    test('Cache string representation (toString() test)', () {
      final cache = SimpleFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key3', 'value3');

      final cacheString = cache.toString();
      expect(cacheString, contains('key1: value1'));
      expect(cacheString, contains('key2: value2'));
      expect(cacheString, contains('key3: value3'));
    });
  });

  group('SimpleFIFOCache - Error Handling', () {
    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(() => SimpleFIFOCache<String, String>(0), throwsArgumentError);
      expect(() => SimpleFIFOCache<String, String>(-1), throwsArgumentError);
    });
  });
}
