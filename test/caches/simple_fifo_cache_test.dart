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
    test('stored null remains present without changing FIFO order', () {
      final cache = SimpleFIFOCache<String, String?>(2);

      cache.set('key1', null);
      cache.set('key2', 'value2');

      expect(cache.get('key1'), isNull);
      expect(cache.getKeys(), contains('key1'));

      cache.set('key3', 'value3');

      expect(cache.getKeys(), containsAll(['key2', 'key3']));
      expect(cache.getKeys(), isNot(contains('key1')));
    });

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
      },
    );

    test(
      'When the same key is set again, it is placed at the most recent position',
      () {
        final cache = SimpleFIFOCache<String, String>(2);
        cache.set('key1', 'value1');
        cache.set('key2', 'value2');
        cache.set(
          'key1',
          'new_value1',
        ); // key1's value is updated; its FIFO position does not change

        cache.set(
          'key3',
          'value3',
        ); // key1, being the oldest, should be evicted

        expect(cache.get('key1'), isNull); // key1 should be evicted (oldest)
        expect(cache.get('key2'), equals('value2')); // key2 should remain
        expect(cache.get('key3'), equals('value3'));
      },
    );

    test('Updating an existing key at capacity does not evict any entry', () {
      final cache = SimpleFIFOCache<String, String>(3);
      cache.set('A', 'valueA');
      cache.set('B', 'valueB');
      cache.set('C', 'valueC');

      cache.set('B', 'newValueB'); // update existing key — no eviction

      expect(cache.getKeys().length, equals(3));
      expect(cache.getKeys(), containsAll(['A', 'B', 'C']));
      expect(cache.get('B'), equals('newValueB'));
    });
  });

  group('SimpleFIFOCache - Additional Behavior Validation', () {
    test(
      'Behavior with maxSize=1 (always keeps only the most recent item)',
      () {
        final cache = SimpleFIFOCache<String, String>(1);
        cache.set('key1', 'value1');
        expect(cache.get('key1'), equals('value1'));

        cache.set(
          'key2',
          'value2',
        ); // 'key1' should be evicted, only 'key2' remains
        expect(cache.get('key1'), isNull);
        expect(cache.get('key2'), equals('value2'));
      },
    );

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
        cache.getKeys(),
        isNot(contains('key1')),
      ); // 'key1' should be evicted
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

  group('SimpleFIFOCache - remove()', () {
    test('remove() existing key makes get() return null', () {
      final cache = SimpleFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.remove('key1');
      expect(cache.get('key1'), isNull);
      expect(cache.getKeys(), isNot(contains('key1')));
    });

    test('remove() non-existent key is a no-op', () {
      final cache = SimpleFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.remove('missing');
      expect(cache.get('key1'), equals('value1'));
      expect(cache.getKeys().length, equals(1));
    });
  });

  // Regression coverage: these methods are implemented by forwarding to an
  // internal Cache engine (composition, not inheritance — see
  // https://github.com/yordgenome03/cacherine/pull/69 review feedback on
  // preserving this facade's original, narrower method surface), so each
  // needs its own direct test rather than relying on Cache's own coverage.
  group('SimpleFIFOCache - full interface coverage', () {
    test('getAll() returns present keys, omitting missing ones', () {
      final cache = SimpleFIFOCache<String, int>(10);
      cache.set('a', 1);
      cache.set('b', 2);
      expect(cache.getAll(['a', 'b', 'missing']), equals({'a': 1, 'b': 2}));
    });

    test('setAll() stores every entry', () {
      final cache = SimpleFIFOCache<String, int>(10);
      cache.setAll({'a': 1, 'b': 2});
      expect(cache.get('a'), equals(1));
      expect(cache.get('b'), equals(2));
    });

    test('update() applies the function to an existing value', () {
      final cache = SimpleFIFOCache<String, int>(10);
      cache.set('a', 1);
      expect(cache.update('a', (v) => v + 1), equals(2));
      expect(cache.get('a'), equals(2));
    });

    test('update() uses ifAbsent to seed a missing key', () {
      final cache = SimpleFIFOCache<String, int>(10);
      expect(cache.update('a', (v) => v + 1, ifAbsent: () => 5), equals(5));
      expect(cache.get('a'), equals(5));
    });

    test('update() throws StateError for a missing key with no ifAbsent', () {
      final cache = SimpleFIFOCache<String, int>(10);
      expect(() => cache.update('a', (v) => v + 1), throwsStateError);
    });

    test('removeWhere() removes matching entries', () {
      final cache = SimpleFIFOCache<String, int>(10);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.removeWhere((key, value) => value == 1);
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), equals(2));
    });

    test('toString() reflects current entries', () {
      final cache = SimpleFIFOCache<String, int>(10);
      cache.set('a', 1);
      expect(cache.toString(), contains('a'));
    });
  });
}
