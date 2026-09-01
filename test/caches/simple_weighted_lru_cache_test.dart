import 'package:cacherine/src/caches/simple_weighted_lru_cache.dart';
import 'package:test/test.dart';

int _lengthWeigher(String key, String value) => value.length;

void main() {
  group('SimpleWeightedLRUCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 20,
        weigher: _lengthWeigher,
      );
      expect(cache.get('key1'), isNull);
    });

    test('Data set with set() can be retrieved using get()', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 20,
        weigher: _lengthWeigher,
      );
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      expect(cache.get('key1'), equals('value1'));
      expect(cache.get('key2'), equals('value2'));
    });

    test('clear() empties the cache and resets currentWeight', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 20,
        weigher: _lengthWeigher,
      );
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.clear();

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
      expect(cache.currentWeight, equals(0));
    });
  });

  group('SimpleWeightedLRUCache - Weight-based Eviction Tests', () {
    test('currentWeight tracks the sum of stored entries', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 100,
        weigher: _lengthWeigher,
      );
      cache.set('key1', 'value1'); // weight 6
      cache.set('key2', 'value2'); // weight 6

      expect(cache.currentWeight, equals(12));
    });

    test('When storing an entry would exceed maxWeight, the least recently '
        'used entries are evicted', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
      );

      cache.set('key1', 'aaaaa'); // weight 5
      cache.set('key2', 'bbbbb'); // weight 5, total 10

      cache.get('key1'); // key2 becomes least recently used

      cache.set('key3', 'ccccc'); // evicts key2

      expect(cache.get('key2'), isNull);
      expect(cache.get('key1'), equals('aaaaa'));
      expect(cache.get('key3'), equals('ccccc'));
      expect(cache.currentWeight, equals(10));
    });

    test('An entry whose own weight exceeds maxWeight is not cached', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 5,
        weigher: _lengthWeigher,
      );

      cache.set('key1', 'value1'); // weight 6 > maxWeight 5

      expect(cache.get('key1'), isNull);
      expect(cache.currentWeight, equals(0));
    });

    test('An explicit weight argument overrides the weigher', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
      );

      cache.set('key1', 'value1', weight: 3);

      expect(cache.get('key1'), equals('value1'));
      expect(cache.currentWeight, equals(3));
    });

    test('Re-setting an existing key replaces its previous weight', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
      );

      cache.set('key1', 'aaaaa'); // weight 5
      cache.set('key1', 'bb'); // weight 2, replaces the previous entry

      expect(cache.get('key1'), equals('bb'));
      expect(cache.currentWeight, equals(2));
    });

    test('An oversized update is rejected as a true no-op — the existing '
        'value survives', () {
      // Regression test: an earlier prototype detached the old entry's
      // weight before checking whether the new weight fit, so a rejected
      // over-budget update destroyed the existing value as a side effect.
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
      );

      cache.set('key1', 'aaaaa'); // weight 5, fits
      cache.set('key1', 'value1', weight: 999); // 999 > maxWeight, rejected

      expect(cache.get('key1'), equals('aaaaa')); // unchanged
      expect(cache.currentWeight, equals(5));
    });

    // Unlike set(), which silently no-ops on a write that can never fit
    // (the test above), update()/getOrSet() have a non-void return
    // contract and instead throw StateError — this is Cache's own
    // documented behavior, inherited unchanged since
    // SimpleWeightedLRUCache extends it directly, but was never exercised
    // through this subclass.
    test('An oversized update() throws StateError instead of silently '
        'rejecting, and leaves the existing value untouched', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
      );

      cache.set('key1', 'aaaaa'); // weight 5, fits

      expect(
        () => cache.update('key1', (v) => 'value1', weight: 999),
        throwsStateError,
      );

      expect(cache.get('key1'), equals('aaaaa'));
      expect(cache.currentWeight, equals(5));
    });

    test(
      'An oversized getOrSet() miss throws StateError and stores nothing',
      () {
        final cache = SimpleWeightedLRUCache<String, String>(
          maxWeight: 10,
          weigher: _lengthWeigher,
        );

        expect(
          () => cache.getOrSet('key1', () => 'value1', weight: 999),
          throwsStateError,
        );

        expect(cache.containsKey('key1'), isFalse);
        expect(cache.currentWeight, equals(0));
      },
    );

    test('maxSize is enforced alongside maxWeight', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 1000,
        weigher: _lengthWeigher,
        maxSize: 2,
      );

      cache.set('key1', 'a');
      cache.set('key2', 'b');
      cache.set('key3', 'c'); // key1 evicted despite low total weight

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), equals('b'));
      expect(cache.get('key3'), equals('c'));
    });

    test('Updating the sole entry at maxSize:1 never evicts it as a side '
        'effect of its own update', () {
      // An update to an existing key must never trip maxSize purely
      // because of itself (the entry count doesn't change), regardless of
      // how much heavier the new value is.
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 1000,
        weigher: _lengthWeigher,
        maxSize: 1,
      );

      cache.set('key1', 'a');
      cache.set('key1', 'a much heavier value than before');

      expect(cache.get('key1'), equals('a much heavier value than before'));
    });
  });

  group('SimpleWeightedLRUCache - Error Handling', () {
    test('Throws ArgumentError when maxWeight is 0 or less', () {
      expect(
        () => SimpleWeightedLRUCache<String, String>(
          maxWeight: 0,
          weigher: _lengthWeigher,
        ),
        throwsArgumentError,
      );
      expect(
        () => SimpleWeightedLRUCache<String, String>(
          maxWeight: -1,
          weigher: _lengthWeigher,
        ),
        throwsArgumentError,
      );
    });

    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(
        () => SimpleWeightedLRUCache<String, String>(
          maxWeight: 10,
          weigher: _lengthWeigher,
          maxSize: 0,
        ),
        throwsArgumentError,
      );
    });

    test('Throws ArgumentError when an explicit weight is negative', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
      );

      expect(
        () => cache.set('key1', 'value1', weight: -1),
        throwsArgumentError,
      );
    });

    // A weigher is user-supplied and can throw (e.g. a bug in a
    // size-estimation function). No prior test exercised this — confirms
    // the exception propagates without leaving a partial entry behind.
    test('a throwing weigher leaves the cache untouched', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: (key, value) => throw StateError('boom'),
      );

      expect(() => cache.set('key1', 'value1'), throwsStateError);

      expect(cache.containsKey('key1'), isFalse);
      expect(cache.currentWeight, equals(0));
    });
  });
}
