import 'dart:async';

import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

int _lengthWeigher(String key, String value) => value.length;

// Regression coverage: async_cache.dart's Lock(reentrant: true) exists so a
// caller already holding the lock (e.g. mid-getOrCompute()/update()) can
// re-enter it by calling back into this instance's own overridable set().
// Every existing reentrancy test only has a set() override call
// super.set() — this exercises a set() override that instead calls back
// into a *different* public method (clear()) mid-write, to confirm that
// doesn't deadlock (the lock is reentrant) or leave the cache in a
// surprising state (the reentrant clear() and the eventual write are still
// fully serialized with everything else on this instance, so the outcome is
// exactly what sequential execution implies: clear(), then the write).
class _ClearOnSetAsyncCache<K, V> extends AsyncCache<K, V> {
  _ClearOnSetAsyncCache(super.engine);

  @override
  Future<void> set(K key, V value, {int? weight, Duration? ttl}) async {
    await clear();
    await super.set(key, value, weight: weight, ttl: ttl);
  }
}

class _ClockCounter {
  int calls = 0;
  DateTime call() {
    calls++;
    return DateTime(2024).add(Duration(microseconds: calls));
  }
}

/// Wraps a [CacheStore], counting accesses to [keys] — used to detect
/// whether [Cache] scanned the whole store for expired entries.
class _KeysAccessCountingStore<K, V> implements CacheStore<K, V> {
  _KeysAccessCountingStore(this._inner);
  final CacheStore<K, V> _inner;
  int keysAccessCount = 0;

  @override
  Iterable<K> get keys {
    keysAccessCount++;
    return _inner.keys;
  }

  @override
  int get length => _inner.length;
  @override
  bool get removesOnAccess => _inner.removesOnAccess;
  @override
  bool containsKey(K key) => _inner.containsKey(key);
  @override
  V? peek(K key) => _inner.peek(key);
  @override
  V? access(K key) => _inner.access(key);
  @override
  void put(K key, V value) => _inner.put(key, value);
  @override
  K? selectVictim({K? excluding}) => _inner.selectVictim(excluding: excluding);
  @override
  (K, V)? evictOne({K? excluding}) => _inner.evictOne(excluding: excluding);
  @override
  bool remove(K key) => _inner.remove(key);
  @override
  void clear() => _inner.clear();
}

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

    test('weigher and maxWeight must be provided together', () {
      expect(
        () => Cache<String, String>(
          store: LRUStore<String, String>(),
          weigher: _lengthWeigher,
        ),
        throwsArgumentError,
      );
      expect(
        () => Cache<String, String>(
          store: LRUStore<String, String>(),
          maxWeight: 10,
        ),
        throwsArgumentError,
      );
    });

    test('a non-empty store is rejected', () {
      final prePopulated = LRUStore<String, String>()..put('a', '1');
      expect(
        () => Cache<String, String>(store: prePopulated, maxSize: 10),
        throwsArgumentError,
      );
    });

    test('a capacity-triggered write does not scan the whole store for '
        'expired entries when nothing has actually expired yet', () {
      var now = DateTime(2024);
      final countingStore = _KeysAccessCountingStore(
        TTLFifoStore<String, String>(),
      );
      final cache = Cache<String, String>(
        store: countingStore,
        maxSize: 2,
        ttl: const Duration(seconds: 100),
        clock: () => now,
      );

      cache.set('a', '1');
      cache.set('b', '2');
      final scansBefore = countingStore.keysAccessCount;
      cache.set('c', '3'); // evicts 'a' on capacity; nothing has expired
      expect(countingStore.keysAccessCount, equals(scansBefore));

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), equals('2'));
      expect(cache.get('c'), equals('3'));
    });

    test('a capacity-triggered write does scan for expired entries once the '
        'earliest deadline has passed', () {
      var now = DateTime(2024);
      final countingStore = _KeysAccessCountingStore(
        TTLFifoStore<String, String>(),
      );
      final cache = Cache<String, String>(
        store: countingStore,
        maxSize: 2,
        ttl: const Duration(seconds: 5),
        clock: () => now,
      );

      cache.set('a', '1');
      cache.set('b', '2');
      now = now.add(const Duration(seconds: 10)); // both now expired
      final scansBefore = countingStore.keysAccessCount;
      cache.set('c', '3');
      expect(countingStore.keysAccessCount, greaterThan(scansBefore));

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), isNull);
      expect(cache.get('c'), equals('3'));

      // Regression coverage: _purgeExpired() recomputes _minExpiry from the
      // survivors so later writes keep getting the O(1) short-circuit. Only
      // 'c' survived the scan above (deadline now+5s); a further
      // capacity-triggered write before that deadline, with nothing newly
      // expired, must go back to skipping the scan — not fall back to
      // scanning on every write forever because _minExpiry was left stale.
      cache.set('d', '4'); // count 2, still under maxSize; no eviction yet
      final scansAfterPurge = countingStore.keysAccessCount;
      cache.set('e', '5'); // count 3 > maxSize; evicts 'c' on capacity
      expect(countingStore.keysAccessCount, equals(scansAfterPurge));

      expect(cache.get('c'), isNull);
      expect(cache.get('d'), equals('4'));
      expect(cache.get('e'), equals('5'));
    });
  });

  group('Cache — injected clock robustness', () {
    // Regression coverage: _minExpiry is a lower bound derived from whatever
    // `now` was in effect when each entry was written, and the short-circuit
    // in _write() only scans for expired entries once `now` reaches it. If
    // an injected clock (test-only; DateTime.now() doesn't do this in
    // practice) ever reports a timestamp earlier than a prior call, entries
    // simply haven't reached their deadline *yet* by that clock's own
    // reckoning — this is not corruption, just TTL correctly deferring to
    // whatever the clock says "now" is. This test pins down that the cache
    // survives such a jump without corrupting state, and self-heals — once
    // the clock advances forward past the true deadlines again, purging
    // resumes normally on the next capacity-triggered write, exactly as if
    // the backward jump had never happened.
    test('a temporarily backward-jumping clock does not corrupt the cache — '
        'purging resumes normally once the clock catches back up', () {
      var now = DateTime(2024, 1, 1, 0, 2, 0); // t = 120s
      final countingStore = _KeysAccessCountingStore(
        TTLFifoStore<String, String>(),
      );
      final cache = Cache<String, String>(
        store: countingStore,
        maxSize: 2,
        ttl: const Duration(seconds: 5),
        clock: () => now,
      );

      cache.set('a', '1'); // deadline t=125s; _minExpiry=125s
      now = DateTime(2024, 1, 1, 0, 1, 0); // clock jumps backward to t=60s
      cache.set('b', '2'); // count 2, still under maxSize; deadline t=65s

      // Capacity-triggered write while the (backward-jumped) clock still
      // reads before either deadline: nothing has "expired" by this clock's
      // own reckoning, so the scan is correctly skipped, and eviction falls
      // back to the store's own policy (FIFO here) instead.
      final scansBefore = countingStore.keysAccessCount;
      cache.set('c', '3'); // count 3 > maxSize; evicts 'a' (FIFO-oldest)
      expect(countingStore.keysAccessCount, equals(scansBefore));
      expect(cache.get('a'), isNull); // evicted by policy, not by expiry
      expect(cache.get('b'), equals('2'));
      expect(cache.get('c'), equals('3'));

      // Now advance the clock forward past every deadline recorded so far.
      now = DateTime(2024, 1, 1, 0, 5, 0); // t = 300s
      final scansAfterCatchUp = countingStore.keysAccessCount;
      cache.set('d', '4'); // count 3 > maxSize; must purge, not just evict
      expect(countingStore.keysAccessCount, greaterThan(scansAfterCatchUp));
      expect(cache.get('b'), isNull); // purged for being expired
      expect(cache.get('c'), isNull); // purged for being expired
      expect(cache.get('d'), equals('4'));
    });
  });

  group('Weight-rejected writes are reported, not silently lied about', () {
    // Regression coverage for https://github.com/yordgenome03/cacherine/pull/69
    // review feedback: _write() silently no-ops when a value's weight
    // exceeds maxWeight (documented, intentional behavior for set()), but
    // getOrSet()/getOrCompute()/update() have a non-void return contract —
    // they used to return the oversized value anyway, claiming it was
    // cached when it never was (and, on a hit, the old value silently
    // remained). They now throw StateError instead, and leave any existing
    // entry untouched.
    test('Cache.getOrSet() throws instead of reporting an uncached value', () {
      final cache = Cache<String, String>(
        store: LRUStore<String, String>(),
        weigher: _lengthWeigher,
        maxWeight: 5,
      );
      expect(() => cache.getOrSet('a', () => 'toolong'), throwsStateError);
      expect(cache.get('a'), isNull); // never actually cached
    });

    test('Cache.update() throws instead of reporting an uncached value, '
        'leaving the old value in place', () {
      final cache = Cache<String, String>(
        store: LRUStore<String, String>(),
        weigher: _lengthWeigher,
        maxWeight: 5,
      );
      cache.set('a', 'ok'); // weight 2, fits
      expect(() => cache.update('a', (v) => 'toolong'), throwsStateError);
      expect(cache.get('a'), equals('ok')); // untouched by the rejected update
    });

    test('AsyncCache.getOrCompute()/update() throw instead of reporting an '
        'uncached value', () async {
      final cache = AsyncCache<String, String>(
        Cache(
          store: LRUStore<String, String>(),
          weigher: _lengthWeigher,
          maxWeight: 5,
        ),
      );
      await expectLater(
        cache.getOrCompute('a', () async => 'toolong'),
        throwsStateError,
      );
      expect(await cache.get('a'), isNull);

      await cache.set('b', 'ok');
      await expectLater(
        cache.update('b', (v) async => 'toolong'),
        throwsStateError,
      );
      expect(await cache.get('b'), equals('ok'));
    });

    test('MonitoredCache.getOrCompute()/update() throw instead of reporting an '
        'uncached value', () async {
      final cache = MonitoredCache<String, String>(
        store: LRUStore<String, String>(),
        weigher: _lengthWeigher,
        maxWeight: 5,
      );
      await expectLater(
        cache.getOrCompute('a', () async => 'toolong'),
        throwsStateError,
      );
      expect(await cache.get('a'), isNull);

      await cache.set('b', 'ok');
      await expectLater(
        cache.update('b', (v) async => 'toolong'),
        throwsStateError,
      );
      expect(await cache.get('b'), equals('ok'));
    });
  });

  group('Cache — cache-aside and update helpers', () {
    test('putIfAbsent() computes and stores only when the key is absent', () {
      final cache = Cache<String, int>(
        store: LRUStore<String, int>(),
        maxSize: 10,
      );
      var calls = 0;
      int compute() {
        calls++;
        return 1;
      }

      expect(cache.putIfAbsent('a', compute), equals(1));
      expect(cache.putIfAbsent('a', compute), equals(1));
      expect(calls, equals(1)); // second call found 'a' already present
    });

    test('update() applies the function to an existing value', () {
      final cache = Cache<String, int>(
        store: LRUStore<String, int>(),
        maxSize: 10,
      );
      cache.set('a', 1);
      final result = cache.update('a', (value) => value + 1);
      expect(result, equals(2));
      expect(cache.get('a'), equals(2));
    });

    test('update() uses ifAbsent to seed a missing key', () {
      final cache = Cache<String, int>(
        store: LRUStore<String, int>(),
        maxSize: 10,
      );
      final result = cache.update('a', (value) => value + 1, ifAbsent: () => 0);
      expect(result, equals(0));
      expect(cache.get('a'), equals(0));
    });

    test('update() throws StateError for a missing key with no ifAbsent', () {
      final cache = Cache<String, int>(
        store: LRUStore<String, int>(),
        maxSize: 10,
      );
      expect(() => cache.update('a', (value) => value + 1), throwsStateError);
    });

    test('setAll() stores every entry', () {
      final cache = Cache<String, int>(
        store: LRUStore<String, int>(),
        maxSize: 10,
      );
      cache.setAll({'a': 1, 'b': 2, 'c': 3});
      expect(cache.get('a'), equals(1));
      expect(cache.get('b'), equals(2));
      expect(cache.get('c'), equals(3));
    });

    // Regression coverage for https://github.com/yordgenome03/cacherine/pull/69
    // review feedback: validateSetArgs() used to only reject a negative
    // explicit weight inside _write(), which getOrSet()/update() skip (or,
    // for update(), only reach after already invoking the caller's callback)
    // on a hit — so the same invalid argument was silently accepted on a hit
    // and only rejected on a miss.
    test('getOrSet() rejects a negative explicit weight even when the key is '
        'already present', () {
      final cache = Cache<String, int>(
        store: LRUStore<String, int>(),
        weigher: (key, value) => value,
        maxWeight: 100,
      );
      cache.set('a', 1);
      expect(
        () => cache.getOrSet('a', () => 2, weight: -1),
        throwsArgumentError,
      );
    });

    test('update() rejects a negative explicit weight before invoking the '
        'update callback', () {
      final cache = Cache<String, int>(
        store: LRUStore<String, int>(),
        weigher: (key, value) => value,
        maxWeight: 100,
      );
      cache.set('a', 1);
      var called = false;
      expect(
        () => cache.update('a', (value) {
          called = true;
          return value + 1;
        }, weight: -1),
        throwsArgumentError,
      );
      expect(called, isFalse);
    });

    test('set() rejects a weigher-computed negative weight (not just an '
        'explicit one)', () {
      final cache = Cache<String, int>(
        store: LRUStore<String, int>(),
        weigher: (key, value) => value, // caller-controlled, can go negative
        maxWeight: 100,
      );
      // No explicit weight: is passed, so validateSetArgs can't catch this
      // eagerly — only _write(), once it has a value to weigh, can.
      expect(() => cache.set('a', -1), throwsArgumentError);
    });

    test('update() leaves the cache and weight ledger untouched when the '
        'update callback throws mid-computation', () {
      final cache = Cache<String, int>(
        store: LRUStore<String, int>(),
        weigher: (key, value) => value,
        maxWeight: 100,
      );
      cache.set('a', 1);

      expect(
        () => cache.update('a', (value) => throw Exception('boom')),
        throwsException,
      );

      expect(cache.get('a'), equals(1));
      expect(cache.currentWeight, equals(1));
      // The cache is still fully usable afterward — nothing was left
      // half-written by the failed update.
      cache.set('b', 2);
      expect(cache.get('b'), equals(2));
      expect(cache.currentWeight, equals(3));
    });
  });

  group('Cache — weigher invocation count', () {
    // Regression coverage: checkWeightRejection() (used by trySet()'s and
    // _storeOrThrow()'s pre-check, i.e. getOrSet()/update()/trySet()) computes
    // the weight once and threads it back into the delegated set() call as an
    // explicit weight: — so set()/_write() reuses that number instead of
    // calling the weigher a second time for the same logical write. This
    // pins the count down explicitly (rather than leaving "how many times a
    // possibly-expensive weigher runs per write" as an unverified accident
    // of the implementation).
    test('a miss through getOrSet()/update()/trySet() calls the weigher '
        'exactly once, not once per internal check', () {
      var weighCalls = 0;
      int countingWeigher(String key, String value) {
        weighCalls++;
        return value.length;
      }

      final cache = Cache<String, String>(
        store: LRUStore<String, String>(),
        weigher: countingWeigher,
        maxWeight: 100,
      );

      weighCalls = 0;
      cache.getOrSet('a', () => '1');
      expect(weighCalls, equals(1));

      weighCalls = 0;
      cache.update('a', (v) => '22');
      expect(weighCalls, equals(1));

      weighCalls = 0;
      expect(cache.trySet('b', '333'), isTrue);
      expect(weighCalls, equals(1));
    });

    test('a plain set() calls the weigher exactly once', () {
      var weighCalls = 0;
      int countingWeigher(String key, String value) {
        weighCalls++;
        return value.length;
      }

      final cache = Cache<String, String>(
        store: LRUStore<String, String>(),
        weigher: countingWeigher,
        maxWeight: 100,
      );

      cache.set('a', '1');
      expect(weighCalls, equals(1));
    });

    // Regression coverage: before checkWeightRejection() threaded a single
    // computed weight through to set(), trySet()/getOrSet()/update() called
    // the weigher once as a pre-check and then a second, independent time
    // inside the delegated set()/_write(). Under a non-deterministic weigher
    // (unsupported per lib/src/interfaces/weigher.dart's "should be
    // pure/deterministic" contract, but not otherwise guarded against), the
    // two calls could disagree — the pre-check could see a small "fits"
    // weight while the actual write computed and stored a much larger one,
    // letting an oversized entry slip past the very check meant to prevent
    // that. A single shared computation makes this scenario moot: there is
    // only one call to disagree with itself.
    test('a stateful (non-deterministic) weigher cannot make trySet() report '
        'success for a write that violates maxWeight, because the weigher '
        'is only consulted once', () {
      var calls = 0;
      // Would return a small "fits" weight on a first call and a huge one on
      // a second call for the same write, if it were ever called twice.
      int flakyWeigher(String key, String value) {
        calls++;
        return calls == 1 ? 1 : 1000;
      }

      final cache = Cache<String, String>(
        store: LRUStore<String, String>(),
        weigher: flakyWeigher,
        maxWeight: 10,
      );

      expect(cache.trySet('a', 'x'), isTrue);
      expect(calls, equals(1));
      expect(cache.currentWeight, equals(1));
      expect(cache.get('a'), equals('x'));
    });
  });

  group('AsyncCache — cache-aside and update helpers', () {
    test(
      'putIfAbsent() computes and stores only when the key is absent',
      () async {
        final cache = AsyncCache<String, int>(
          Cache(store: LRUStore<String, int>(), maxSize: 10),
        );
        var calls = 0;
        Future<int> compute() async {
          calls++;
          return 1;
        }

        expect(await cache.putIfAbsent('a', compute), equals(1));
        expect(await cache.putIfAbsent('a', compute), equals(1));
        expect(calls, equals(1));
      },
    );

    test('update() applies the function to an existing value', () async {
      final cache = AsyncCache<String, int>(
        Cache(store: LRUStore<String, int>(), maxSize: 10),
      );
      await cache.set('a', 1);
      final result = await cache.update('a', (value) async => value + 1);
      expect(result, equals(2));
      expect(await cache.get('a'), equals(2));
    });

    test('update() uses ifAbsent to seed a missing key', () async {
      final cache = AsyncCache<String, int>(
        Cache(store: LRUStore<String, int>(), maxSize: 10),
      );
      final result = await cache.update(
        'a',
        (value) async => value + 1,
        ifAbsent: () async => 0,
      );
      expect(result, equals(0));
      expect(await cache.get('a'), equals(0));
    });

    test(
      'update() throws StateError for a missing key with no ifAbsent',
      () async {
        final cache = AsyncCache<String, int>(
          Cache(store: LRUStore<String, int>(), maxSize: 10),
        );
        expect(
          () => cache.update('a', (value) async => value + 1),
          throwsStateError,
        );
      },
    );

    test('setAll() stores every entry', () async {
      final cache = AsyncCache<String, int>(
        Cache(store: LRUStore<String, int>(), maxSize: 10),
      );
      await cache.setAll({'a': 1, 'b': 2, 'c': 3});
      expect(await cache.get('a'), equals(1));
      expect(await cache.get('b'), equals(2));
      expect(await cache.get('c'), equals(3));
    });

    // Regression coverage: getOrCompute()/update() run the caller's
    // valueFactory/update callback while holding this instance's lock (see
    // the class doc comment). That relies on package:synchronized's
    // Lock.synchronized releasing the lock even when the guarded callback
    // throws — nothing in this suite verified that assumption. If it were
    // ever violated (or a future refactor broke the release-on-throw path),
    // every later call on this instance would hang forever instead of
    // failing loudly, so these bound the "does it recover" check with a
    // timeout rather than letting a regression hang the whole test run.
    test('getOrCompute() releases its lock when valueFactory throws, so a '
        'later call does not deadlock', () async {
      final cache = AsyncCache<String, int>(
        Cache(store: LRUStore<String, int>()),
      );

      await expectLater(
        () => cache.getOrCompute('a', () => throw Exception('boom')),
        throwsException,
      );

      await expectLater(
        cache.set('b', 1).timeout(const Duration(seconds: 2)),
        completes,
      );
      expect(await cache.get('b'), equals(1));
    });

    test('update() releases its lock when the update callback throws, so a '
        'later call does not deadlock', () async {
      final cache = AsyncCache<String, int>(
        Cache(store: LRUStore<String, int>()),
      );
      await cache.set('a', 1);

      await expectLater(
        () => cache.update('a', (value) => throw Exception('boom')),
        throwsException,
      );

      await expectLater(
        cache.set('b', 2).timeout(const Duration(seconds: 2)),
        completes,
      );
      expect(await cache.get('b'), equals(2));
    });

    // Same single-computation guarantee as the sync Cache group above,
    // exercised through AsyncCache.storeOrThrow() (used by
    // getOrCompute()/update()).
    test('a miss through getOrCompute()/update() calls the weigher exactly '
        'once, not once per internal check', () async {
      var weighCalls = 0;
      int countingWeigher(String key, int value) {
        weighCalls++;
        return value;
      }

      final cache = AsyncCache<String, int>(
        Cache(
          store: LRUStore<String, int>(),
          weigher: countingWeigher,
          maxWeight: 100,
        ),
      );

      weighCalls = 0;
      await cache.getOrCompute('a', () async => 1);
      expect(weighCalls, equals(1));

      weighCalls = 0;
      await cache.update('a', (v) async => 2);
      expect(weighCalls, equals(1));
    });
  });

  group('AsyncCache — single-instance lock contention', () {
    // Regression coverage: the class doc comment documents that
    // getOrCompute()/update() hold this instance's lock across the whole
    // awaited valueFactory/update callback, so "concurrent callers on
    // *other* keys are blocked too (the lock is per-instance, not per-key)"
    // — a real tradeoff, not per-key locking. Every existing
    // "serializes concurrent computations" test races two calls on the
    // *same* key, which only proves no duplicate computation happens; it
    // doesn't touch this documented cross-key blocking at all. This drives a
    // slow computation on one key and confirms a plain set() on a
    // completely unrelated key is genuinely blocked behind it, not merely
    // that both eventually complete.
    test('a slow getOrCompute() on one key blocks a concurrent set() on an '
        'unrelated key until it finishes', () async {
      final cache = AsyncCache<String, int>(
        Cache(store: LRUStore<String, int>()),
      );
      final computeStarted = Completer<void>();
      final releaseCompute = Completer<int>();

      final aFuture = cache.getOrCompute('A', () {
        computeStarted.complete();
        return releaseCompute.future;
      });
      await computeStarted
          .future; // A's computation is in flight, holding the lock

      var bDone = false;
      final bFuture = cache.set('B', 1).then((_) => bDone = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bDone, isFalse); // still blocked, despite being an unrelated key

      releaseCompute.complete(42);
      expect(await aFuture, equals(42));
      await bFuture;
      expect(bDone, isTrue);
    });
  });

  group('AsyncCache — reentrant subclass overrides', () {
    test('a set() override that reentrantly calls clear() mid-write does '
        'not deadlock, and leaves the cache in the state sequential '
        'execution implies', () async {
      final cache = _ClearOnSetAsyncCache<String, int>(
        Cache(store: LRUStore<String, int>()),
      );
      await cache.set('seed', 0);

      final result = await cache
          .getOrCompute('a', () async => 1)
          .timeout(const Duration(seconds: 2));

      expect(result, equals(1));
      // clear() ran (from within the set() override, reentering the
      // already-held lock) before 'a' was written, so 'seed' must be gone
      // and 'a' must be present.
      expect(await cache.get('seed'), isNull);
      expect(await cache.get('a'), equals(1));
    });
  });

  group('Cache — unbounded configuration', () {
    // Regression coverage: Cache's constructor validates maxSize/weigher+
    // maxWeight/ttl independently but never rejects all three being omitted
    // — Cache(store: ...) alone is a legal, fully unbounded cache. This was
    // previously an untested configuration; this confirms it's functionally
    // correct at a real scale, not just "presumably fine because nothing
    // rejects it".
    test('a fully unbounded Cache (no maxSize/maxWeight/ttl) correctly holds '
        'a large number of distinct entries', () {
      final cache = Cache<int, int>(store: LRUStore<int, int>());
      const n = 50000;
      for (var i = 0; i < n; i++) {
        cache.set(i, i * 2);
      }
      expect(cache.getKeys().length, equals(n));
      expect(cache.get(0), equals(0));
      expect(cache.get(n ~/ 2), equals(n));
      expect(cache.get(n - 1), equals((n - 1) * 2));
    });
  });

  group('TTL check-then-fetch atomicity', () {
    // Regression coverage: getOrSet()/update()/getOrCompute() used to check
    // presence via containsKey() and then separately fetch via get() — each
    // call reads the clock independently. On a TTL-enabled cache, an expiry
    // landing between those two reads could make containsKey() report "live"
    // and get() immediately after report "expired" (purging it and returning
    // null), corrupting the found/existing-value pair these helpers build on.
    // presentValue() now performs both checks against a single clock reading.
    // A clock that advances by 1 microsecond on every call turns "two reads
    // instead of one" into an observable difference without needing to hit
    // an exact race window in real time.
    test('Cache.getOrSet() reads the clock once per call on a hit', () {
      final counter = _ClockCounter();
      final cache = Cache<String, String>(
        store: LRUStore<String, String>(),
        ttl: const Duration(seconds: 100),
        clock: counter.call,
      );
      cache.set('a', 'value');
      final before = counter.calls;
      expect(cache.getOrSet('a', () => 'unused'), equals('value'));
      expect(counter.calls - before, equals(1));
    });

    test('Cache.update() reads the clock exactly twice on a hit — once for the '
        'atomic presence check, once for the write that persists the new '
        'value — never the three reads a naive containsKey()+get()+set() '
        'chain would take', () {
      final counter = _ClockCounter();
      final cache = Cache<String, int>(
        store: LRUStore<String, int>(),
        ttl: const Duration(seconds: 100),
        clock: counter.call,
      );
      cache.set('a', 1);
      final before = counter.calls;
      expect(cache.update('a', (v) => v + 1), equals(2));
      expect(counter.calls - before, equals(2));
    });

    test(
      'AsyncCache.getOrCompute() reads the clock once per call on a hit',
      () async {
        final counter = _ClockCounter();
        final cache = AsyncCache<String, String>(
          Cache(
            store: LRUStore<String, String>(),
            ttl: const Duration(seconds: 100),
            clock: counter.call,
          ),
        );
        await cache.set('a', 'value');
        final before = counter.calls;
        expect(
          await cache.getOrCompute('a', () async => 'unused'),
          equals('value'),
        );
        expect(counter.calls - before, equals(1));
      },
    );

    test('AsyncCache.update() reads the clock exactly twice on a hit — once '
        'for the atomic presence check, once for the write', () async {
      final counter = _ClockCounter();
      final cache = AsyncCache<String, int>(
        Cache(
          store: LRUStore<String, int>(),
          ttl: const Duration(seconds: 100),
          clock: counter.call,
        ),
      );
      await cache.set('a', 1);
      final before = counter.calls;
      expect(await cache.update('a', (v) async => v + 1), equals(2));
      expect(counter.calls - before, equals(2));
    });

    test('getOrCompute()/update() validate ttl before checking presence or '
        'running valueFactory', () async {
      final cache = AsyncCache<String, String>(
        Cache(
          store: LRUStore<String, String>(),
          ttl: const Duration(seconds: 100),
        ),
      );
      await cache.set(
        'a',
        'value',
      ); // present, so a naive fix might skip validation on a hit
      var factoryCalls = 0;

      await expectLater(
        cache.getOrCompute('a', () async {
          factoryCalls++;
          return 'unused';
        }, ttl: Duration.zero),
        throwsArgumentError,
      );
      expect(factoryCalls, equals(0));

      await expectLater(
        cache.getOrCompute('missing', () async {
          factoryCalls++;
          return 'unused';
        }, ttl: Duration.zero),
        throwsArgumentError,
      );
      expect(factoryCalls, equals(0)); // factory must not run before validation
    });

    // getAll()/removeWhere() had the same bug: SimpleCache/ThreadSafeCache's
    // default implementations check presence and then separately fetch/peek,
    // each reading the clock (and, for AsyncCache, re-acquiring the lock)
    // independently. Cache/AsyncCache now override both to read each key via
    // a single presentValue()/presentPeek() snapshot.
    test('Cache.getAll() reads the clock once per key on a hit', () {
      final counter = _ClockCounter();
      final cache = Cache<String, String>(
        store: LRUStore<String, String>(),
        ttl: const Duration(seconds: 100),
        clock: counter.call,
      );
      cache.set('a', '1');
      cache.set('b', '2');
      final before = counter.calls;
      expect(cache.getAll(['a', 'b']), equals({'a': '1', 'b': '2'}));
      expect(counter.calls - before, equals(2));
    });

    test('Cache.removeWhere() reads the clock once per key and does not bump '
        'LRU recency merely by testing an entry (it must use peek, not '
        'access, or the predicate visiting an entry would perturb eviction '
        'order as a side effect)', () {
      final counter = _ClockCounter();
      final cache = Cache<String, String>(
        store: LRUStore<String, String>(),
        maxSize: 2,
        ttl: const Duration(seconds: 100),
        clock: counter.call,
      );
      cache.set('a', '1');
      cache.set('b', '2');
      final before = counter.calls;
      cache.removeWhere((key, value) => false); // never matches
      // 1 read for getKeys() (to enumerate live keys) + 1 per key for
      // presentPeek() — never 2 reads per key (containsKey()+peek()).
      expect(counter.calls - before, equals(3));

      // If removeWhere had bumped 'a' via access(), 'a' would now be MRU
      // and 'b' would be evicted first; peek-based visiting must leave
      // insertion/recency order exactly as set() left it.
      cache.set('c', '3');
      expect(cache.getKeys(), equals(['b', 'c']));
    });

    test('AsyncCache.getAll() reads the clock once per key on a hit', () async {
      final counter = _ClockCounter();
      final cache = AsyncCache<String, String>(
        Cache(
          store: LRUStore<String, String>(),
          ttl: const Duration(seconds: 100),
          clock: counter.call,
        ),
      );
      await cache.set('a', '1');
      await cache.set('b', '2');
      final before = counter.calls;
      expect(await cache.getAll(['a', 'b']), equals({'a': '1', 'b': '2'}));
      expect(counter.calls - before, equals(2));
    });

    test('AsyncCache.removeWhere() reads the clock once per key and does not '
        'bump LRU recency merely by testing an entry', () async {
      final counter = _ClockCounter();
      final cache = AsyncCache<String, String>(
        Cache(
          store: LRUStore<String, String>(),
          maxSize: 2,
          ttl: const Duration(seconds: 100),
          clock: counter.call,
        ),
      );
      await cache.set('a', '1');
      await cache.set('b', '2');
      final before = counter.calls;
      await cache.removeWhere((key, value) async => false);
      // 1 read for getKeys() + 1 per key for presentPeek().
      expect(counter.calls - before, equals(3));

      await cache.set('c', '3');
      expect(await cache.getKeys(), equals(['b', 'c']));
    });

    test(
      'AsyncCache.removeWhere() removes entries the predicate matches',
      () async {
        final cache = AsyncCache<String, String>(
          Cache(store: LRUStore<String, String>(), maxSize: 10),
        );
        await cache.set('a', '1');
        await cache.set('b', '2');
        await cache.removeWhere((key, value) async => key == 'a');
        expect(await cache.getKeys(), equals(['b']));
      },
    );
  });

  group('MonitoredCache — construction validation', () {
    test('sweepInterval without a configured ttl throws ArgumentError', () {
      expect(
        () => MonitoredCache<String, String>(
          store: LRUStore<String, String>(),
          maxSize: 10,
          sweepInterval: const Duration(seconds: 1),
        ),
        throwsArgumentError,
      );
    });

    test('non-positive sweepInterval throws ArgumentError even with a '
        'configured ttl', () {
      expect(
        () => MonitoredCache<String, String>(
          store: LRUStore<String, String>(),
          ttl: const Duration(seconds: 10),
          sweepInterval: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('a valid sweepInterval starts a background sweep that removes expired '
        'entries and records evictions', () async {
      var now = DateTime(2024);
      final cache = MonitoredCache<String, String>(
        store: LRUStore<String, String>(),
        ttl: const Duration(seconds: 10),
        sweepInterval: const Duration(milliseconds: 5),
        clock: () => now,
      );
      addTearDown(cache.dispose);

      await cache.set('key', 'value');
      now = now.add(const Duration(seconds: 11));

      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(await cache.getKeys(), isEmpty);
      expect(
        cache.metrics.snapshot(const Duration(minutes: 1)).evictionsPerMinute,
        equals(1),
      );
    });
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

    // Regression coverage: _write()'s eviction loop recomputes
    // `wasOverWeight = exceedsWeight()` on every iteration and reports
    // `wasOverWeight ? EvictionReason.weight : EvictionReason.capacity` — but
    // every existing reason test above configures only one of
    // maxSize/maxWeight, so this ternary's behavior when *both* are
    // configured (and which one actually binds for a given write) was never
    // exercised. These three cases pin down: capacity-only-binding,
    // weight-only-binding, and — since removing an entry can only ever
    // shrink both count and weight, never re-trigger either — the case where
    // both conditions are exceeded by the same incoming write, which this
    // ternary always attributes to `.weight`, never `.capacity`.
    group(
      'reason attribution when maxSize and maxWeight are both configured',
      () {
        test('is capacity when only the count limit is actually exceeded', () {
          final reasons = <EvictionReason>[];
          final cache = Cache<String, String>(
            store: LRUStore<String, String>(),
            maxSize: 2,
            weigher: _lengthWeigher,
            maxWeight: 100,
          )..onEvict = reasons.add;

          cache.set('a', '1'); // weight 1, count 1
          cache.set(
            'b',
            '1',
          ); // weight 2, count 2 — at maxSize, weight is nowhere near maxWeight
          cache.set(
            'c',
            '1',
          ); // count would be 3 > maxSize; weight would be 3, still <= 100

          expect(reasons, equals([EvictionReason.capacity]));
        });

        test('is weight when only the weight limit is actually exceeded', () {
          final reasons = <EvictionReason>[];
          final cache = Cache<String, String>(
            store: LRUStore<String, String>(),
            maxSize: 10,
            weigher: _lengthWeigher,
            maxWeight: 2,
          )..onEvict = reasons.add;

          cache.set('a', '1'); // weight 1, count 1
          cache.set(
            'b',
            '1',
          ); // weight 2, count 2 — at maxWeight, count nowhere near maxSize
          cache.set(
            'c',
            '1',
          ); // weight would be 3 > maxWeight; count would be 3, still <= 10

          expect(reasons, equals([EvictionReason.weight]));
        });

        test('is weight, not capacity, when the same write exceeds both limits '
            'at once', () {
          final reasons = <EvictionReason>[];
          final cache = Cache<String, String>(
            store: LRUStore<String, String>(),
            maxSize: 2,
            weigher: _lengthWeigher,
            maxWeight: 2,
          )..onEvict = reasons.add;

          cache.set('a', '1'); // weight 1, count 1
          cache.set('b', '1'); // weight 2, count 2 — exactly at both limits
          cache.set('c', '1'); // count would be 3 > 2 AND weight would be 3 > 2

          expect(reasons, equals([EvictionReason.weight]));
        });
      },
    );

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

  group('MonitoredCache — getAll() traffic metrics', () {
    // Regression coverage for https://github.com/yordgenome03/cacherine/pull/69
    // review feedback: the inherited AsyncCache.getAll() reads each key
    // atomically but is unmonitored, so MonitoredCache used to silently drop
    // the hit/latency metrics doc/monitored_cache.md:125-127 promises.
    test(
      'records a hit per present key, matching repeated get() calls',
      () async {
        final cache = MonitoredCache<String, String>(
          store: LRUStore<String, String>(),
          maxSize: 10,
        );
        await cache.set('a', '1');
        await cache.set('b', '2');

        expect(
          await cache.getAll(['a', 'b', 'missing']),
          equals({'a': '1', 'b': '2'}),
        );
        expect(cache.metrics.hits, equals(2));
        expect(cache.metrics.misses, equals(0)); // omitted, not a recorded miss
      },
    );
  });

  group('MonitoredCache — update() traffic metrics', () {
    // Regression coverage for https://github.com/yordgenome03/cacherine/pull/69
    // review feedback: the pre-existing default update() called get()
    // internally, recording hit/miss metrics via virtual dispatch; the
    // atomic presentValue()-based rewrite that fixed update()'s TTL
    // check-then-fetch race delegated straight to the (unmonitored) engine
    // instead, silently dropping those metrics — contradicting
    // doc/monitored_cache.md's "update() follow[s] getOrCompute() hit/miss
    // semantics" contract.
    test('records a hit on an existing key and a miss via ifAbsent', () async {
      final cache = MonitoredCache<String, int>(
        store: LRUStore<String, int>(),
        maxSize: 10,
      );
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

    test('throws StateError for a missing key with no ifAbsent', () async {
      final cache = MonitoredCache<String, int>(
        store: LRUStore<String, int>(),
        maxSize: 10,
      );
      await expectLater(
        cache.update('missing', (v) async => v),
        throwsStateError,
      );
    });

    // Same lock-release-on-throw concern as AsyncCache above, but here the
    // callback additionally runs inside monitoredGet()'s wrapping — confirm
    // that doesn't change the outcome.
    test('getOrCompute() releases its lock when valueFactory throws, so a '
        'later call does not deadlock', () async {
      final cache = MonitoredCache<String, int>(store: LRUStore<String, int>());
      addTearDown(cache.dispose);

      await expectLater(
        () => cache.getOrCompute('a', () => throw Exception('boom')),
        throwsException,
      );

      await expectLater(
        cache.set('b', 1).timeout(const Duration(seconds: 2)),
        completes,
      );
      expect(await cache.get('b'), equals(1));
    });
  });

  group(
    'Cache engine — access() that removes the entry (EphemeralFIFOStore)',
    () {
      test(
        'get() reconciles the weight ledger when the store removes the entry '
        'as a side effect of access()',
        () {
          final cache = Cache<String, String>(
            store: EphemeralFIFOStore<String, String>(),
            weigher: _lengthWeigher,
            maxWeight: 100,
          );

          cache.set('a', 'aaaaa'); // weight 5
          expect(cache.currentWeight, equals(5));

          expect(cache.get('a'), equals('aaaaa')); // removed by access()
          expect(
            cache.currentWeight,
            equals(0),
          ); // ledger reconciled, not stale

          // Re-inserting under the same key must not be short-changed by a
          // leftover ledger entry.
          cache.set('a', 'bb'); // weight 2
          expect(cache.currentWeight, equals(2));
        },
      );
    },
  );

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

    // Regression coverage: lib/src/stores/lfu_store.dart's `excluding`
    // parameter exists specifically so Cache._write()'s eviction loop can
    // grow an *existing* key's weight without that same key ever being
    // selected as its own eviction victim. test/stores/
    // cache_store_conformance_test.dart exercises that parameter directly
    // against LFUStore in isolation; this drives it end-to-end through the
    // actual integration that motivated it — a weight-bounded LFU Cache
    // overwriting an existing key that happens to be the sole occupant of
    // the minimum-frequency bucket, forcing selectVictim(excluding:) to fall
    // through to the next bucket rather than reporting nothing evictable.
    test('a weight-bounded LFU cache correctly falls through frequency '
        'buckets to find a victim other than the key currently being '
        'written to', () {
      final cache = Cache<String, int>(
        store: LFUStore<String, int>(),
        weigher: (key, value) => value,
        maxWeight: 9,
      );

      cache.set('a', 1); // freq(a) = 1, weight 1
      cache.set('b', 1); // freq(b) = 1, weight 1
      cache.get('b'); // freq(b) = 2; 'a' is now the sole freq-1 occupant

      // Growing 'a' to weight 9 requires evicting to stay within maxWeight
      // (9), but 'a' — the key being written — must be excluded from
      // eviction. The min-frequency (1) bucket now holds only 'a', so the
      // store must fall through to the freq-2 bucket and evict 'b' instead
      // of reporting "nothing to evict".
      cache.set('a', 9);

      expect(cache.get('a'), equals(9));
      expect(cache.get('b'), isNull);
      expect(cache.currentWeight, equals(9));
    });
  });
}
