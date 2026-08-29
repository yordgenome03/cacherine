import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

class _ClockCounter {
  int calls = 0;
  DateTime call() {
    calls++;
    return DateTime(2024).add(Duration(microseconds: calls));
  }
}

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

    test('toString returns live entries and omits expired entries', () async {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.set('expired', 'old', ttl: const Duration(seconds: 5));
      await cache.set('live', 'new');
      fakeNow = fakeNow.add(const Duration(seconds: 6));

      final cacheString = cache.toString();

      expect(cacheString, contains('live'));
      expect(cacheString, contains('new'));
      expect(cacheString, isNot(contains('expired')));
      expect(cacheString, isNot(contains('old')));
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

    test('purgeExpired records one eviction per removed entry', () async {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.set('expired-a', '1', ttl: const Duration(seconds: 5));
      await cache.set('expired-b', '2', ttl: const Duration(seconds: 5));
      await cache.set('live', '3');

      fakeNow = fakeNow.add(const Duration(seconds: 6));

      expect(await cache.purgeExpired(), equals(2));
      expect(await cache.getKeys(), equals(['live']));
      expect(
        cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
        equals(2),
      );
    });
  });

  group('MonitoredTTLCache - lifecycle', () {
    final config = CacheAlertConfig(notifyCallback: (_) {});

    test(
      'background sweep removes expired entries and records evictions',
      () async {
        final cache = MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: 10),
          sweepInterval: const Duration(milliseconds: 5),
          clock: fakeClock,
          alertConfig: config,
        );
        addTearDown(cache.dispose);

        await cache.set('key', 'value');
        fakeNow = fakeNow.add(const Duration(seconds: 11));

        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(await cache.getKeys(), isEmpty);
        expect(
          cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
          equals(1),
        );
      },
    );

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

    test('is a CacheMonitoring<K, V>, same as every other Monitored*Cache '
        '(regression: an earlier version delegated to CacheMonitoring instead '
        'of mixing it in directly, losing this type relationship)', () {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
        alertConfig: config,
      );
      expect(cache, isA<CacheMonitoring<String, String>>());
      cache.dispose();
    });
  });

  group('MonitoredTTLCache - check-then-fetch atomicity', () {
    final config = CacheAlertConfig(notifyCallback: (_) {});

    // Regression coverage: update()/getAll()/removeWhere() used to be
    // inherited from ThreadSafeTTLCacheInterface/ThreadSafeCache defaults,
    // which check presence via containsKey() and then separately fetch via
    // get()/peek() — each call independently reacquires the composed
    // AsyncCache's lock and reads the clock. These are now overridden to take
    // a single atomic presentValue()/presentPeek() snapshot per key, reading
    // the clock (and lock) once per key.
    test('update() reads the clock exactly twice on a hit', () async {
      final counter = _ClockCounter();
      final cache = MonitoredTTLCache<String, int>(
        ttl: const Duration(seconds: 100),
        clock: counter.call,
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.set('a', 1);
      final before = counter.calls;
      expect(await cache.update('a', (v) async => v + 1), equals(2));
      expect(counter.calls - before, equals(2));
    });

    test('getAll() reads the clock once per key on a hit', () async {
      final counter = _ClockCounter();
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 100),
        clock: counter.call,
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.set('a', '1');
      await cache.set('b', '2');
      final before = counter.calls;
      expect(await cache.getAll(['a', 'b']), equals({'a': '1', 'b': '2'}));
      expect(counter.calls - before, equals(2));
    });

    test('removeWhere() reads the clock once per key', () async {
      final counter = _ClockCounter();
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 100),
        clock: counter.call,
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.set('a', '1');
      await cache.set('b', '2');
      final before = counter.calls;
      await cache.removeWhere((key, value) async => false);
      // 1 read for getKeys() + 1 per key for presentPeek().
      expect(counter.calls - before, equals(3));
    });

    // Regression coverage for https://github.com/yordgenome03/cacherine/pull/69
    // review feedback: getAll()/removeWhere() were bypassing this facade's
    // monitored get()/remove(), silently dropping the hit/latency and
    // manual-eviction metrics doc/monitored_cache.md:123-127 promises.
    test('getAll() records a hit per present key, matching repeated get() '
        'calls', () async {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 100),
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.set('a', '1');
      await cache.set('b', '2');
      expect(
        await cache.getAll(['a', 'b', 'missing']),
        equals({'a': '1', 'b': '2'}),
      );

      expect(cache.metrics.hits, equals(2));
      expect(cache.metrics.misses, equals(0)); // 'missing' is omitted, not a
      // recorded miss, per doc/monitored_cache.md.
    });

    test('removeWhere() records manual evictions via remove()', () async {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 100),
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.set('a', '1');
      await cache.set('b', '2');
      await cache.removeWhere((key, value) async => key == 'a');

      expect(await cache.getKeys(), equals(['b']));
      expect(
        cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
        equals(1),
      );
    });

    // Regression coverage: the pre-existing (pre-composable-engine) default
    // update() called get() internally, so on a MonitoredTTLCache it recorded
    // hit/miss metrics via virtual dispatch, matching
    // doc/monitored_cache.md:122-123 ("update() follow[s] getOrCompute()
    // hit/miss semantics"). The atomic presentValue()-based rewrite that
    // fixed update()'s TTL check-then-fetch race delegated straight to the
    // (unmonitored) engine instead, silently dropping those metrics.
    test('update() records a hit on an existing key and a miss via '
        'ifAbsent', () async {
      final cache = MonitoredTTLCache<String, int>(
        ttl: const Duration(seconds: 100),
        alertConfig: config,
      );
      addTearDown(cache.dispose);

      await cache.set('a', 1);
      expect(await cache.update('a', (v) async => v + 1), equals(2));
      expect(cache.metrics.hits, equals(1));
      expect(cache.metrics.misses, equals(0));

      expect(
        await cache.update('b', (v) async => v, ifAbsent: () async => 9),
        equals(9),
      );
      expect(cache.metrics.hits, equals(1));
      expect(cache.metrics.misses, equals(1));
    });
  });
}
