import 'package:test/test.dart';
import 'package:cacherine/src/caches/lfu_cache.dart';

void main() {
  group('LFUCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () async {
      final cache = LFUCache<String, String>(3);
      expect(await cache.get('key1'), isNull);
    });

    test('Data set with set() can be retrieved with get()', () async {
      final cache = LFUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.get('key2'), equals('value2'));
    });

    test('clear() empties the cache', () async {
      final cache = LFUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(await cache.getKeys(), isEmpty);
    });
  });

  group('LFUCache - LFU Eviction Tests', () {
    test(
      'When the cache exceeds maxSize, LFU eviction removes the least frequently used item',
      () async {
        final cache = LFUCache<String, String>(2);

        // Adding key1 and key2
        await cache.set('key1', 'value1');
        await cache.set('key2', 'value2');

        // Increasing the usage count for key1
        await cache.get('key1');

        // Adding key3 and exceeding maxSize
        await cache.set(
          'key3',
          'value3',
        ); // key2 will be evicted (lower usage count)

        expect(await cache.get('key2'), isNull); // key2 should be evicted
        expect(
          await cache.get('key1'),
          equals('value1'),
        ); // key1 remains as it has higher usage
        expect(
          await cache.get('key3'),
          equals('value3'),
        ); // key3 is newly added and should remain
      },
    );

    test(
      'set() on an existing key when cache is full does not evict any entry',
      () async {
        final cache = LFUCache<String, String>(2);
        await cache.set('key1', 'value1');
        await cache.set('key2', 'value2');

        await cache.set('key1', 'new_value1');

        expect(await cache.get('key1'), equals('new_value1'));
        expect(await cache.get('key2'), equals('value2'));
        expect((await cache.getKeys()).length, equals(2));
      },
    );

    test('set() on an existing key preserves its usage count', () async {
      final cache = LFUCache<String, String>(2);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      // Boost key1's usage count
      await cache.get('key1');
      await cache.get('key1');

      // Update key1 — count must be preserved, not reset to 1
      await cache.set('key1', 'updated');

      // Inserting key3 forces eviction; key2 (count 1) must go, not key1 (count 3)
      await cache.set('key3', 'value3');

      expect(await cache.get('key2'), isNull);
      expect(await cache.get('key1'), equals('updated'));
      expect(await cache.get('key3'), equals('value3'));
    });
  });

  group('LFUCache - Thread-safety Tests', () {
    test('Parallel set() / get() operations work safely', () async {
      final cache = LFUCache<int, String>(5);

      // Performing 1000 parallel set & get operations
      final futures = List.generate(1000, (i) async {
        await cache.set(
          i % 5,
          'value$i',
        ); // values for keys 0 to 4 will be continuously updated
        return await cache.get(i % 5); // Check if value can be retrieved
      });

      await Future.wait(futures);
      expect(
        (await cache.getKeys()).length,
        lessThanOrEqualTo(5),
      ); // Only 5 keys should remain
    });

    test('Parallel clear() completely clears the cache', () async {
      final cache = LFUCache<String, String>(5);
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

  group('LFUCache - Error Handling', () {
    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(() => LFUCache<String, String>(0), throwsArgumentError);
      expect(() => LFUCache<String, String>(-1), throwsArgumentError);
    });
  });

  group('LFUCache - remove()', () {
    test('remove() existing key makes subsequent get() return null', () async {
      final cache = LFUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.remove('key1');
      expect(await cache.get('key1'), isNull);
      expect(await cache.getKeys(), isNot(contains('key1')));
    });

    test('remove() non-existent key is a no-op', () async {
      final cache = LFUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.remove('missing');
      expect(await cache.get('key1'), equals('value1'));
      expect((await cache.getKeys()).length, equals(1));
    });

    test('remove() Future completes without error', () async {
      final cache = LFUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await expectLater(cache.remove('key1'), completes);
    });
  });
}
