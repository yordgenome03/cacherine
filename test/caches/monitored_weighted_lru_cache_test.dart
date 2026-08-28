import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

int _lengthWeigher(String key, String value) => value.length;

void main() {
  group('MonitoredWeightedLRUCache Tests', () {
    final CacheAlertConfig config = CacheAlertConfig(notifyCallback: (_) {});

    test('Stored data should be retrievable', () async {
      final cache = MonitoredWeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
        alertConfig: config,
      );

      await cache.set('key1', 'value1');
      expect(await cache.get('key1'), equals('value1'));
    });

    test(
      'Weight-based eviction should remove the least recently used element '
      'when maxWeight is exceeded, and record it with EvictionReason.weight',
      () async {
        final cache = MonitoredWeightedLRUCache<String, String>(
          maxWeight: 10,
          weigher: _lengthWeigher,
          alertConfig: config,
        );

        await cache.set('key1', 'aaaaa'); // weight 5
        await cache.set('key2', 'bbbbb'); // weight 5, total 10
        await cache.get('key1'); // key2 becomes LRU
        await cache.set('key3', 'ccccc'); // evicts key2

        expect(await cache.get('key2'), isNull);
        expect(await cache.get('key1'), equals('aaaaa'));
        expect(await cache.get('key3'), equals('ccccc'));
        expect(await cache.currentWeight, equals(10));

        final snapshot = cache.metrics.snapshot(const Duration(minutes: 1));
        expect(
          snapshot.evictionsPerMinuteByReason[EvictionReason.weight],
          greaterThan(0),
        );
      },
    );

    test('maxSize is enforced alongside maxWeight', () async {
      final cache = MonitoredWeightedLRUCache<String, String>(
        maxWeight: 1000,
        weigher: _lengthWeigher,
        maxSize: 2,
        alertConfig: config,
      );

      await cache.set('key1', 'a');
      await cache.set('key2', 'b');
      await cache.set('key3', 'c');

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), equals('b'));
      expect(await cache.get('key3'), equals('c'));
    });

    test('Cache hit/miss rates should be correctly recorded', () async {
      final cache = MonitoredWeightedLRUCache<String, String>(
        maxWeight: 100,
        weigher: _lengthWeigher,
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

    test('remove() records a manual eviction, distinct from weight/capacity '
        'evictions', () async {
      final cache = MonitoredWeightedLRUCache<String, String>(
        maxWeight: 100,
        weigher: _lengthWeigher,
        alertConfig: config,
      );

      await cache.set('key1', 'value1');
      await cache.remove('key1');

      final snapshot = cache.metrics.snapshot(const Duration(minutes: 1));
      expect(
        snapshot.evictionsPerMinuteByReason[EvictionReason.manual],
        greaterThan(0),
      );
    });

    test('clear() should remove all cache entries', () async {
      final cache = MonitoredWeightedLRUCache<String, String>(
        maxWeight: 100,
        weigher: _lengthWeigher,
        alertConfig: config,
      );

      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(await cache.getKeys(), isEmpty);
      expect(await cache.currentWeight, equals(0));
    });

    test('MonitoredWeightedLRUCache implements Disposable', () {
      final cache = MonitoredWeightedLRUCache<String, String>(
        maxWeight: 10,
        weigher: _lengthWeigher,
        alertConfig: config,
      );
      expect(cache, isA<Disposable>());
      cache.dispose();
      cache.dispose(); // idempotent
    });

    test('Should throw an exception if maxWeight is 0 or negative', () {
      expect(
        () => MonitoredWeightedLRUCache<String, String>(
          maxWeight: 0,
          weigher: _lengthWeigher,
          alertConfig: config,
        ),
        throwsArgumentError,
      );
    });

    test('Should throw an exception if maxSize is 0 or negative', () {
      expect(
        () => MonitoredWeightedLRUCache<String, String>(
          maxWeight: 10,
          weigher: _lengthWeigher,
          maxSize: 0,
          alertConfig: config,
        ),
        throwsArgumentError,
      );
    });
  });
}
