import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  DateTime fakeNow = DateTime(2024);
  DateTime fakeClock() => fakeNow;

  setUp(() {
    fakeNow = DateTime(2024);
  });

  group('SimpleTTLCacheInterface', () {
    test('SimpleTTLCache implements the public TTL interface', () {
      final cache = SimpleTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      expect(cache, isA<SimpleCache<String, String>>());
      expect(cache, isA<SimpleTTLCacheInterface<String, String>>());
    });

    test('allows per-entry TTL overrides through the interface', () {
      final SimpleTTLCacheInterface<String, String> cache =
          SimpleTTLCache<String, String>(
            ttl: const Duration(seconds: 30),
            clock: fakeClock,
          );

      cache.set('default', 'live');
      cache.set('short', 'expired', ttl: const Duration(seconds: 5));

      fakeNow = fakeNow.add(const Duration(seconds: 10));

      expect(cache.get('default'), equals('live'));
      expect(cache.get('short'), isNull);
      expect(cache.containsKey('default'), isTrue);
      expect(cache.containsKey('short'), isFalse);
    });

    test('validates per-entry TTL overrides through the interface', () {
      final SimpleTTLCacheInterface<String, String> cache =
          SimpleTTLCache<String, String>(
            ttl: const Duration(seconds: 30),
            clock: fakeClock,
          );

      expect(
        () => cache.set('key', 'value', ttl: Duration.zero),
        throwsArgumentError,
      );
    });
  });

  group('ThreadSafeTTLCacheInterface', () {
    test('TTLCache implements the public TTL interface', () {
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
      );

      expect(cache, isA<ThreadSafeCache<String, String>>());
      expect(cache, isA<ThreadSafeTTLCacheInterface<String, String>>());
    });

    test('MonitoredTTLCache implements the public TTL interface', () {
      final cache = MonitoredTTLCache<String, String>(
        ttl: const Duration(seconds: 10),
        clock: fakeClock,
        alertConfig: CacheAlertConfig(notifyCallback: (_) {}),
      );
      addTearDown(cache.dispose);

      expect(cache, isA<ThreadSafeCache<String, String>>());
      expect(cache, isA<ThreadSafeTTLCacheInterface<String, String>>());
    });

    test('allows per-entry TTL overrides through TTLCache interface', () async {
      final ThreadSafeTTLCacheInterface<String, String> cache =
          TTLCache<String, String>(
            ttl: const Duration(seconds: 30),
            clock: fakeClock,
          );

      await cache.set('default', 'live');
      await cache.set('short', 'expired', ttl: const Duration(seconds: 5));

      fakeNow = fakeNow.add(const Duration(seconds: 10));

      expect(await cache.get('default'), equals('live'));
      expect(await cache.get('short'), isNull);
      expect(await cache.containsKey('default'), isTrue);
      expect(await cache.containsKey('short'), isFalse);
    });

    test(
      'allows per-entry TTL overrides through MonitoredTTLCache interface',
      () async {
        final cache = MonitoredTTLCache<String, String>(
          ttl: const Duration(seconds: 30),
          clock: fakeClock,
          alertConfig: CacheAlertConfig(notifyCallback: (_) {}),
        );
        addTearDown(cache.dispose);

        final ThreadSafeTTLCacheInterface<String, String> ttlCache = cache;

        await ttlCache.set('default', 'live');
        await ttlCache.set('short', 'expired', ttl: const Duration(seconds: 5));

        fakeNow = fakeNow.add(const Duration(seconds: 10));

        expect(await ttlCache.get('default'), equals('live'));
        expect(await ttlCache.get('short'), isNull);
        expect(cache.metrics.hits, equals(1));
        expect(cache.metrics.misses, equals(1));
      },
    );

    test('validates per-entry TTL overrides through the interface', () async {
      final ThreadSafeTTLCacheInterface<String, String> cache =
          TTLCache<String, String>(
            ttl: const Duration(seconds: 30),
            clock: fakeClock,
          );

      await expectLater(
        () => cache.set('key', 'value', ttl: Duration.zero),
        throwsArgumentError,
      );
    });
  });
}
