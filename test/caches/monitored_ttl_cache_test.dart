import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  DateTime fakeNow = DateTime(2024, 1, 1);
  DateTime fakeClock() => fakeNow;

  setUp(() {
    fakeNow = DateTime(2024, 1, 1);
  });

  group('MonitoredTTLCache - constructor validation', () {
    final config = CacheAlertConfig(notifyCallback: (_) {});

    test('throws ArgumentError for zero ttl', () {
      expect(
        () => MonitoredTTLCache<String, String>(
          ttl: Duration.zero,
          alertConfig: config,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative ttl', () {
      expect(
        () => MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: -1),
          alertConfig: config,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for zero maxSize', () {
      expect(
        () => MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: 10),
          maxSize: 0,
          alertConfig: config,
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for zero sweepInterval', () {
      expect(
        () => MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: 10),
          sweepInterval: Duration.zero,
          alertConfig: config,
        ),
        throwsArgumentError,
      );
    });

    test(
      'set() throws ArgumentError for zero per-entry ttl override',
      () async {
        final cache = MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: 10),
          clock: fakeClock,
          alertConfig: config,
        );
        addTearDown(cache.dispose);

        await expectLater(
          () => cache.set('key', 'value', ttl: Duration.zero),
          throwsArgumentError,
        );
      },
    );
  });

  group('MonitoredTTLCache - TTL behavior', () {
    final config = CacheAlertConfig(notifyCallback: (_) {});

    test('stored value is returned before expiry and records a hit', () async {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.set('key', 'value');
      fakeNow = fakeNow.add(const Duration(seconds: 9));

      expect(await cache.get('key'), equals('value'));
      expect(cache.metrics.hits, equals(1));
      expect(cache.metrics.misses, equals(0));
    });

    test(
      'expired entry is removed on get and records a miss and eviction',
      () async {
        final cache = MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: 10),
          clock: fakeClock,
          alertConfig: config,
        );
        addTearDown(cache.dispose);

        await cache.set('key', 'value');
        fakeNow = fakeNow.add(const Duration(seconds: 11));

        expect(await cache.get('key'), isNull);
        expect(await cache.getKeys(), isNot(contains('key')));
        expect(cache.metrics.hits, equals(0));
        expect(cache.metrics.misses, equals(1));
        expect(
          cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
          equals(1),
        );
      },
    );

    test(
      'stored null remains present until expiry and records a hit',
      () async {
        final cache = MonitoredTTLCache<String, String?>(
          ttl: const Duration(seconds: 10),
          clock: fakeClock,
          alertConfig: config,
        );
        addTearDown(cache.dispose);

        await cache.set('key', null);

        expect(await cache.get('key'), isNull);
        expect(await cache.getKeys(), contains('key'));
        expect(cache.metrics.hits, equals(1));
        expect(cache.metrics.misses, equals(0));
      },
    );

    test('per-entry ttl overrides global ttl', () async {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 5),
        clock: fakeClock,
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.set('long', 'value', ttl: const Duration(seconds: 20));
      fakeNow = fakeNow.add(const Duration(seconds: 10));

      expect(await cache.get('long'), equals('value'));
    });
  });

  group('MonitoredTTLCache - eviction metrics', () {
    final config = CacheAlertConfig(notifyCallback: (_) {});

    test(
      'capacity eviction removes oldest live entry and records eviction',
      () async {
        final cache = MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: 60),
          maxSize: 2,
          clock: fakeClock,
          alertConfig: config,
        );
        addTearDown(cache.dispose);

        await cache.set('a', '1');
        await cache.set('b', '2');
        await cache.set('c', '3');

        expect(await cache.get('a'), isNull);
        expect(await cache.get('b'), equals('2'));
        expect(await cache.get('c'), equals('3'));
        expect(
          cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
          equals(1),
        );
      },
    );

    test(
      'expired entries removed during capacity check record evictions',
      () async {
        final cache = MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: 5),
          maxSize: 2,
          clock: fakeClock,
          alertConfig: config,
        );
        addTearDown(cache.dispose);

        await cache.set('a', '1');
        await cache.set('b', '2');
        fakeNow = fakeNow.add(const Duration(seconds: 10));
        await cache.set('c', '3');

        expect(await cache.getKeys(), equals(['c']));
        expect(
          cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
          equals(2),
        );
      },
    );

    test('remove existing key records eviction', () async {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.set('key', 'value');
      await cache.remove('key');

      expect(await cache.get('key'), isNull);
      expect(
        cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
        equals(1),
      );
    });

    test('remove missing key does not record eviction', () async {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.remove('missing');

      expect(
        cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
        equals(0),
      );
    });
  });

  group('MonitoredTTLCache - lifecycle', () {
    final config = CacheAlertConfig(notifyCallback: (_) {});

    test('clear removes entries without resetting metrics', () async {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.set('key', 'value');
      await cache.get('key');
      await cache.clear();

      expect(await cache.getKeys(), isEmpty);
      expect(cache.metrics.hits, equals(1));
    });

    test('dispose implements Disposable and is idempotent', () {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        sweepInterval: const Duration(seconds: 60),
        clock: fakeClock,
        alertConfig: config,
      );

      expect(cache, isA<Disposable>());
      expect(() {
        cache.dispose();
        cache.dispose();
      }, returnsNormally);
    });
  });
}
