import 'package:test/test.dart';
import 'package:cacherine/src/caches/mru_cache.dart';

void main() {
  group('MRUCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () async {
      final cache = MRUCache<String, String>(3);
      expect(await cache.get('key1'), isNull);
    });

    test('Data set with set() can be retrieved with get()', () async {
      final cache = MRUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.get('key2'), equals('value2'));
    });

    test('clear() empties the cache', () async {
      final cache = MRUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('MRUCache - MRU Eviction Tests', () {
    test(
        'When the cache exceeds maxSize, MRU eviction removes the most recently used item',
        () async {
      final cache = MRUCache<String, String>(2);

      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.get('key2'); // Mark key2 as recently used

      await cache.set('key3', 'value3'); // key2 should be evicted

      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.get('key2'), isNull); // key2 should be evicted
      expect(await cache.get('key3'), equals('value3')); // key3 should remain
    });
  });

  group('MRUCache - Thread-safety Tests', () {
    test('Parallel set() / get() operations work safely', () async {
      final cache = MRUCache<int, String>(5);

      final futures = List.generate(1000, (i) async {
        await cache.set(i % 5, 'value$i');
        return await cache.get(i % 5);
      });

      await Future.wait(futures);

      expect(cache.getKeys().length, equals(5));
      expect(cache.getKeys(), containsAll([0, 1, 2, 3, 4]));
    });
  });

  group('MRUCache - Error Handling', () {
    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(() => MRUCache<String, String>(0), throwsArgumentError);
      expect(() => MRUCache<String, String>(-1), throwsArgumentError);
    });
  });
}
