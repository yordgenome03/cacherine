import 'dart:async';
import 'dart:math';

import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

/// Every existing concurrency test in this suite races a hand-picked pair of
/// calls via `Completer`s to pin down one exact interleaving. That's the
/// right tool for proving a *specific* ordering is safe, but it can't catch
/// a bug that only shows up under a much wider fan-out — e.g. a dedup path
/// that happens to work for two racing callers but not for the twentieth.
/// These tests instead fire a large, unstructured batch of calls via
/// `Future.wait` and assert on the aggregate outcome (a count, a bound, a
/// "still usable afterward"), trading exact interleaving control for scale.
///
/// A hung `Future.wait` would otherwise just run until the test runner's own
/// timeout with a generic message, so every wait below carries an explicit
/// `.timeout(...)` with a message naming what would have deadlocked.
const _timeout = Duration(seconds: 5);

void main() {
  group('Concurrency stress tests', () {
    group('getOrCompute() single-flight guarantee under heavy fan-out', () {
      final targets = <String, ThreadSafeCache<String, int> Function()>{
        'LRUCache': () => LRUCache<String, int>(10),
        'MRUCache': () => MRUCache<String, int>(10),
        'FIFOCache': () => FIFOCache<String, int>(10),
        'LFUCache': () => LFUCache<String, int>(10),
        'AsyncCache': () =>
            AsyncCache<String, int>(Cache(store: LRUStore<String, int>())),
        'MonitoredCache': () =>
            MonitoredCache<String, int>(store: LRUStore<String, int>()),
      };

      for (final entry in targets.entries) {
        test('${entry.key}: 100 concurrent getOrCompute() calls on the same '
            'missing key all receive the identical computed value, and the '
            'factory runs exactly once', () async {
          final cache = entry.value();
          const callerCount = 100;
          var factoryCalls = 0;

          final results =
              await Future.wait(
                List.generate(
                  callerCount,
                  (_) => cache.getOrCompute('k', () async {
                    factoryCalls++;
                    await Future.delayed(
                      Duration.zero,
                    ); // encourage interleaving
                    return 42;
                  }),
                ),
              ).timeout(
                _timeout,
                onTimeout: () => fail(
                  '${entry.key}: $callerCount concurrent getOrCompute() calls '
                  'on the same key never completed',
                ),
              );

          expect(factoryCalls, equals(1));
          expect(results, everyElement(equals(42)));
        });
      }

      // EphemeralFIFOCache is deliberately excluded from the sweep above: its
      // getOrCompute() dispatches a hit through this class's own get(), which
      // — per the class's core "retrieved data cannot be reused" contract —
      // *consumes* the entry. So a hit for caller N is a fresh miss for
      // caller N+1, and single-flight dedup cannot hold across more than one
      // subsequent caller. Confirmed empirically before encoding it here
      // (with an even caller count, the pattern is exactly miss-hit-miss-hit,
      // so exactly half the calls recompute and the cache ends up empty —
      // the last call's hit consumes the final entry).
      test('EphemeralFIFOCache: 20 concurrent getOrCompute() calls on the same '
          'missing key do NOT collapse into one computation, since every hit '
          'consumes the entry it reads', () async {
        final cache = EphemeralFIFOCache<String, int>(10);
        const callerCount = 20;
        var factoryCalls = 0;

        final results =
            await Future.wait(
              List.generate(
                callerCount,
                (_) => cache.getOrCompute('k', () async {
                  factoryCalls++;
                  await Future.delayed(Duration.zero);
                  return 42;
                }),
              ),
            ).timeout(
              _timeout,
              onTimeout: () => fail(
                '$callerCount concurrent getOrCompute() calls on the same key '
                'never completed',
              ),
            );

        expect(results, everyElement(equals(42)));
        expect(factoryCalls, equals(callerCount ~/ 2));
        expect(
          await cache.getKeys(),
          isEmpty,
          reason: 'the last caller\'s hit consumes the final entry',
        );
      });
    });

    test(
      'hundreds of concurrent mixed operations against a capacity-bounded '
      'cache never exceed maxSize and leave the cache in a usable state',
      () async {
        const maxSize = 5;
        final cache = LRUCache<String, int>(maxSize);
        final keyPool = List.generate(10, (i) => 'k$i');
        final random = Random(7);

        final operations = List.generate(500, (i) {
          final key = keyPool[random.nextInt(keyPool.length)];
          switch (random.nextInt(5)) {
            case 0:
              return () => cache.set(key, i);
            case 1:
              return () => cache.get(key);
            case 2:
              return () => cache.remove(key);
            case 3:
              return () => cache.getOrCompute(key, () async => i);
            default:
              return () => cache.update(
                key,
                (v) async => v + 1,
                ifAbsent: () async => i,
              );
          }
        });

        await Future.wait(operations.map((op) => op())).timeout(
          _timeout,
          onTimeout: () => fail(
            'the mixed-op stress run '
            'against a capacity-bounded LRUCache never completed',
          ),
        );

        final finalKeys = await cache.getKeys();
        expect(finalKeys.length, lessThanOrEqualTo(maxSize));

        // Confirm the cache is still fully usable afterward — a leaked,
        // never-released lock would hang this instead of failing an
        // assertion.
        await cache
            .set('sentinel', 999)
            .timeout(
              _timeout,
              onTimeout: () =>
                  fail('cache is unusable (lock leaked?) after the stress run'),
            );
        expect(await cache.get('sentinel'), equals(999));
      },
    );

    test('concurrent getAll()/removeWhere() batch calls mixed with regular '
        'traffic on a MonitoredCache never deadlock and settle at a '
        'consistent count', () async {
      const maxSize = 5;
      final cache = MonitoredCache<String, int>(
        store: LRUStore<String, int>(),
        maxSize: maxSize,
      );
      final keyPool = List.generate(8, (i) => 'k$i');
      for (final key in keyPool) {
        await cache.set(key, 0);
      }

      final random = Random(11);
      final operations = List.generate(200, (i) {
        switch (random.nextInt(4)) {
          case 0:
            return () => cache.set(keyPool[random.nextInt(keyPool.length)], i);
          case 1:
            return () => cache.getAll(keyPool);
          case 2:
            return () => cache.removeWhere((key, value) => value.isOdd);
          default:
            return () => cache.get(keyPool[random.nextInt(keyPool.length)]);
        }
      });

      await Future.wait(operations.map((op) => op())).timeout(
        _timeout,
        onTimeout: () => fail(
          'concurrent set()/getAll()/removeWhere()/get() traffic on a '
          'MonitoredCache never completed — the batch-lock fix earlier in '
          'this release is exactly the kind of change that could '
          'reintroduce a deadlock here',
        ),
      );

      expect(await cache.size, lessThanOrEqualTo(maxSize));
    });

    test('hundreds of concurrent mixed operations against a weight-bounded '
        'WeightedLRUCache never exceed maxWeight and leave the cache in a '
        'usable state', () async {
      const maxWeight = 50;
      final cache = WeightedLRUCache<String, int>(
        weigher: (key, value) => value,
        maxWeight: maxWeight,
      );
      final keyPool = List.generate(10, (i) => 'k$i');
      final random = Random(13);

      final operations = List.generate(500, (i) {
        final key = keyPool[random.nextInt(keyPool.length)];
        // Weights stay well under maxWeight individually (1-9), so no
        // single write is ever unconditionally rejected — only capacity
        // pressure from the aggregate should ever trigger eviction.
        final weight = 1 + random.nextInt(9);
        switch (random.nextInt(4)) {
          case 0:
            return () => cache.set(key, weight);
          case 1:
            return () => cache.get(key);
          case 2:
            return () => cache.remove(key);
          default:
            return () => cache.getOrCompute(key, () async => weight);
        }
      });

      await Future.wait(operations.map((op) => op())).timeout(
        _timeout,
        onTimeout: () => fail(
          'the mixed-op stress run against a weight-bounded '
          'WeightedLRUCache never completed',
        ),
      );

      expect(await cache.currentWeight, lessThanOrEqualTo(maxWeight));

      // Confirm the cache is still fully usable afterward — a leaked,
      // never-released lock would hang this instead of failing an
      // assertion.
      await cache
          .set('sentinel', 1)
          .timeout(
            _timeout,
            onTimeout: () =>
                fail('cache is unusable (lock leaked?) after the stress run'),
          );
      expect(await cache.get('sentinel'), equals(1));
    });

    test('concurrent get()/set() traffic on a MonitoredTTLCache never '
        'deadlocks with its own background sweep timer', () async {
      final cache = MonitoredTTLCache<String, int>(
        ttl: const Duration(milliseconds: 20),
        sweepInterval: const Duration(milliseconds: 5),
      );
      final keyPool = List.generate(8, (i) => 'k$i');
      final random = Random(17);

      final operations = List.generate(300, (i) {
        final key = keyPool[random.nextInt(keyPool.length)];
        switch (random.nextInt(3)) {
          case 0:
            return () => cache.set(key, i);
          case 1:
            return () => cache.get(key);
          default:
            return () => cache.getOrCompute(key, () async => i);
        }
      });

      await Future.wait(operations.map((op) => op())).timeout(
        _timeout,
        onTimeout: () => fail(
          'concurrent traffic on a MonitoredTTLCache racing its own sweep '
          'timer never completed — a sweep firing mid-operation could '
          'deadlock on the shared instance lock',
        ),
      );

      cache.dispose();

      // Confirm the cache is still fully usable afterward.
      await cache
          .set('sentinel', 999)
          .timeout(
            _timeout,
            onTimeout: () =>
                fail('cache is unusable (lock leaked?) after the stress run'),
          );
      expect(await cache.get('sentinel'), equals(999));
    });

    test('MonitoredLRUCache: hit/miss/total-request counts stay exactly '
        'consistent under heavy concurrent get() traffic', () async {
      final cache = MonitoredLRUCache<String, int>(maxSize: 20);
      // Half the key pool exists (guaranteed hits), half doesn't
      // (guaranteed misses), so both counters are exercised under load.
      for (var i = 0; i < 10; i++) {
        await cache.set('k$i', i);
      }

      const callerCount = 300;
      await Future.wait(
        List.generate(callerCount, (i) => cache.get('k${i % 20}')),
      ).timeout(
        _timeout,
        onTimeout: () => fail(
          '$callerCount concurrent get() calls on a MonitoredLRUCache '
          'never completed',
        ),
      );

      expect(
        cache.metrics.hits + cache.metrics.misses,
        equals(cache.metrics.totalRequests),
        reason:
            'a lost or double-counted increment under concurrent '
            'scheduling would desync these',
      );
      expect(cache.metrics.totalRequests, equals(callerCount));
    });
  });
}
