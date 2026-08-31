import 'dart:async';

import 'package:test/test.dart';
import 'package:cacherine/src/caches/ephemeral_fifo_cache.dart';

// Deterministically reproduces a race that only affects this store: get()
// is destructive here (an entry is removed on read), so if getAll()/
// removeWhere() check presence and then separately read/peek — as
// ThreadSafeCache's default implementations do, each call independently
// acquiring the lock — a second caller's concurrent get() can land in the
// gap and consume the entry first. Overriding containsKey() to trigger that
// concurrent get() as a side effect reproduces the exact interleaving
// without depending on real scheduling luck.
class _RacyEphemeralFIFOCache<K, V> extends EphemeralFIFOCache<K, V> {
  _RacyEphemeralFIFOCache(super.maxSize);

  K? raceOnContainsKeyFor;

  @override
  Future<bool> containsKey(K key) async {
    final result = await super.containsKey(key);
    if (key == raceOnContainsKeyFor) {
      await get(key); // simulates a concurrent caller's destructive get()
    }
    return result;
  }
}

void main() {
  group('EphemeralFIFOCache - Basic Functionality', () {
    test('get() from an empty cache returns null', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      expect(await cache.get('key1'), isNull);
    });

    test('set() data can be retrieved with get()', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      expect(await cache.get('key1'), equals('value1'));
    });

    test('Data retrieved with get() is removed from the cache', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      expect(await cache.get('key1'), equals('value1'));
      expect(
        await cache.get('key1'),
        isNull,
      ); // It should be removed after retrieval
    });

    test('stored null is removed after get()', () async {
      final cache = EphemeralFIFOCache<String, String?>(3);

      await cache.set('key1', null);

      expect(await cache.get('key1'), isNull);
      expect(await cache.getKeys(), isNot(contains('key1')));
    });

    test('clear() empties the cache', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(await cache.getKeys(), isEmpty);
    });
  });

  group('EphemeralFIFOCache - FIFO Eviction Tests', () {
    test(
      'When the cache exceeds maxSize, FIFO eviction removes the oldest item',
      () async {
        final cache = EphemeralFIFOCache<String, String>(2);
        await cache.set('key1', 'value1');
        await cache.set('key2', 'value2');
        await cache.set('key3', 'value3'); // key1 should be evicted (FIFO)

        expect(await cache.get('key1'), isNull); // key1 should be removed
        expect(await cache.get('key2'), equals('value2'));
        expect(await cache.get('key3'), equals('value3'));
      },
    );

    test('Setting the same key with set() does not change the order', () async {
      final cache = EphemeralFIFOCache<String, String>(2);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set(
        'key1',
        'new_value1',
      ); // key1's value is updated; its FIFO position does not change

      await cache.set(
        'key3',
        'value3',
      ); // key1, being the oldest, should be evicted

      expect(
        await cache.get('key1'),
        isNull,
      ); // key1 should be removed (oldest)
      expect(await cache.get('key2'), equals('value2')); // key2 should remain
      expect(await cache.get('key3'), equals('value3'));
    });

    test(
      'Updating an existing key at capacity does not evict any entry',
      () async {
        final cache = EphemeralFIFOCache<String, String>(3);
        await cache.set('A', 'valueA');
        await cache.set('B', 'valueB');
        await cache.set('C', 'valueC');

        await cache.set('B', 'newValueB'); // update existing key — no eviction

        expect((await cache.getKeys()).length, equals(3));
        expect(await cache.getKeys(), containsAll(['A', 'B', 'C']));
        expect(await cache.get('B'), equals('newValueB'));
      },
    );
  });

  group('EphemeralFIFOCache - Thread-safety Tests', () {
    test('Parallel set() / get() operations work safely', () async {
      final cache = EphemeralFIFOCache<int, String>(5);

      // Perform 1000 parallel set & get operations
      final futures = List.generate(1000, (i) async {
        await cache.set(
          i % 5,
          'value$i',
        ); // keys 0 to 4 will be updated continuously
        return await cache.get(
          i % 5,
        ); // Check if value can be retrieved (and is deleted immediately after)
      });

      // Wait for all async operations to complete
      await Future.wait(futures);

      // Confirm that no values are left in the cache
      expect((await cache.getKeys()).isEmpty, isTrue);
    });

    test('Parallel clear() calls remove all data', () async {
      final cache = EphemeralFIFOCache<String, String>(5);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3');

      // Perform parallel clear() calls
      await Future.wait([cache.clear(), cache.clear(), cache.clear()]);

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(await cache.get('key3'), isNull);
      expect(await cache.getKeys(), isEmpty);
    });

    test(
      'Calling toString() during parallel processing does not cause errors',
      () async {
        final cache = EphemeralFIFOCache<int, String>(5);
        await cache.set(1, 'value1');
        await cache.set(2, 'value2');
        await cache.set(3, 'value3');

        // Perform parallel get() and toString() calls
        final futures = List.generate(1000, (i) async {
          await cache.get(i % 3);
          return cache.toString();
        });

        final results = await Future.wait(futures);
        expect(
          results.length,
          equals(1000),
        ); // All toString() calls should work without errors
      },
    );
  });

  group('EphemeralFIFOCache - Error Handling', () {
    test('Throws ArgumentError when maxSize is 0 or less', () {
      expect(() => EphemeralFIFOCache<String, String>(0), throwsArgumentError);
      expect(() => EphemeralFIFOCache<String, String>(-1), throwsArgumentError);
    });
  });

  group('EphemeralFIFOCache - remove()', () {
    test('remove() existing key makes subsequent get() return null', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.remove('key1');
      expect(await cache.get('key1'), isNull);
      expect(await cache.getKeys(), isNot(contains('key1')));
    });

    test('remove() non-existent key is a no-op', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.remove('missing');
      // Use getKeys() — calling get() would consume the ephemeral entry
      expect(await cache.getKeys(), contains('key1'));
      expect((await cache.getKeys()).length, equals(1));
    });

    test('remove() Future completes without error', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await expectLater(cache.remove('key1'), completes);
    });
  });

  // Regression coverage: these methods are implemented by forwarding to an
  // internal AsyncCache engine (composition, not inheritance — see
  // https://github.com/yordgenome03/cacherine/pull/69 review feedback on
  // preserving this facade's original, narrower method surface), so each
  // needs its own direct test rather than relying on AsyncCache's own
  // coverage.
  group('EphemeralFIFOCache - full interface coverage', () {
    test('getAll() returns present keys, omitting missing ones', () async {
      final cache = EphemeralFIFOCache<String, int>(10);
      await cache.set('a', 1);
      await cache.set('b', 2);
      expect(
        await cache.getAll(['a', 'b', 'missing']),
        equals({'a': 1, 'b': 2}),
      );
    });

    test('setAll() stores every entry', () async {
      final cache = EphemeralFIFOCache<String, int>(10);
      await cache.setAll({'a': 1, 'b': 2});
      expect(await cache.get('a'), equals(1));
      expect(await cache.get('b'), equals(2));
    });

    test(
      'getOrCompute() computes and stores only when the key is absent',
      () async {
        final cache = EphemeralFIFOCache<String, int>(10);
        var calls = 0;
        Future<int> compute() async {
          calls++;
          return 1;
        }

        expect(await cache.getOrCompute('a', compute), equals(1));
        expect(await cache.getOrCompute('a', compute), equals(1));
        expect(calls, equals(1));
      },
    );

    test('update() applies the function to an existing value', () async {
      final cache = EphemeralFIFOCache<String, int>(10);
      await cache.set('a', 1);
      expect(await cache.update('a', (v) async => v + 1), equals(2));
      expect(await cache.get('a'), equals(2));
    });

    test('update() uses ifAbsent to seed a missing key', () async {
      final cache = EphemeralFIFOCache<String, int>(10);
      expect(
        await cache.update('a', (v) async => v + 1, ifAbsent: () async => 5),
        equals(5),
      );
      expect(await cache.get('a'), equals(5));
    });

    test(
      'update() throws StateError for a missing key with no ifAbsent',
      () async {
        final cache = EphemeralFIFOCache<String, int>(10);
        await expectLater(
          cache.update('a', (v) async => v + 1),
          throwsStateError,
        );
      },
    );

    test('removeWhere() removes matching entries', () async {
      final cache = EphemeralFIFOCache<String, int>(10);
      await cache.set('a', 1);
      await cache.set('b', 2);
      await cache.removeWhere((key, value) async => value == 1);
      expect(await cache.getKeys(), isNot(contains('a')));
      expect(await cache.getKeys(), contains('b'));
    });

    test('toString() reflects current entries', () async {
      final cache = EphemeralFIFOCache<String, int>(10);
      await cache.set('a', 1);
      expect(cache.toString(), contains('a'));
    });
  });

  group(
    'EphemeralFIFOCache - getAll()/removeWhere() destructive-read race',
    () {
      test('getAll() is not exposed to a concurrent get() landing between a '
          'presence check and the read — the read must be atomic, with no '
          'separate presence-check step for a race to land in', () async {
        final cache = _RacyEphemeralFIFOCache<String, int>(10)
          ..raceOnContainsKeyFor = 'x';
        await cache.set('x', 1);
        await cache.set('y', 2);

        final result = await cache.getAll(['x', 'y']);

        // If getAll() is implemented as an atomic per-key read (no exposed
        // containsKey() step), this subclass's containsKey() override never
        // fires during getAll(), so nothing races 'x' away — both keys come
        // back, each consumed by getAll()'s own read.
        expect(result, equals({'x': 1, 'y': 2}));
        expect(await cache.get('x'), isNull); // consumed by getAll() itself
        expect(await cache.get('y'), isNull);
      });

      test('removeWhere() does not throw when a key is consumed by a '
          'concurrent get() between the presence check and the peek', () async {
        final cache = _RacyEphemeralFIFOCache<String, int>(10)
          ..raceOnContainsKeyFor = 'x';
        await cache.set('x', 1);
        await cache.set('y', 2);

        await expectLater(
          cache.removeWhere((key, value) async => false),
          completes,
        );
        expect(await cache.get('y'), equals(2)); // untouched by the race
      });
    },
  );
}
