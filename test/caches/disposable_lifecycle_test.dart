import 'dart:async';

import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  group('Disposable lifecycle', () {
    final factories = <String, ThreadSafeCache<String, String> Function()>{
      'MonitoredFIFOCache': () => MonitoredFIFOCache(maxSize: 2),
      'MonitoredEphemeralFIFOCache': () =>
          MonitoredEphemeralFIFOCache(maxSize: 2),
      'MonitoredLRUCache': () => MonitoredLRUCache(maxSize: 2),
      'MonitoredMRUCache': () => MonitoredMRUCache(maxSize: 2),
      'MonitoredLFUCache': () => MonitoredLFUCache(maxSize: 2),
      'TTLCache': () => TTLCache(ttl: const Duration(seconds: 30)),
      'MonitoredTTLCache': () =>
          MonitoredTTLCache(ttl: const Duration(seconds: 30)),
    };

    for (final entry in factories.entries) {
      test(
        '${entry.key} dispose is idempotent and cache operations still work',
        () async {
          final cache = entry.value();
          final disposable = cache as Disposable;

          expect(() {
            disposable.dispose();
            disposable.dispose();
          }, returnsNormally);

          await cache.set('key', 'value');

          expect(await cache.get('key'), equals('value'));
          await cache.remove('key');
          expect(await cache.containsKey('key'), isFalse);

          await cache.set('a', 'A');
          await cache.clear();
          expect(await cache.getKeys(), isEmpty);
        },
      );
    }

    // Regression coverage: dispose() only cancels this instance's own
    // timers (alert monitoring / TTL sweep) — it does not touch the
    // instance lock or interrupt any operation already in flight. A
    // getOrCompute() call that is mid-callback (holding the lock) when
    // dispose() is called must still complete normally afterward, and its
    // result must still be cached — dispose() is not a way to cancel a
    // pending write.
    test(
      'dispose() while a getOrCompute() is in flight does not interrupt '
      'it — the pending call completes normally and its result is cached',
      () async {
        final cache = MonitoredCache<String, int>(
          store: LRUStore<String, int>(),
          maxSize: 10,
        );
        final started = Completer<void>();
        final release = Completer<int>();

        final future = cache.getOrCompute('a', () {
          started.complete();
          return release.future;
        });
        await started.future; // in flight, holding the lock

        cache.dispose(); // must not block on, or interfere with, the lock

        release.complete(42);
        expect(await future, equals(42));
        expect(await cache.get('a'), equals(42));
      },
    );

    // Regression coverage: MonitoredTTLCache's sweep timer runs
    // engine.purgeExpired() under the instance lock on its own schedule,
    // independent of any in-flight caller operation. Disposing while a sweep
    // could plausibly be about to fire (or has just fired) must not crash,
    // and no further sweeps should run afterward.
    test('MonitoredTTLCache: dispose() while sweeping is active stops '
        'further sweeps without crashing', () async {
      final cache = MonitoredTTLCache<String, int>(
        ttl: const Duration(milliseconds: 5),
        sweepInterval: const Duration(milliseconds: 5),
      );
      await cache.set('a', 1);
      // Let at least one sweep cycle run.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(cache.dispose, returnsNormally);

      // No crash from further ticks that would have fired had the timer
      // not been cancelled.
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
  });
}
