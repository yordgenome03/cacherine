import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

int _lengthWeigher(String key, String value) => value.length;

void main() {
  group('Cache engine — composed weight + TTL + LRU', () {
    test('an already-expired entry is purged and its slot reclaimed before a '
        'live LRU victim is evicted', () {
      var now = DateTime(2024);
      final cache = Cache<String, String>(
        store: LRUStore<String, String>(),
        weigher: _lengthWeigher,
        maxWeight: 13,
        ttl: const Duration(seconds: 100), // long default; 'c' overrides it
        clock: () => now,
      );

      cache.set('a', 'aaaa'); // weight 4, long-lived
      cache.set('b', 'bbb'); // weight 3, long-lived
      cache.set(
        'c',
        'cc',
        ttl: const Duration(seconds: 1),
      ); // weight 2, short-lived; total weight 9

      // Advance time so only 'c' has expired; 'a'/'b' are still live.
      now = now.add(const Duration(seconds: 2));

      // Adding 'd' (weight 5) would push total to 14 > maxWeight(13) if
      // 'c' were still counted. The expired 'c' must be purged first,
      // reclaiming its weight (total becomes 7), so the live 'a'/'b'
      // should NOT need to be evicted for this write (7 + 5 = 12) to fit.
      cache.set('d', 'ddddd'); // weight 5

      expect(cache.get('c'), isNull); // purged for being expired
      expect(cache.get('a'), equals('aaaa')); // still live, not evicted
      expect(cache.get('b'), equals('bbb')); // still live, not evicted
      expect(cache.get('d'), equals('ddddd'));
      expect(cache.currentWeight, equals(4 + 3 + 5));
    });

    test('a composed weight+TTL+LRU cache can be built directly', () async {
      final cache = AsyncCache<String, String>(
        Cache(
          store: LRUStore<String, String>(),
          weigher: _lengthWeigher,
          maxWeight: 1024,
          ttl: const Duration(minutes: 10),
        ),
      );

      await cache.set('avatar:42', 'bytes-ish content');
      await cache.set(
        'avatar:99',
        'short-lived override',
        ttl: const Duration(minutes: 1),
      );

      expect(await cache.get('avatar:42'), equals('bytes-ish content'));
      expect(await cache.get('avatar:99'), equals('short-lived override'));
    });

    test('weight: is rejected on an instance without a configured weigher', () {
      final cache = Cache<String, String>(
        store: LRUStore<String, String>(),
        maxSize: 10,
      );
      expect(() => cache.set('a', 'value', weight: 5), throwsArgumentError);
    });

    test(
      'ttl: is rejected on an instance without a configured default ttl',
      () {
        final cache = Cache<String, String>(
          store: LRUStore<String, String>(),
          maxSize: 10,
        );
        expect(
          () => cache.set('a', 'value', ttl: const Duration(seconds: 1)),
          throwsArgumentError,
        );
      },
    );
  });

  group('MonitoredCache — EvictionReason attribution', () {
    test('capacity eviction is recorded as EvictionReason.capacity', () async {
      final cache = MonitoredCache<String, String>(
        store: LRUStore<String, String>(),
        maxSize: 1,
      );
      await cache.set('a', '1');
      await cache.set('b', '2'); // evicts 'a' on capacity

      final snapshot = cache.metrics.snapshot(const Duration(minutes: 1));
      expect(
        snapshot.evictionsPerMinuteByReason[EvictionReason.capacity],
        greaterThan(0),
      );
    });

    test('weight eviction is recorded as EvictionReason.weight', () async {
      final cache = MonitoredCache<String, String>(
        store: LRUStore<String, String>(),
        weigher: _lengthWeigher,
        maxWeight: 5,
      );
      await cache.set('a', 'aaaaa'); // weight 5
      await cache.set('b', 'bbbbb'); // evicts 'a' on weight

      final snapshot = cache.metrics.snapshot(const Duration(minutes: 1));
      expect(
        snapshot.evictionsPerMinuteByReason[EvictionReason.weight],
        greaterThan(0),
      );
    });

    test('expiry eviction is recorded as EvictionReason.expired', () async {
      var now = DateTime(2024);
      final cache = MonitoredCache<String, String>(
        store: LRUStore<String, String>(),
        ttl: const Duration(seconds: 1),
        clock: () => now,
      );
      await cache.set('a', '1');
      now = now.add(const Duration(seconds: 2));
      expect(await cache.get('a'), isNull); // lazily discovered and purged

      final snapshot = cache.metrics.snapshot(const Duration(minutes: 1));
      expect(
        snapshot.evictionsPerMinuteByReason[EvictionReason.expired],
        greaterThan(0),
      );
    });

    test('manual removal is recorded as EvictionReason.manual', () async {
      final cache = MonitoredCache<String, String>(
        store: LRUStore<String, String>(),
        maxSize: 10,
      );
      await cache.set('a', '1');
      await cache.remove('a');

      final snapshot = cache.metrics.snapshot(const Duration(minutes: 1));
      expect(
        snapshot.evictionsPerMinuteByReason[EvictionReason.manual],
        greaterThan(0),
      );
    });

    test('the legacy zero-argument recordEviction() still buckets as '
        'unspecified and counts toward the aggregate rate', () {
      final metrics = CacheMetrics();
      metrics.recordEviction();
      final snapshot = metrics.snapshot(const Duration(minutes: 1));
      expect(snapshot.evictionsPerMinute, equals(1));
      expect(
        snapshot.evictionsPerMinuteByReason[EvictionReason.unspecified],
        equals(1),
      );
    });
  });

  group('Cache engine — plain LFU via the composable engine', () {
    test('matches LFUCache eviction behavior', () async {
      final cache = AsyncCache<String, int>(
        Cache(store: LFUStore<String, int>(), maxSize: 2),
      );
      await cache.set('a', 1);
      await cache.set('b', 2);
      await cache.get('a'); // bump frequency of 'a'
      await cache.set('c', 3); // evicts 'b' (lower frequency)

      expect(await cache.get('b'), isNull);
      expect(await cache.get('a'), equals(1));
      expect(await cache.get('c'), equals(3));
    });
  });
}
