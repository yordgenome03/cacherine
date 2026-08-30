import 'package:test/test.dart';
import 'package:cacherine/src/caches/simple_ephemeral_fifo_cache.dart';

void main() {
  group('SimpleEphemeralFIFOCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () {
      final cache = SimpleEphemeralFIFOCache<String, String>(3);
      expect(cache.get('key1'), isNull);
    });

    test('Data set with set() can be retrieved with get()', () {
      final cache = SimpleEphemeralFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      expect(cache.get('key1'), equals('value1'));
      expect(cache.get('key2'), equals('value2'));
    });

    test('clear() empties the cache', () {
      final cache = SimpleEphemeralFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.clear();

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('SimpleEphemeralFIFOCache - FIFO Eviction Tests', () {
    test(
      'When the cache exceeds maxSize, FIFO eviction removes the oldest item',
      () {
        final cache = SimpleEphemeralFIFOCache<String, String>(2);
        cache.set('key1', 'value1');
        cache.set('key2', 'value2');
        cache.set('key3', 'value3'); // key1 will be evicted

        expect(cache.get('key1'), isNull); // key1 should be evicted
        expect(cache.get('key2'), equals('value2'));
        expect(cache.get('key3'), equals('value3'));
      },
    );

    test(
      'If the same key is set again, it is placed at the latest position',
      () {
        final cache = SimpleEphemeralFIFOCache<String, String>(2);
        cache.set('key1', 'value1');
        cache.set('key2', 'value2');
        cache.set(
          'key1',
          'new_value1',
        ); // key1's value is updated; its FIFO position does not change

        cache.set('key3', 'value3'); // key1, being the oldest, is evicted

        expect(cache.get('key1'), isNull); // key1 should be evicted (oldest)
        expect(cache.get('key2'), equals('value2')); // key2 should remain
        expect(cache.get('key3'), equals('value3'));
      },
    );

    test('Updating an existing key at capacity does not evict any entry', () {
      final cache = SimpleEphemeralFIFOCache<String, String>(3);
      cache.set('A', 'valueA');
      cache.set('B', 'valueB');
      cache.set('C', 'valueC');

      cache.set('B', 'newValueB'); // update existing key — no eviction

      expect(cache.getKeys().length, equals(3));
      expect(cache.getKeys(), containsAll(['A', 'B', 'C']));
      expect(cache.get('B'), equals('newValueB'));
    });
  });

  group('SimpleEphemeralFIFOCache - Get and Remove on Retrieval Tests', () {
    test('get() removes the key after retrieval', () {
      final cache = SimpleEphemeralFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      final result = cache.get('key1');

      expect(result, equals('value1'));
      expect(cache.get('key1'), isNull); // key should be removed after get()
    });

    test('stored null is removed after get()', () {
      final cache = SimpleEphemeralFIFOCache<String, String?>(3);

      cache.set('key1', null);

      expect(cache.get('key1'), isNull);
      expect(cache.getKeys(), isNot(contains('key1')));
    });
  });

  group('SimpleFIFOCache - Additional Behavior Validation', () {
    test('maxSize=1 behavior (always keeps only the most recent item)', () {
      final cache = SimpleEphemeralFIFOCache<String, String>(1);
      cache.set('key1', 'value1');
      expect(cache.get('key1'), equals('value1'));

      cache.set(
        'key2',
        'value2',
      ); // 'key1' should be evicted, only 'key2' remains
      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), equals('value2'));
    });

    test('Retrieving a non-existing key returns null', () {
      final cache = SimpleEphemeralFIFOCache<String, String>(3);
      expect(cache.get('non_existing_key'), isNull);
    });

    test('getKeys() correctly returns the current keys', () {
      final cache = SimpleEphemeralFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key3', 'value3');

      expect(cache.getKeys(), containsAll(['key1', 'key2', 'key3']));

      cache.set('key4', 'value4'); // 'key1' is evicted
      expect(cache.getKeys(), containsAll(['key2', 'key3', 'key4']));
      expect(
        cache.getKeys(),
        isNot(contains('key1')),
      ); // 'key1' should be evicted
    });
  });

  group('SimpleEphemeralFIFOCache - Error Handling', () {
    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(
        () => SimpleEphemeralFIFOCache<String, String>(0),
        throwsArgumentError,
      );
      expect(
        () => SimpleEphemeralFIFOCache<String, String>(-1),
        throwsArgumentError,
      );
    });
  });

  group('SimpleEphemeralFIFOCache - remove()', () {
    test('remove() existing key makes get() return null', () {
      final cache = SimpleEphemeralFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.remove('key1');
      expect(cache.get('key1'), isNull);
      expect(cache.getKeys(), isNot(contains('key1')));
    });

    test('remove() non-existent key is a no-op', () {
      final cache = SimpleEphemeralFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.remove('missing');
      // Use getKeys() — calling get() would consume the ephemeral entry
      expect(cache.getKeys(), contains('key1'));
      expect(cache.getKeys().length, equals(1));
    });
  });

  // Regression coverage: these methods are implemented by forwarding to an
  // internal Cache engine (composition, not inheritance — see
  // https://github.com/yordgenome03/cacherine/pull/69 review feedback on
  // preserving this facade's original, narrower method surface), so each
  // needs its own direct test rather than relying on Cache's own coverage.
  group('SimpleEphemeralFIFOCache - full interface coverage', () {
    test('getAll() returns present keys, omitting missing ones', () {
      final cache = SimpleEphemeralFIFOCache<String, int>(10);
      cache.set('a', 1);
      cache.set('b', 2);
      expect(cache.getAll(['a', 'b', 'missing']), equals({'a': 1, 'b': 2}));
    });

    test('setAll() stores every entry', () {
      final cache = SimpleEphemeralFIFOCache<String, int>(10);
      cache.setAll({'a': 1, 'b': 2});
      expect(cache.get('a'), equals(1));
      expect(cache.get('b'), equals(2));
    });

    test('update() applies the function to an existing value', () {
      final cache = SimpleEphemeralFIFOCache<String, int>(10);
      cache.set('a', 1);
      expect(cache.update('a', (v) => v + 1), equals(2));
      expect(cache.get('a'), equals(2));
    });

    test('update() uses ifAbsent to seed a missing key', () {
      final cache = SimpleEphemeralFIFOCache<String, int>(10);
      expect(cache.update('a', (v) => v + 1, ifAbsent: () => 5), equals(5));
      expect(cache.get('a'), equals(5));
    });

    test('update() throws StateError for a missing key with no ifAbsent', () {
      final cache = SimpleEphemeralFIFOCache<String, int>(10);
      expect(() => cache.update('a', (v) => v + 1), throwsStateError);
    });

    test('removeWhere() removes matching entries', () {
      final cache = SimpleEphemeralFIFOCache<String, int>(10);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.removeWhere((key, value) => value == 1);
      expect(cache.getKeys(), isNot(contains('a')));
      expect(cache.getKeys(), contains('b'));
    });

    test('toString() reflects current entries', () {
      final cache = SimpleEphemeralFIFOCache<String, int>(10);
      cache.set('a', 1);
      expect(cache.toString(), contains('a'));
    });
  });
}
