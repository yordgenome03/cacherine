import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  group('getKeys() order contract', () {
    test(
      'FIFO caches return insertion order and updates keep position',
      () async {
        final cache = FIFOCache<String, String>(3);

        await cache.set('a', 'A');
        await cache.set('b', 'B');
        await cache.set('a', 'updated');
        await cache.set('c', 'C');

        expect(await cache.getKeys(), equals(['a', 'b', 'c']));
      },
    );

    test('Ephemeral FIFO returns remaining keys in insertion order', () async {
      final cache = EphemeralFIFOCache<String, String>(3);

      await cache.set('a', 'A');
      await cache.set('b', 'B');
      await cache.set('c', 'C');
      await cache.get('b');

      expect(await cache.getKeys(), equals(['a', 'c']));
    });

    test('LRU getKeys returns least to most recently used', () async {
      final cache = LRUCache<String, String>(3);

      await cache.set('a', 'A');
      await cache.set('b', 'B');
      await cache.set('c', 'C');
      await cache.get('a');

      expect(await cache.getKeys(), equals(['b', 'c', 'a']));
    });

    test('MRU getKeys returns least to most recently used', () async {
      final cache = MRUCache<String, String>(3);

      await cache.set('a', 'A');
      await cache.set('b', 'B');
      await cache.set('c', 'C');
      await cache.get('a');

      expect(await cache.getKeys(), equals(['b', 'c', 'a']));
    });

    // Unlike every other policy above, LFU's getKeys() order is explicitly
    // documented as unspecified (doc/lfu_cache.md: "the order is unspecified.
    // Do not use it to infer frequency, recency, or eviction order."). This
    // doesn't test a specific order — it closes the gap of LFU being the only
    // policy absent from this file, by pinning down what IS guaranteed: the
    // correct *set* of live keys, regardless of the access pattern that
    // produced them.
    test('LFU getKeys returns exactly the live keys, in whatever order — order '
        'itself is unspecified and must not be relied on', () async {
      final cache = LFUCache<String, String>(3);

      await cache.set('a', 'A');
      await cache.set('b', 'B');
      await cache.set('c', 'C');
      await cache.get('a'); // bump frequency; must not change key *set*

      expect(await cache.getKeys(), unorderedEquals(['a', 'b', 'c']));
    });

    test('TTL getKeys returns live keys in insertion order', () async {
      var now = DateTime(2024);
      final cache = TTLCache<String, String>(
        ttl: const Duration(seconds: 30),
        clock: () => now,
      );

      await cache.set('expired', 'old', ttl: const Duration(seconds: 5));
      await cache.set('a', 'A');
      await cache.set('b', 'B');
      now = now.add(const Duration(seconds: 10));

      expect(await cache.getKeys(), equals(['a', 'b']));
    });
  });
}
