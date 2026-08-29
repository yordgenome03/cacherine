import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

int _lengthWeigher(String key, String value) => value.length;

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
  });
}
