import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  group('MonitoredEphemeralFIFOCache Tests', () {
    final CacheAlertConfig config = CacheAlertConfig(notifyCallback: (_) {});
    test('Stored data should be retrievable and removed after get()', () async {
      final cache = MonitoredEphemeralFIFOCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );

      await cache.set('key1', 'value1');
      expect(
        await cache.get('key1'),
        equals('value1'),
      ); // Retrieved successfully
      expect(
        await cache.get('key1'),
        isNull,
      ); // Should be removed after retrieval
    });

    test(
      'FIFO eviction should remove the oldest element when maxSize is exceeded',
      () async {
        final cache = MonitoredEphemeralFIFOCache<String, String>(
          maxSize: 2,
          alertConfig: config,
        );

        await cache.set('key1', 'value1');
        await cache.set('key2', 'value2');
        await cache.set('key3', 'value3'); // 'key1' should be removed

        expect(await cache.get('key1'), isNull); // 'key1' should be evicted
        expect(await cache.get('key2'), equals('value2'));
        expect(await cache.get('key3'), equals('value3'));
      },
    );

    test(
      'Cache should maintain data integrity under concurrent access',
      () async {
        final cache = MonitoredEphemeralFIFOCache<int, int>(
          maxSize: 10,
          alertConfig: config,
        );

        final futures = List.generate(100, (i) async {
          await cache.set(i, i * 10);
          final value = await cache.get(i);
          expect(
            value,
            anyOf(isNull, equals(i * 10)),
          ); // Either retrieved or already removed
        });

        await Future.wait(futures);
      },
    );

    test('Cache hit/miss rates should be correctly recorded', () async {
      final cache = MonitoredEphemeralFIFOCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );

      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      await cache.get('key1'); // Cache hit
      await cache.get('key3'); // Cache miss
      await cache.get('key2'); // Cache hit

      final metrics = cache.metrics;
      expect(metrics.hits, equals(2));
      expect(metrics.misses, equals(1));
    });

    test('get() records a stored null as a hit and removes it', () async {
      final cache = MonitoredEphemeralFIFOCache<String, String?>(
        maxSize: 2,
        alertConfig: config,
      );

      await cache.set('key1', null);

      expect(await cache.get('key1'), isNull);
      expect(cache.metrics.hits, equals(1));
      expect(cache.metrics.misses, equals(0));
      expect(await cache.getKeys(), isNot(contains('key1')));
    });

    test('clear() should remove all cache entries', () async {
      final cache = MonitoredEphemeralFIFOCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );

      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(await cache.getKeys(), isEmpty);
    });

    test(
      'set() on an existing key when cache is full does not evict any entry',
      () async {
        final cache = MonitoredEphemeralFIFOCache<String, String>(
          maxSize: 2,
          alertConfig: config,
        );
        await cache.set('key1', 'value1');
        await cache.set('key2', 'value2');

        // Update the non-oldest key (key2). With the buggy implementation that
        // lacked the containsKey guard, key1 (oldest) would be evicted here.
        await cache.set('key2', 'new_value2');

        expect((await cache.getKeys()).length, equals(2));
        expect(await cache.get('key1'), equals('value1'));
      },
    );

    test('Should throw an exception if maxSize is 0 or negative', () {
      expect(
        () => MonitoredEphemeralFIFOCache<String, String>(
          maxSize: 0,
          alertConfig: config,
        ),
        throwsArgumentError,
      );
    });
  });

  group('MonitoredEphemeralFIFOCache - remove()', () {
    final config = CacheAlertConfig(notifyCallback: (_) {});

    test('remove() existing key records eviction in metrics', () async {
      final cache = MonitoredEphemeralFIFOCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );
      await cache.set('key1', 'value1');
      await cache.remove('key1');
      expect(await cache.get('key1'), isNull);
      final stats = cache.metrics.getRecentStats(const Duration(minutes: 1));
      expect(stats['evictions_per_minute'], equals(1));
    });

    test('remove() non-existent key does not record eviction', () async {
      final cache = MonitoredEphemeralFIFOCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );
      await cache.remove('missing');
      final stats = cache.metrics.getRecentStats(const Duration(minutes: 1));
      expect(stats['evictions_per_minute'], equals(0));
    });

    test('capacity eviction via set() records eviction in metrics', () async {
      final cache = MonitoredEphemeralFIFOCache<String, String>(
        maxSize: 2,
        alertConfig: config,
      );
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3'); // triggers FIFO eviction of key1
      final stats = cache.metrics.getRecentStats(const Duration(minutes: 1));
      expect(stats['evictions_per_minute'], equals(1));
    });

    test('dispose() implements Disposable and stops the timer', () {
      final cache = MonitoredEphemeralFIFOCache<String, String>(
        maxSize: 3,
        alertConfig: config,
      );
      expect(cache, isA<Disposable>());
      expect(cache.dispose, returnsNormally);
    });
  });

  // Regression coverage: these methods are implemented directly on this
  // class (composing an AsyncCache engine, not inheriting MonitoredCache —
  // see https://github.com/yordgenome03/cacherine/pull/69 review feedback
  // on preserving is CacheMonitoring<K, V>/is Disposable and this facade's
  // original method surface), so each needs its own direct test rather than
  // relying on MonitoredCache's own coverage.
  group('MonitoredEphemeralFIFOCache - full interface coverage', () {
    final config = CacheAlertConfig(notifyCallback: (_) {});

    test('peek()/containsKey() report presence without recording metrics '
        'or consuming the entry', () async {
      final cache = MonitoredEphemeralFIFOCache<String, String>(
        maxSize: 10,
        alertConfig: config,
      );
      await cache.set('a', '1');
      expect(await cache.peek('a'), equals('1'));
      expect(await cache.containsKey('a'), isTrue);
      expect(await cache.containsKey('missing'), isFalse);
      expect(cache.metrics.hits, equals(0));
      expect(cache.metrics.misses, equals(0));
    });

    test('setAll() stores every entry', () async {
      final cache = MonitoredEphemeralFIFOCache<String, String>(
        maxSize: 10,
        alertConfig: config,
      );
      await cache.setAll({'a': '1', 'b': '2'});
      expect(await cache.get('a'), equals('1'));
      expect(await cache.get('b'), equals('2'));
    });

    test('getOrCompute() records a hit on a present key and a miss on a '
        'computed one', () async {
      final cache = MonitoredEphemeralFIFOCache<String, String>(
        maxSize: 10,
        alertConfig: config,
      );
      await cache.set('a', '1');
      expect(await cache.getOrCompute('a', () async => 'x'), equals('1'));
      expect(cache.metrics.hits, equals(1));

      var calls = 0;
      Future<String> compute() async {
        calls++;
        return '2';
      }

      expect(await cache.getOrCompute('b', compute), equals('2'));
      expect(await cache.getOrCompute('b', compute), equals('2'));
      expect(calls, equals(1));
      expect(cache.metrics.misses, equals(1));
    });

    test('update() records a hit on an existing key and a miss via '
        'ifAbsent', () async {
      final cache = MonitoredEphemeralFIFOCache<String, int>(
        maxSize: 10,
        alertConfig: config,
      );
      await cache.set('a', 1);
      expect(await cache.update('a', (v) async => v + 1), equals(2));
      expect(cache.metrics.hits, equals(1));

      expect(
        await cache.update('b', (v) async => v, ifAbsent: () async => 9),
        equals(9),
      );
      expect(cache.metrics.misses, equals(1));
    });

    test(
      'update() throws StateError for a missing key with no ifAbsent',
      () async {
        final cache = MonitoredEphemeralFIFOCache<String, int>(
          maxSize: 10,
          alertConfig: config,
        );
        await expectLater(
          cache.update('missing', (v) async => v),
          throwsStateError,
        );
      },
    );

    test(
      'getAll() records a hit per present key, omitting missing ones',
      () async {
        final cache = MonitoredEphemeralFIFOCache<String, String>(
          maxSize: 10,
          alertConfig: config,
        );
        await cache.set('a', '1');
        await cache.set('b', '2');
        expect(
          await cache.getAll(['a', 'b', 'missing']),
          equals({'a': '1', 'b': '2'}),
        );
        expect(cache.metrics.hits, equals(2));
        expect(cache.metrics.misses, equals(0));
      },
    );

    test(
      'removeWhere() removes matching entries and records eviction',
      () async {
        final cache = MonitoredEphemeralFIFOCache<String, String>(
          maxSize: 10,
          alertConfig: config,
        );
        await cache.set('a', '1');
        await cache.set('b', '2');
        await cache.removeWhere((key, value) async => key == 'a');
        expect(await cache.getKeys(), equals(['b']));
        expect(
          cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
          equals(1),
        );
      },
    );

    test('toString() reflects current entries', () async {
      final cache = MonitoredEphemeralFIFOCache<String, String>(
        maxSize: 10,
        alertConfig: config,
      );
      await cache.set('a', '1');
      expect(cache.toString(), contains('a'));
    });
  });
}
