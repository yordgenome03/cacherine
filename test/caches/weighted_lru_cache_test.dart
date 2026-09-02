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

    // Unlike set(), which silently no-ops on a write that can never fit
    // (the test above), update()/getOrCompute() have a non-void return
    // contract and instead throw StateError — this is AsyncCache's own
    // documented behavior, inherited unchanged since WeightedLRUCache
    // extends it directly, but was never exercised through this subclass.
    test('An oversized update() throws StateError instead of silently '
        'rejecting, and leaves the existing value untouched', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
      );

      await cache.set('key1', 'aaaaa'); // weight 5, fits

      await expectLater(
        () => cache.update('key1', (v) async => 'value1', weight: 999),
        throwsStateError,
      );

      expect(await cache.get('key1'), equals('aaaaa'));
      expect(await cache.currentWeight, equals(5));
    });

    test('An oversized getOrCompute() miss throws StateError and stores '
        'nothing', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
      );

      await expectLater(
        () => cache.getOrCompute('key1', () async => 'value1', weight: 999),
        throwsStateError,
      );

      expect(await cache.containsKey('key1'), isFalse);
      expect(await cache.currentWeight, equals(0));
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

    // A weigher is user-supplied and can throw (e.g. a bug in a
    // size-estimation function). No prior test exercised this — confirms
    // the exception propagates without leaving a partial entry behind, and
    // that AsyncCache's lock is released rather than leaked (a subsequent
    // operation completes instead of hanging).
    test('a throwing weigher leaves the cache untouched and does not leak '
        'the lock', () async {
      final cache = WeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: (key, value) => throw StateError('boom'),
      );

      await expectLater(() => cache.set('key1', 'value1'), throwsStateError);

      expect(await cache.containsKey('key1'), isFalse);
      expect(await cache.currentWeight, equals(0));
      await expectLater(
        cache.get('key1').timeout(const Duration(seconds: 5)),
        completion(isNull),
      );
    });
  });
}
