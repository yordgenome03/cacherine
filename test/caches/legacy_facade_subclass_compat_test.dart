import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

// Regression coverage for https://github.com/yordgenome03/cacherine/pull/69
// review feedback: SimpleLRUCache/LRUCache/MonitoredLRUCache (and their
// sibling "legacy" — pre-composable-engine — facades) used to extend
// Cache/AsyncCache/MonitoredCache directly. Since those engines' set()/
// setAll()/getOrSet()/getOrCompute()/update() gained optional weight:/ttl:
// named parameters, any pre-existing downstream subclass overriding one of
// those methods with the old, narrower signature (as below) would fail to
// *compile* — Dart doesn't allow an override to drop optional named
// parameters present in the method it overrides. These facades were
// rewritten to compose an internal engine instead of extending it, exactly
// like TTLCache/MonitoredTTLCache/SimpleTTLCache already did, specifically
// so old-shaped overrides like these keep compiling. If this file compiles
// and its tests pass, the compatibility is intact for both a sync and an
// async legacy facade family.

class _LoggingSimpleLRUCache<K, V> extends SimpleLRUCache<K, V> {
  final setCalls = <K>[];

  _LoggingSimpleLRUCache(super.maxSize);

  @override
  void set(K key, V value) {
    setCalls.add(key);
    super.set(key, value);
  }
}

class _LoggingLRUCache<K, V> extends LRUCache<K, V> {
  final setCalls = <K>[];

  _LoggingLRUCache(super.maxSize);

  @override
  Future<void> set(K key, V value) async {
    setCalls.add(key);
    await super.set(key, value);
  }
}

class _LoggingMonitoredLRUCache<K, V> extends MonitoredLRUCache<K, V> {
  final setCalls = <K>[];

  _LoggingMonitoredLRUCache({required super.maxSize, super.alertConfig});

  @override
  Future<void> set(K key, V value) async {
    setCalls.add(key);
    await super.set(key, value);
  }
}

// TTLCache/MonitoredTTLCache/SimpleTTLCache have composed an internal engine
// since before this PR, so they never had the compile-breaking issue above —
// but getOrCompute()/getOrSet()/update() writing through the engine directly
// (instead of this class's own set()) has the same subclass-dispatch bypass
// as the non-TTL facades, just discovered separately.

class _LoggingSimpleTTLCache<K, V> extends SimpleTTLCache<K, V> {
  final setCalls = <K>[];

  _LoggingSimpleTTLCache({required super.ttl});

  @override
  void set(K key, V value, {Duration? ttl}) {
    setCalls.add(key);
    super.set(key, value, ttl: ttl);
  }
}

class _LoggingTTLCache<K, V> extends TTLCache<K, V> {
  final setCalls = <K>[];

  _LoggingTTLCache({required super.ttl});

  @override
  Future<void> set(K key, V value, {Duration? ttl}) async {
    setCalls.add(key);
    await super.set(key, value, ttl: ttl);
  }
}

class _LoggingMonitoredTTLCache<K, V> extends MonitoredTTLCache<K, V> {
  final setCalls = <K>[];

  _LoggingMonitoredTTLCache({required super.ttl, super.alertConfig});

  @override
  Future<void> set(K key, V value, {Duration? ttl}) async {
    setCalls.add(key);
    await super.set(key, value, ttl: ttl);
  }
}

// Regression coverage for https://github.com/yordgenome03/cacherine/pull/69
// review comment on pullrequestreview-5073040192: getOrCompute()/update() on
// the five non-TTL legacy facades (LRUCache and its siblings) used to check
// presence and read by calling the composed engine directly instead of this
// class's own (overridable) containsKey()/get() — bypassing a downstream
// subclass's override of either, unlike the pre-existing
// ThreadSafeCache.getOrCompute()/update() defaults these facades stand in
// for (which always dispatched through containsKey()/get()). None of these
// five facades configure a ttl, so — unlike TTLCache — there is no
// check-then-fetch race for two separate dispatched calls to reintroduce.
//
// The bug that prompted this file's expansion was fixed once, in one shared
// helper — but it existed identically in all 5 (then 10, once Monitored
// counterparts are counted) call sites, and only one of them (LRUCache) had
// been exercised by a test before the review caught it. To stop the same
// class of bug — a pattern applied uniformly to several call sites, verified
// against only one of them — from hiding behind an untested sibling again,
// every concrete non-TTL facade is driven through the identical parameterized
// check below, instead of a single hand-picked representative.

mixin _LoggingReads<K, V> on ThreadSafeCache<K, V> {
  final reads = <String>[];

  @override
  Future<V?> get(K key) {
    reads.add('get($key)');
    return super.get(key);
  }

  @override
  Future<bool> containsKey(K key) {
    reads.add('containsKey($key)');
    return super.containsKey(key);
  }
}

class _ReadLoggingLRUCache<K, V> extends LRUCache<K, V>
    with _LoggingReads<K, V> {
  _ReadLoggingLRUCache(super.maxSize);
}

class _ReadLoggingMRUCache<K, V> extends MRUCache<K, V>
    with _LoggingReads<K, V> {
  _ReadLoggingMRUCache(super.maxSize);
}

class _ReadLoggingFIFOCache<K, V> extends FIFOCache<K, V>
    with _LoggingReads<K, V> {
  _ReadLoggingFIFOCache(super.maxSize);
}

class _ReadLoggingLFUCache<K, V> extends LFUCache<K, V>
    with _LoggingReads<K, V> {
  _ReadLoggingLFUCache(super.maxSize);
}

class _ReadLoggingEphemeralFIFOCache<K, V> extends EphemeralFIFOCache<K, V>
    with _LoggingReads<K, V> {
  _ReadLoggingEphemeralFIFOCache(super.maxSize);
}

class _ReadLoggingMonitoredLRUCache<K, V> extends MonitoredLRUCache<K, V>
    with _LoggingReads<K, V> {
  _ReadLoggingMonitoredLRUCache({required super.maxSize, super.alertConfig});
}

class _ReadLoggingMonitoredMRUCache<K, V> extends MonitoredMRUCache<K, V>
    with _LoggingReads<K, V> {
  _ReadLoggingMonitoredMRUCache({required super.maxSize, super.alertConfig});
}

class _ReadLoggingMonitoredFIFOCache<K, V> extends MonitoredFIFOCache<K, V>
    with _LoggingReads<K, V> {
  _ReadLoggingMonitoredFIFOCache({required super.maxSize, super.alertConfig});
}

class _ReadLoggingMonitoredLFUCache<K, V> extends MonitoredLFUCache<K, V>
    with _LoggingReads<K, V> {
  _ReadLoggingMonitoredLFUCache({required super.maxSize, super.alertConfig});
}

class _ReadLoggingMonitoredEphemeralFIFOCache<K, V>
    extends MonitoredEphemeralFIFOCache<K, V>
    with _LoggingReads<K, V> {
  _ReadLoggingMonitoredEphemeralFIFOCache({
    required super.maxSize,
    super.alertConfig,
  });
}

// Shared parameterized check: create a fresh cache, seed key 'a', and verify
// containsKey()/get() dispatch on both a miss (getOrCompute() only) and a
// hit (getOrCompute() and update()). Re-seeds 'a' before the update() check
// since EphemeralFIFOCache's get() consumes it during the prior getOrCompute()
// hit — every other policy leaves 'a' present, so the re-seed is a no-op
// there.
Future<void> _expectReadDispatch<T extends ThreadSafeCache<String, int>>(
  T cache,
  List<String> Function() reads,
) async {
  await cache.set('a', 1);
  reads().clear();

  expect(await cache.getOrCompute('miss', () async => 2), equals(2));
  expect(reads(), equals(['containsKey(miss)']));
  reads().clear();

  expect(await cache.getOrCompute('a', () async => 99), equals(1));
  expect(reads(), equals(['containsKey(a)', 'get(a)']));
  reads().clear();

  await cache.set('a', 1); // re-seed in case get() above consumed it
  reads().clear();

  expect(await cache.update('a', (v) async => v + 1), equals(2));
  expect(reads(), equals(['containsKey(a)', 'get(a)']));
}

void main() {
  group('Legacy facade subclass compatibility', () {
    test('SimpleLRUCache subclass can override set(key, value) with the '
        'pre-existing narrow signature', () {
      final cache = _LoggingSimpleLRUCache<String, String>(10);
      cache.set('a', '1');
      expect(cache.setCalls, equals(['a']));
      expect(cache.get('a'), equals('1'));
    });

    test('LRUCache subclass can override set(key, value) with the '
        'pre-existing narrow signature', () async {
      final cache = _LoggingLRUCache<String, String>(10);
      await cache.set('a', '1');
      expect(cache.setCalls, equals(['a']));
      expect(await cache.get('a'), equals('1'));
    });

    test('MonitoredLRUCache subclass can override set(key, value) with the '
        'pre-existing narrow signature', () async {
      final cache = _LoggingMonitoredLRUCache<String, String>(maxSize: 10);
      addTearDown(cache.dispose);
      await cache.set('a', '1');
      expect(cache.setCalls, equals(['a']));
      expect(await cache.get('a'), equals('1'));
    });

    // Regression coverage for https://github.com/yordgenome03/cacherine/pull/69
    // review feedback: bulk/compound helpers (setAll/update/getOrCompute)
    // used to delegate straight to the internal engine, bypassing a
    // subclass's override of set()/get() entirely — so overriding set() for
    // logging/validation would silently miss every write that went through
    // setAll() or update(). These now go through this class's own
    // (overridable) set()/get(), so a subclass override sees every call.
    test('SimpleLRUCache subclass\'s set() override sees every write made '
        'through setAll()/update()', () {
      final cache = _LoggingSimpleLRUCache<String, int>(10);
      cache.setAll({'a': 1, 'b': 2});
      expect(cache.setCalls, equals(['a', 'b']));
      cache.update('a', (v) => v + 1);
      expect(cache.setCalls, equals(['a', 'b', 'a']));
    });

    test('LRUCache subclass\'s set() override sees every write made '
        'through setAll()/update()', () async {
      final cache = _LoggingLRUCache<String, int>(10);
      await cache.setAll({'a': 1, 'b': 2});
      expect(cache.setCalls, equals(['a', 'b']));
      await cache.update('a', (v) async => v + 1);
      expect(cache.setCalls, equals(['a', 'b', 'a']));
    });

    test('MonitoredLRUCache subclass\'s set() override sees every write '
        'made through setAll()/update()', () async {
      final cache = _LoggingMonitoredLRUCache<String, int>(maxSize: 10);
      addTearDown(cache.dispose);
      await cache.setAll({'a': 1, 'b': 2});
      expect(cache.setCalls, equals(['a', 'b']));
      await cache.update('a', (v) async => v + 1);
      expect(cache.setCalls, equals(['a', 'b', 'a']));
    });

    test('SimpleTTLCache subclass\'s set() override sees every write made '
        'through getOrSet()/update()', () {
      final cache = _LoggingSimpleTTLCache<String, int>(
        ttl: const Duration(seconds: 100),
      );
      expect(cache.getOrSet('a', () => 1), equals(1));
      expect(cache.setCalls, equals(['a']));
      cache.update('a', (v) => v + 1);
      expect(cache.setCalls, equals(['a', 'a']));
    });

    test('TTLCache subclass\'s set() override sees every write made '
        'through getOrCompute()/update()', () async {
      final cache = _LoggingTTLCache<String, int>(
        ttl: const Duration(seconds: 100),
      );
      addTearDown(cache.dispose);
      expect(await cache.getOrCompute('a', () async => 1), equals(1));
      expect(cache.setCalls, equals(['a']));
      await cache.update('a', (v) async => v + 1);
      expect(cache.setCalls, equals(['a', 'a']));
    });

    test('MonitoredTTLCache subclass\'s set() override sees every write '
        'made through getOrCompute()/update()', () async {
      final cache = _LoggingMonitoredTTLCache<String, int>(
        ttl: const Duration(seconds: 100),
      );
      addTearDown(cache.dispose);
      expect(await cache.getOrCompute('a', () async => 1), equals(1));
      expect(cache.setCalls, equals(['a']));
      await cache.update('a', (v) async => v + 1);
      expect(cache.setCalls, equals(['a', 'a']));
    });

    test('LRUCache subclass\'s containsKey()/get() overrides see every read '
        'made through getOrCompute()/update()', () async {
      final cache = _ReadLoggingLRUCache<String, int>(10);
      await _expectReadDispatch(cache, () => cache.reads);
    });

    test('MRUCache subclass\'s containsKey()/get() overrides see every read '
        'made through getOrCompute()/update()', () async {
      final cache = _ReadLoggingMRUCache<String, int>(10);
      await _expectReadDispatch(cache, () => cache.reads);
    });

    test('FIFOCache subclass\'s containsKey()/get() overrides see every '
        'read made through getOrCompute()/update()', () async {
      final cache = _ReadLoggingFIFOCache<String, int>(10);
      await _expectReadDispatch(cache, () => cache.reads);
    });

    test('LFUCache subclass\'s containsKey()/get() overrides see every read '
        'made through getOrCompute()/update()', () async {
      final cache = _ReadLoggingLFUCache<String, int>(10);
      await _expectReadDispatch(cache, () => cache.reads);
    });

    test('EphemeralFIFOCache subclass\'s containsKey()/get() overrides see '
        'every read made through getOrCompute()/update()', () async {
      final cache = _ReadLoggingEphemeralFIFOCache<String, int>(10);
      await _expectReadDispatch(cache, () => cache.reads);
    });

    test('MonitoredLRUCache subclass\'s containsKey()/get() overrides see '
        'every read made through getOrCompute()/update()', () async {
      final cache = _ReadLoggingMonitoredLRUCache<String, int>(maxSize: 10);
      addTearDown(cache.dispose);
      await _expectReadDispatch(cache, () => cache.reads);
    });

    test('MonitoredMRUCache subclass\'s containsKey()/get() overrides see '
        'every read made through getOrCompute()/update()', () async {
      final cache = _ReadLoggingMonitoredMRUCache<String, int>(maxSize: 10);
      addTearDown(cache.dispose);
      await _expectReadDispatch(cache, () => cache.reads);
    });

    test('MonitoredFIFOCache subclass\'s containsKey()/get() overrides see '
        'every read made through getOrCompute()/update()', () async {
      final cache = _ReadLoggingMonitoredFIFOCache<String, int>(maxSize: 10);
      addTearDown(cache.dispose);
      await _expectReadDispatch(cache, () => cache.reads);
    });

    test('MonitoredLFUCache subclass\'s containsKey()/get() overrides see '
        'every read made through getOrCompute()/update()', () async {
      final cache = _ReadLoggingMonitoredLFUCache<String, int>(maxSize: 10);
      addTearDown(cache.dispose);
      await _expectReadDispatch(cache, () => cache.reads);
    });

    test(
      'MonitoredEphemeralFIFOCache subclass\'s containsKey()/get() '
      'overrides see every read made through getOrCompute()/update()',
      () async {
        final cache = _ReadLoggingMonitoredEphemeralFIFOCache<String, int>(
          maxSize: 10,
        );
        addTearDown(cache.dispose);
        await _expectReadDispatch(cache, () => cache.reads);
      },
    );

    // Regression coverage for the same review comment: the Monitored*Cache
    // legacy facades' update()/getOrCompute() used to wrap the *whole*
    // check-compute-store sequence in one monitoredGet() call, so no hit was
    // recorded at all if the caller's update callback threw afterward.
    // Dispatching the presence check through this class's own (already
    // monitored) get() records the hit as soon as the read resolves — before
    // the callback that might throw ever runs — matching the pre-existing
    // ThreadSafeCache.update() default. Swept across every concrete
    // Monitored*Cache legacy facade for the same reason as the read-dispatch
    // sweep above: this bug previously existed identically in all five and
    // only one had ever been exercised by a test. _MonitoredFacadeHarness
    // gives the loop below a single, statically-typed shape to drive, since
    // the five concrete classes share no common supertype exposing
    // set/update/getOrCompute alongside metrics/dispose.
    for (final entry in <String, _MonitoredFacadeHarness Function()>{
      'MonitoredLRUCache': () =>
          _MonitoredLRUHarness(MonitoredLRUCache(maxSize: 10)),
      'MonitoredMRUCache': () =>
          _MonitoredMRUHarness(MonitoredMRUCache(maxSize: 10)),
      'MonitoredFIFOCache': () =>
          _MonitoredFIFOHarness(MonitoredFIFOCache(maxSize: 10)),
      'MonitoredLFUCache': () =>
          _MonitoredLFUHarness(MonitoredLFUCache(maxSize: 10)),
      'MonitoredEphemeralFIFOCache': () => _MonitoredEphemeralFIFOHarness(
        MonitoredEphemeralFIFOCache(maxSize: 10),
      ),
    }.entries) {
      final name = entry.key;
      final create = entry.value;

      test('$name records a hit for update() even if the updater throws '
          'after the read', () async {
        final cache = create();
        addTearDown(cache.dispose);
        await cache.set('a', 1);

        await expectLater(
          cache.update('a', (v) async => throw Exception('boom')),
          throwsException,
        );
        expect(cache.hits, equals(1));
        expect(cache.misses, equals(0));
      });

      test('$name records a hit for getOrCompute() even though it never '
          'calls valueFactory on a hit', () async {
        final cache = create();
        addTearDown(cache.dispose);
        await cache.set('a', 1);

        expect(await cache.getOrCompute('a', () async => 99), equals(1));
        expect(cache.hits, equals(1));
        expect(cache.misses, equals(0));
      });
    }
  });
}

/// Statically-typed access to the surface the metrics-timing sweep above
/// needs, common to every `Monitored*Cache` legacy facade — these classes
/// share no common supertype exposing `set`/`update`/`getOrCompute`
/// alongside `metrics`/`dispose`, so each concrete facade gets a thin
/// wrapper implementing this instead of driving the loop through `dynamic`.
abstract class _MonitoredFacadeHarness {
  Future<void> set(String key, int value);
  Future<int> update(String key, Future<int> Function(int value) updater);
  Future<int> getOrCompute(String key, Future<int> Function() valueFactory);
  int get hits;
  int get misses;
  void dispose();
}

class _MonitoredLRUHarness implements _MonitoredFacadeHarness {
  _MonitoredLRUHarness(this._cache);
  final MonitoredLRUCache<String, int> _cache;

  @override
  Future<void> set(String key, int value) => _cache.set(key, value);
  @override
  Future<int> update(String key, Future<int> Function(int value) updater) =>
      _cache.update(key, updater);
  @override
  Future<int> getOrCompute(String key, Future<int> Function() valueFactory) =>
      _cache.getOrCompute(key, valueFactory);
  @override
  int get hits => _cache.metrics.hits;
  @override
  int get misses => _cache.metrics.misses;
  @override
  void dispose() => _cache.dispose();
}

class _MonitoredMRUHarness implements _MonitoredFacadeHarness {
  _MonitoredMRUHarness(this._cache);
  final MonitoredMRUCache<String, int> _cache;

  @override
  Future<void> set(String key, int value) => _cache.set(key, value);
  @override
  Future<int> update(String key, Future<int> Function(int value) updater) =>
      _cache.update(key, updater);
  @override
  Future<int> getOrCompute(String key, Future<int> Function() valueFactory) =>
      _cache.getOrCompute(key, valueFactory);
  @override
  int get hits => _cache.metrics.hits;
  @override
  int get misses => _cache.metrics.misses;
  @override
  void dispose() => _cache.dispose();
}

class _MonitoredFIFOHarness implements _MonitoredFacadeHarness {
  _MonitoredFIFOHarness(this._cache);
  final MonitoredFIFOCache<String, int> _cache;

  @override
  Future<void> set(String key, int value) => _cache.set(key, value);
  @override
  Future<int> update(String key, Future<int> Function(int value) updater) =>
      _cache.update(key, updater);
  @override
  Future<int> getOrCompute(String key, Future<int> Function() valueFactory) =>
      _cache.getOrCompute(key, valueFactory);
  @override
  int get hits => _cache.metrics.hits;
  @override
  int get misses => _cache.metrics.misses;
  @override
  void dispose() => _cache.dispose();
}

class _MonitoredLFUHarness implements _MonitoredFacadeHarness {
  _MonitoredLFUHarness(this._cache);
  final MonitoredLFUCache<String, int> _cache;

  @override
  Future<void> set(String key, int value) => _cache.set(key, value);
  @override
  Future<int> update(String key, Future<int> Function(int value) updater) =>
      _cache.update(key, updater);
  @override
  Future<int> getOrCompute(String key, Future<int> Function() valueFactory) =>
      _cache.getOrCompute(key, valueFactory);
  @override
  int get hits => _cache.metrics.hits;
  @override
  int get misses => _cache.metrics.misses;
  @override
  void dispose() => _cache.dispose();
}

class _MonitoredEphemeralFIFOHarness implements _MonitoredFacadeHarness {
  _MonitoredEphemeralFIFOHarness(this._cache);
  final MonitoredEphemeralFIFOCache<String, int> _cache;

  @override
  Future<void> set(String key, int value) => _cache.set(key, value);
  @override
  Future<int> update(String key, Future<int> Function(int value) updater) =>
      _cache.update(key, updater);
  @override
  Future<int> getOrCompute(String key, Future<int> Function() valueFactory) =>
      _cache.getOrCompute(key, valueFactory);
  @override
  int get hits => _cache.metrics.hits;
  @override
  int get misses => _cache.metrics.misses;
  @override
  void dispose() => _cache.dispose();
}
