import 'dart:async';

import 'package:cacherine/src/caches/ttl_cache.dart';
import 'package:test/test.dart';

void main() {
  // A simple fake clock: start at a fixed instant and allow manual advancement.
  DateTime fakeNow = DateTime(2024, 1, 1);
  DateTime fakeClock() => fakeNow;

  setUp(() {
    fakeNow = DateTime(2024, 1, 1);
  });

  group('TTLCache - Constructor validation', () {
    test('throws ArgumentError for zero ttl', () {
      expect(
        () => TTLCache<String, String>(ttl: Duration.zero),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative ttl', () {
      expect(
        () => TTLCache<String, String>(ttl: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for zero maxSize', () {
      expect(
        () => TTLCache<String, String>(
          ttl: const Duration(seconds: 10),
          maxSize: 0,
        ),
        throwsArgumentError,
      );
    });

    test(
      'set() throws ArgumentError for zero per-entry ttl override',
      () async {
        final cache = TTLCache<String, String>(
          ttl: const Duration(seconds: 10),
          clock: fakeClock,
        );
        await expectLater(
          () => cache.set('key', 'value', ttl: Duration.zero),
          throwsArgumentError,
        );
      },
    );

    test(
      'set() throws ArgumentError for negative per-entry ttl override',
      () async {
        final cache = TTLCache<String, String>(
          ttl: const Duration(seconds: 10),
          clock: fakeClock,
        );
        await expectLater(
          () => cache.set('key', 'value', ttl: const Duration(seconds: -1)),
          throwsArgumentError,
        );
      },
    );
  });

  group('TTLCache - Global TTL', () {
    test('entry expires after global TTL elapses', () async {
      // 3.1 / 3.11
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      await cache.set('key', 'value');
      fakeNow = fakeNow.add(const Duration(seconds: 11));

      expect(await cache.get('key'), isNull);
    });

    test('entry is accessible before TTL elapses', () async {
      // 3.2
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      await cache.set('key', 'value');
      fakeNow = fakeNow.add(const Duration(seconds: 9));

      expect(await cache.get('key'), equals('value'));
    });
  });

  group('TTLCache - Per-entry TTL (set with ttl:)', () {
    test('per-entry TTL shorter than global TTL', () async {
      // 3.3
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 20),
        clock: fakeClock,
      );

      await cache.set('long', 'value-long');
      await cache.set('short', 'value-short', ttl: const Duration(seconds: 5));

      fakeNow = fakeNow.add(const Duration(seconds: 10));

      expect(await cache.get('short'), isNull);
      expect(await cache.get('long'), equals('value-long'));
    });

    test('per-entry TTL longer than global TTL', () async {
      // 3.4
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 5),
        clock: fakeClock,
      );

      await cache.set('long', 'value-long', ttl: const Duration(seconds: 20));
      fakeNow = fakeNow.add(const Duration(seconds: 10));

      expect(await cache.get('long'), equals('value-long'));
    });
  });

  group('TTLCache - getKeys()', () {
    test('getKeys() excludes expired keys', () async {
      // 3.5
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      await cache.set('a', '1');
      await cache.set('b', '2');

      fakeNow = fakeNow.add(const Duration(seconds: 5));
      await cache.set('c', '3'); // fresh entry

      fakeNow = fakeNow.add(const Duration(seconds: 6)); // a and b now expired

      final keys = await cache.getKeys();
      expect(keys, contains('c'));
      expect(keys, isNot(contains('a')));
      expect(keys, isNot(contains('b')));
    });
  });

  group('TTLCache - remove() and clear()', () {
    test('remove() deletes a specific entry', () async {
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      await cache.set('a', '1');
      await cache.set('b', '2');
      await cache.remove('a');

      expect(await cache.get('a'), isNull);
      expect(await cache.get('b'), equals('2'));
    });

    test('remove() is a no-op for absent key', () async {
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      await expectLater(() => cache.remove('missing'), returnsNormally);
    });

    test('clear() removes all entries', () async {
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      await cache.set('a', '1');
      await cache.set('b', '2');
      await cache.clear();

      expect(await cache.get('a'), isNull);
      expect(await cache.get('b'), isNull);
      expect(await cache.getKeys(), isEmpty);
    });
  });

  group('TTLCache - Lazy eviction', () {
    test('expired entry is removed on get()', () async {
      // 3.6
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      await cache.set('key', 'value');
      fakeNow = fakeNow.add(const Duration(seconds: 11));

      expect(await cache.get('key'), isNull);
      // Internal removal: after get(), the key should not be in getKeys either.
      expect(await cache.getKeys(), isNot(contains('key')));
    });
  });

  group('TTLCache - maxSize FIFO eviction', () {
    test(
      'maxSize evicts oldest FIFO entry when capacity is exceeded',
      () async {
        // 3.7
        final cache = TTLCache<String, String>(
          ttl: const Duration(seconds: 60),
          maxSize: 2,
          clock: fakeClock,
        );

        await cache.set('a', '1');
        await cache.set('b', '2');
        await cache.set('c', '3'); // should evict 'a'

        expect(await cache.get('a'), isNull);
        expect(await cache.get('b'), equals('2'));
        expect(await cache.get('c'), equals('3'));
      },
    );

    test('expired entries do not count toward maxSize', () async {
      // 3.8
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 5),
        maxSize: 2,
        clock: fakeClock,
      );

      await cache.set('a', '1');
      await cache.set('b', '2');

      // Expire both entries
      fakeNow = fakeNow.add(const Duration(seconds: 10));

      // Now add a new entry — expired entries don't count so no eviction of live data
      await cache.set('c', '3');
      await cache.set('d', '4');

      expect(await cache.get('c'), equals('3'));
      expect(await cache.get('d'), equals('4'));
    });
  });

  group('TTLCache - dispose()', () {
    test('dispose() cancels sweep timer so no further sweeps occur', () async {
      // 3.9
      // We verify that after dispose(), internal state is not modified by further
      // sweeps. We do this by injecting a completer-based clock and confirming
      // that the timer does not fire after cancel.
      final swept = <int>[];
      var sweepCount = 0;

      final cache = TTLCache<String, String>(
        ttl: const Duration(milliseconds: 50),
        sweepInterval: const Duration(milliseconds: 50),
        clock: () {
          sweepCount++;
          swept.add(sweepCount);
          return DateTime.now();
        },
      );

      // Let at least one sweep fire.
      await Future.delayed(const Duration(milliseconds: 120));
      cache.dispose();
      final countAfterDispose = swept.length;

      // Wait again — no new sweeps should have fired.
      await Future.delayed(const Duration(milliseconds: 120));
      expect(swept.length, equals(countAfterDispose));
    });

    test('dispose() is idempotent', () async {
      // 3.10
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        sweepInterval: const Duration(seconds: 60),
        clock: fakeClock,
      );

      expect(() {
        cache.dispose();
        cache.dispose();
      }, returnsNormally);
    });
  });

  group('TTLCache - fake clock controls expiry', () {
    test('fake clock advances time without real sleep', () async {
      // 3.11
      final cache = TTLCache<String, String>(
        ttl: const Duration(hours: 1),
        clock: fakeClock,
      );

      await cache.set('key', 'value');
      expect(await cache.get('key'), equals('value'));

      fakeNow = fakeNow.add(const Duration(hours: 2));
      expect(await cache.get('key'), isNull);
    });
  });
}
