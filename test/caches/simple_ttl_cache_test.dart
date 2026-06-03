import 'package:cacherine/src/caches/simple_ttl_cache.dart';
import 'package:test/test.dart';

void main() {
  DateTime fakeNow = DateTime(2024);
  DateTime fakeClock() => fakeNow;

  setUp(() {
    fakeNow = DateTime(2024);
  });

  group('SimpleTTLCache - Constructor validation', () {
    test('throws ArgumentError for zero ttl', () {
      expect(
        () => SimpleTTLCache<String, String>(ttl: Duration.zero),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative ttl', () {
      expect(
        () => SimpleTTLCache<String, String>(ttl: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for zero maxSize', () {
      expect(
        () => SimpleTTLCache<String, String>(
          ttl: const Duration(seconds: 10),
          maxSize: 0,
        ),
        throwsArgumentError,
      );
    });

    test('set() throws ArgumentError for invalid per-entry ttl', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      expect(
        () => cache.set('key', 'value', ttl: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => cache.set('key', 'value', ttl: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });
  });

  group('SimpleTTLCache - Expiry', () {
    test('entry is accessible before TTL elapses', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      cache.set('key', 'value');
      fakeNow = fakeNow.add(const Duration(seconds: 9));

      expect(cache.get('key'), equals('value'));
    });

    test('entry expires after global TTL elapses', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      cache.set('key', 'value');
      fakeNow = fakeNow.add(const Duration(seconds: 11));

      expect(cache.get('key'), isNull);
      expect(cache.getKeys(), isNot(contains('key')));
    });

    test('per-entry TTL can be shorter than global TTL', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 20),
        clock: fakeClock,
      );

      cache.set('long', 'value-long');
      cache.set('short', 'value-short', ttl: const Duration(seconds: 5));

      fakeNow = fakeNow.add(const Duration(seconds: 10));

      expect(cache.get('short'), isNull);
      expect(cache.get('long'), equals('value-long'));
    });

    test('per-entry TTL can be longer than global TTL', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 5),
        clock: fakeClock,
      );

      cache.set('long', 'value-long', ttl: const Duration(seconds: 20));
      fakeNow = fakeNow.add(const Duration(seconds: 10));

      expect(cache.get('long'), equals('value-long'));
    });
  });

  group('SimpleTTLCache - containsKey()', () {
    test('distinguishes stored null from missing key until expiry', () {
      final cache = SimpleTTLCache<String, String?>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      cache.set('key', null);

      expect(cache.get('key'), isNull);
      expect(cache.containsKey('key'), isTrue);

      fakeNow = fakeNow.add(const Duration(seconds: 11));

      expect(cache.containsKey('key'), isFalse);
      expect(cache.getKeys(), isNot(contains('key')));
    });
  });

  group('SimpleTTLCache - getKeys()', () {
    test('getKeys() excludes expired keys', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      cache.set('a', '1');
      cache.set('b', '2');

      fakeNow = fakeNow.add(const Duration(seconds: 5));
      cache.set('c', '3');

      fakeNow = fakeNow.add(const Duration(seconds: 6));

      expect(cache.getKeys(), contains('c'));
      expect(cache.getKeys(), isNot(contains('a')));
      expect(cache.getKeys(), isNot(contains('b')));
    });
  });

  group('SimpleTTLCache - maxSize FIFO eviction', () {
    test('maxSize evicts oldest FIFO entry when capacity is exceeded', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 60),
        maxSize: 2,
        clock: fakeClock,
      );

      cache.set('a', '1');
      cache.set('b', '2');
      cache.set('c', '3');

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), equals('2'));
      expect(cache.get('c'), equals('3'));
    });

    test('expired entries do not count toward maxSize', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 5),
        maxSize: 2,
        clock: fakeClock,
      );

      cache.set('a', '1');
      cache.set('b', '2');

      fakeNow = fakeNow.add(const Duration(seconds: 10));

      cache.set('c', '3');
      cache.set('d', '4');

      expect(cache.get('c'), equals('3'));
      expect(cache.get('d'), equals('4'));
    });

    test('updating an existing key refreshes FIFO order', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 60),
        maxSize: 2,
        clock: fakeClock,
      );

      cache.set('a', '1');
      cache.set('b', '2');
      cache.set('a', 'updated');
      cache.set('c', '3');

      expect(cache.get('a'), equals('updated'));
      expect(cache.get('b'), isNull);
      expect(cache.get('c'), equals('3'));
    });
  });

  group('SimpleTTLCache - remove(), clear(), and toString()', () {
    test('remove() deletes a specific entry', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      cache.set('a', '1');
      cache.set('b', '2');
      cache.remove('a');

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), equals('2'));
    });

    test('clear() removes all entries', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      cache.set('a', '1');
      cache.set('b', '2');
      cache.clear();

      expect(cache.getKeys(), isEmpty);
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), isNull);
    });

    test('toString() excludes expired entries', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      cache.set('a', '1');
      fakeNow = fakeNow.add(const Duration(seconds: 11));

      expect(cache.toString(), isNot(contains('a: 1')));
    });

    test('toString() includes live entries', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      cache.set('a', '1');

      expect(cache.toString(), contains('a: 1'));
    });
  });
}
