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
    test('get() treats a stored null as present and refreshes recency', () {
      final cache = SimpleMRUCache<String, String?>(2);

      cache.set('key1', null);
      cache.set('key2', 'value2');
      expect(cache.get('key1'), isNull);

      cache.set('key3', 'value3');

      expect(cache.getKeys(), containsAll(['key2', 'key3']));
      expect(cache.getKeys(), isNot(contains('key1')));
    });

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

  group('SimpleMRUCache - remove()', () {
    test('remove() existing key makes get() return null', () {
      final cache = SimpleMRUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.remove('key1');
      expect(cache.get('key1'), isNull);
      expect(cache.getKeys(), isNot(contains('key1')));
    });

    test('remove() non-existent key is a no-op', () {
      final cache = SimpleMRUCache<String, String>(3);
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
  group('SimpleMRUCache - full interface coverage', () {
    test('getAll() returns present keys, omitting missing ones', () {
      final cache = SimpleMRUCache<String, int>(10);
      cache.set('a', 1);
      cache.set('b', 2);
      expect(cache.getAll(['a', 'b', 'missing']), equals({'a': 1, 'b': 2}));
    });

    test('setAll() stores every entry', () {
      final cache = SimpleMRUCache<String, int>(10);
      cache.setAll({'a': 1, 'b': 2});
      expect(cache.get('a'), equals(1));
      expect(cache.get('b'), equals(2));
    });

    test('update() applies the function to an existing value', () {
      final cache = SimpleMRUCache<String, int>(10);
      cache.set('a', 1);
      expect(cache.update('a', (v) => v + 1), equals(2));
      expect(cache.get('a'), equals(2));
    });

    test('update() uses ifAbsent to seed a missing key', () {
      final cache = SimpleMRUCache<String, int>(10);
      expect(cache.update('a', (v) => v + 1, ifAbsent: () => 5), equals(5));
      expect(cache.get('a'), equals(5));
    });

    test('update() throws StateError for a missing key with no ifAbsent', () {
      final cache = SimpleMRUCache<String, int>(10);
      expect(() => cache.update('a', (v) => v + 1), throwsStateError);
    });

    test('removeWhere() removes matching entries', () {
      final cache = SimpleMRUCache<String, int>(10);
      cache.set('a', 1);
      cache.set('b', 2);
      cache.removeWhere((key, value) => value == 1);
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), equals(2));
    });

    test('toString() reflects current entries', () {
      final cache = SimpleMRUCache<String, int>(10);
      cache.set('a', 1);
      expect(cache.toString(), contains('a'));
    });
  });
}
