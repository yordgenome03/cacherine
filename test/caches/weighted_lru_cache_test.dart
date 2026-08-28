import 'package:cacherine/src/caches/weighted_lru_cache.dart';
import 'package:test/test.dart';

int _lengthWeigher(String key, String value) => value.length;

void main() {
  group('WeightedLRUCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 20,
        weigher: _lengthWeigher,
      );
      expect(await cache.get('key1'), isNull);
    });

    test('Data set with set() can be retrieved with get()', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 20,
        weigher: _lengthWeigher,
      );
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.get('key2'), equals('value2'));
    });

    test('clear() empties the cache and resets currentWeight', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 20,
        weigher: _lengthWeigher,
      );
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(await cache.getKeys(), isEmpty);
      expect(await cache.currentWeight, equals(0));
    });
  });

  group('WeightedLRUCache - Weight-based Eviction Tests', () {
    test('When storing an entry would exceed maxWeight, the least recently '
        'used entries are evicted', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
      );

      await cache.set('key1', 'aaaaa'); // weight 5
      await cache.set('key2', 'bbbbb'); // weight 5, total 10

      await cache.get('key1'); // key2 becomes least recently used

      await cache.set('key3', 'ccccc'); // evicts key2

      expect(await cache.get('key2'), isNull);
      expect(await cache.get('key1'), equals('aaaaa'));
      expect(await cache.get('key3'), equals('ccccc'));
      expect(await cache.currentWeight, equals(10));
    });

    test('An entry whose own weight exceeds maxWeight is not cached', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 5,
        weigher: _lengthWeigher,
      );

      await cache.set('key1', 'value1'); // weight 6 > maxWeight 5

      expect(await cache.get('key1'), isNull);
      expect(await cache.currentWeight, equals(0));
    });

    test('An explicit weight argument overrides the weigher', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
      );

      await cache.set('key1', 'value1', weight: 3);

      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.currentWeight, equals(3));
    });

    test('An oversized update is rejected as a true no-op — the existing '
        'value survives', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
      );

      await cache.set('key1', 'aaaaa'); // weight 5, fits
      await cache.set('key1', 'value1', weight: 999); // rejected

      expect(await cache.get('key1'), equals('aaaaa'));
      expect(await cache.currentWeight, equals(5));
    });

    test('maxSize is enforced alongside maxWeight', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 1000,
        weigher: _lengthWeigher,
        maxSize: 2,
      );

      await cache.set('key1', 'a');
      await cache.set('key2', 'b');
      await cache.set('key3', 'c');

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), equals('b'));
      expect(await cache.get('key3'), equals('c'));
    });
  });

  group('WeightedLRUCache - Thread-safety Tests', () {
    test('Parallel set() / get() operations work safely', () async {
      final cache = WeightedLRUCache<int, int>(
        maxWeight: 5,
        weigher: (key, value) => 1,
      );

      final futures = List.generate(1000, (i) async {
        await cache.set(i % 5, i);
        return await cache.get(i % 5);
      });

      await Future.wait(futures);

      expect((await cache.getKeys()).length, equals(5));
      expect(await cache.currentWeight, equals(5));
    });

    test('Parallel clear() calls completely clear the cache', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 100,
        weigher: _lengthWeigher,
      );
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3');

      await Future.wait([cache.clear(), cache.clear(), cache.clear()]);

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(await cache.get('key3'), isNull);
      expect(await cache.getKeys(), isEmpty);
    });
  });

  group('WeightedLRUCache - Error Handling', () {
    test('Throws ArgumentError when maxWeight is 0 or less', () {
      expect(
        () => WeightedLRUCache<String, String>(
          maxWeight: 0,
          weigher: _lengthWeigher,
        ),
        throwsArgumentError,
      );
      expect(
        () => WeightedLRUCache<String, String>(
          maxWeight: -1,
          weigher: _lengthWeigher,
        ),
        throwsArgumentError,
      );
    });

    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(
        () => WeightedLRUCache<String, String>(
          maxWeight: 10,
          weigher: _lengthWeigher,
          maxSize: 0,
        ),
        throwsArgumentError,
      );
    });

    test('Throws ArgumentError when an explicit weight is negative', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
      );

      expect(cache.set('key1', 'value1', weight: -1), throwsArgumentError);
    });
  });
}
