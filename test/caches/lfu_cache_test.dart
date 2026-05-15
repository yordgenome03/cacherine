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

    test(
      'set() on an existing key preserves its usage count (not reset to 1)',
      () async {
        final cache = LFUCache<String, String>(2);
        await cache.set('key1', 'value1');
        await cache.set('key2', 'value2');

        // Give key2 count=2 so a reset-to-1 on key1 would make key1 the LFU
        await cache.get('key2');

        // Boost key1's count to 5
        await cache.get('key1');
        await cache.get('key1');
        await cache.get('key1');
        await cache.get('key1');

        // Update key1 via set — count must be preserved at 5, not reset to 1.
        // If reset to 1, key1 (count 1) < key2 (count 2) → key1 would be
        // evicted instead of key2, and the assertions below would fail.
        await cache.set('key1', 'updated');

        // Inserting key3 forces eviction; key2 (count 2) must go, not key1
        await cache.set('key3', 'value3');

        expect(await cache.get('key2'), isNull);
        expect(await cache.get('key1'), equals('updated'));
        expect(await cache.get('key3'), equals('value3'));
      },
    );

    test('set() on an existing key does not inflate its usage count', () async {
      // Regression: repeated set() calls must not increment the usage count.
      // If they did, the count could exceed that of a key boosted via get(),
      // causing the wrong key to be evicted.
      final cache = LFUCache<String, String>(2);
      await cache.set('keyA', 'valueA');
      await cache.set('keyB', 'valueB');

      // Boost keyA's count to 4 via three get() calls (1 initial + 3 gets)
      await cache.get('keyA');
      await cache.get('keyA');
      await cache.get('keyA');

      // Update keyB four times via set(); count must remain 1
      await cache.set('keyB', 'update1');
      await cache.set('keyB', 'update2');
      await cache.set('keyB', 'update3');
      await cache.set('keyB', 'update4');

      // Insert keyC — eviction must remove keyB (count 1), not keyA (count 4)
      await cache.set('keyC', 'valueC');

      expect(await cache.get('keyB'), isNull);
      expect(await cache.get('keyA'), equals('valueA'));
      expect(await cache.get('keyC'), equals('valueC'));
    });

    test(
      'set() on existing key refreshes LRU position — eviction uses LRU tiebreak',
      () async {
        // key1 inserted first, key2 inserted second. Both at freq=1 with key1 oldest.
        // set(key1) refreshes key1's recency → key2 becomes the oldest in bucket[1].
        // Eviction must then remove key2 (LRU tiebreak: oldest is evicted first).
        final cache = LFUCache<String, String>(2);
        await cache.set('key1', 'value1'); // bucket[1]: [key1]
        await cache.set(
          'key2',
          'value2',
        ); // bucket[1]: [key2, key1] (key1 is tail)
        await cache.set(
          'key1',
          'updated',
        ); // refreshes recency → [key1, key2] (key2 is tail)
        await cache.set('key3', 'value3'); // evicts tail of bucket[1] → key2
        expect(await cache.get('key2'), isNull);
        expect(await cache.get('key1'), equals('updated'));
        expect(await cache.get('key3'), equals('value3'));
      },
    );
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

  group('LFUCache - toString()', () {
    test('toString() returns key-value pairs as a string', () async {
      final cache = LFUCache<String, String>(3);
      await cache.set('a', '1');
      await cache.set('b', '2');
      final result = cache.toString();
      expect(result, contains('a'));
      expect(result, contains('1'));
      expect(result, contains('b'));
      expect(result, contains('2'));
    });
  });

  group('LFUCache - remove()', () {
    test(
      'remove() empties minFreq bucket while other items remain — next set() evicts correctly',
      () async {
        final cache = LFUCache<String, String>(2);
        await cache.set('key1', 'value1'); // freq=1
        await cache.set('key2', 'value2'); // freq=1
        await cache.get('key2'); // key2 freq=2, _minFreq still 1
        // Remove key1: freq=1 bucket becomes empty. _minFreq may be stale
        // but set() resets _minFreq=1 on next new-key insertion.
        await cache.remove('key1');
        expect(await cache.get('key1'), isNull);
        expect(await cache.get('key2'), equals('value2'));
        // Insert two new keys — cache is size 2, so key3 gets evicted by key4.
        await cache.set('key3', 'value3'); // _minFreq reset to 1
        await cache.set('key4', 'value4'); // evicts key3 (freq=1, key2 freq≥2)
        expect(await cache.get('key3'), isNull);
        expect(await cache.get('key2'), equals('value2'));
        expect(await cache.get('key4'), equals('value4'));
      },
    );

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
