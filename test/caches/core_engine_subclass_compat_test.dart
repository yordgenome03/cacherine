import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

// Regression coverage for the composable engine classes (Cache/AsyncCache/
// MonitoredCache) and the Weighted*Cache facades built directly on top of
// them. legacy_facade_subclass_compat_test.dart covers the 15 legacy
// facades + TTLCache/MonitoredTTLCache/SimpleTTLCache, all of which write
// through this class's own set() so a subclass override sees every write —
// but those facades all *compose* an internal engine rather than extending
// it. Cache/AsyncCache/MonitoredCache are the engine itself: a subclass of
// one of these overriding set() is exactly the scenario the Weighted*Cache
// facades are built from (they extend these classes directly and add no
// set() of their own), and it was not covered by any test until now.
//
// Note: getAll()/removeWhere() are *not* covered here — like
// TTLCache/SimpleTTLCache, they intentionally read via a single
// presentValue()/presentPeek() snapshot instead of this class's own
// get()/peek(), to keep check-then-read atomic under TTL/weight. That's a
// deliberate, already-documented exception to "always dispatch through the
// overridable method", not an oversight.

class _LoggingCache<K, V> extends Cache<K, V> {
  final setCalls = <K>[];

  _LoggingCache({
    required super.store,
    super.maxSize,
    super.weigher,
    super.maxWeight,
  });

  @override
  void set(K key, V value, {int? weight, Duration? ttl}) {
    setCalls.add(key);
    super.set(key, value, weight: weight, ttl: ttl);
  }
}

class _LoggingAsyncCache<K, V> extends AsyncCache<K, V> {
  final setCalls = <K>[];

  _LoggingAsyncCache(super.engine);

  @override
  Future<void> set(K key, V value, {int? weight, Duration? ttl}) async {
    setCalls.add(key);
    await super.set(key, value, weight: weight, ttl: ttl);
  }
}

class _LoggingMonitoredCache<K, V> extends MonitoredCache<K, V> {
  final setCalls = <K>[];

  _LoggingMonitoredCache({
    required super.store,
    super.maxSize,
    super.weigher,
    super.maxWeight,
  });

  @override
  Future<void> set(K key, V value, {int? weight, Duration? ttl}) async {
    setCalls.add(key);
    await super.set(key, value, weight: weight, ttl: ttl);
  }
}

class _LoggingSimpleWeightedLRUCache<K, V>
    extends SimpleWeightedLRUCache<K, V> {
  final setCalls = <K>[];

  _LoggingSimpleWeightedLRUCache({
    required super.weigher,
    required super.maxWeight,
    super.maxSize,
  });

  @override
  void set(K key, V value, {int? weight, Duration? ttl}) {
    setCalls.add(key);
    super.set(key, value, weight: weight, ttl: ttl);
  }
}

class _LoggingWeightedLRUCache<K, V> extends WeightedLRUCache<K, V> {
  final setCalls = <K>[];

  _LoggingWeightedLRUCache({
    required super.weigher,
    required super.maxWeight,
    super.maxSize,
  });

  @override
  Future<void> set(K key, V value, {int? weight, Duration? ttl}) async {
    setCalls.add(key);
    await super.set(key, value, weight: weight, ttl: ttl);
  }
}

class _LoggingMonitoredWeightedLRUCache<K, V>
    extends MonitoredWeightedLRUCache<K, V> {
  final setCalls = <K>[];

  _LoggingMonitoredWeightedLRUCache({
    required super.weigher,
    required super.maxWeight,
    super.maxSize,
    super.alertConfig,
  });

  @override
  Future<void> set(K key, V value, {int? weight, Duration? ttl}) async {
    setCalls.add(key);
    await super.set(key, value, weight: weight, ttl: ttl);
  }
}

void main() {
  group('Cache subclass compatibility', () {
    test('set() override is invoked directly', () {
      final cache = _LoggingCache<String, String>(store: LRUStore());
      cache.set('a', '1');
      expect(cache.setCalls, equals(['a']));
      expect(cache.get('a'), equals('1'));
    });

    test('set() override sees every write made through '
        'getOrSet()/update()/setAll()/trySet()', () {
      final cache = _LoggingCache<String, int>(store: LRUStore());
      expect(cache.getOrSet('a', () => 1), equals(1));
      expect(cache.setCalls, equals(['a']));
      cache.update('a', (v) => v + 1);
      expect(cache.setCalls, equals(['a', 'a']));
      cache.setAll({'b': 2, 'c': 3});
      expect(cache.setCalls, equals(['a', 'a', 'b', 'c']));
      expect(cache.trySet('d', 4), isTrue);
      expect(cache.setCalls, equals(['a', 'a', 'b', 'c', 'd']));
    });

    test('a doomed weight-exceeding write does not invoke set() at all', () {
      final cache = _LoggingCache<String, int>(
        store: LRUStore(),
        weigher: (key, value) => value,
        maxWeight: 10,
      );
      expect(() => cache.getOrSet('a', () => 100), throwsStateError);
      expect(cache.setCalls, isEmpty);
      expect(
        () => cache.update('a', (v) => v, ifAbsent: () => 100),
        throwsStateError,
      );
      expect(cache.setCalls, isEmpty);
      expect(cache.trySet('a', 100), isFalse);
      expect(cache.setCalls, isEmpty);
    });
  });

  group('AsyncCache subclass compatibility', () {
    test('set() override is invoked directly', () async {
      final cache = _LoggingAsyncCache<String, String>(
        Cache(store: LRUStore()),
      );
      await cache.set('a', '1');
      expect(cache.setCalls, equals(['a']));
      expect(await cache.get('a'), equals('1'));
    });

    test('set() override sees every write made through '
        'getOrCompute()/update()/setAll()', () async {
      final cache = _LoggingAsyncCache<String, int>(Cache(store: LRUStore()));
      expect(await cache.getOrCompute('a', () async => 1), equals(1));
      expect(cache.setCalls, equals(['a']));
      await cache.update('a', (v) async => v + 1);
      expect(cache.setCalls, equals(['a', 'a']));
      await cache.setAll({'b': 2, 'c': 3});
      expect(cache.setCalls, equals(['a', 'a', 'b', 'c']));
    });

    test(
      'a doomed weight-exceeding write does not invoke set() at all',
      () async {
        final cache = _LoggingAsyncCache<String, int>(
          Cache(
            store: LRUStore(),
            weigher: (key, value) => value,
            maxWeight: 10,
          ),
        );
        await expectLater(
          () => cache.getOrCompute('a', () async => 100),
          throwsStateError,
        );
        expect(cache.setCalls, isEmpty);
        await expectLater(
          () => cache.update('a', (v) async => v, ifAbsent: () async => 100),
          throwsStateError,
        );
        expect(cache.setCalls, isEmpty);
      },
    );
  });

  group('MonitoredCache subclass compatibility', () {
    test('set() override is invoked directly', () async {
      final cache = _LoggingMonitoredCache<String, String>(store: LRUStore());
      addTearDown(cache.dispose);
      await cache.set('a', '1');
      expect(cache.setCalls, equals(['a']));
      expect(await cache.get('a'), equals('1'));
    });

    test('set() override sees every write made through '
        'getOrCompute()/update()/setAll()', () async {
      final cache = _LoggingMonitoredCache<String, int>(store: LRUStore());
      addTearDown(cache.dispose);
      expect(await cache.getOrCompute('a', () async => 1), equals(1));
      expect(cache.setCalls, equals(['a']));
      await cache.update('a', (v) async => v + 1);
      expect(cache.setCalls, equals(['a', 'a']));
      await cache.setAll({'b': 2, 'c': 3});
      expect(cache.setCalls, equals(['a', 'a', 'b', 'c']));
    });
  });

  group('SimpleWeightedLRUCache subclass compatibility', () {
    test('set() override sees every write made through '
        'getOrSet()/update()/setAll()', () {
      final cache = _LoggingSimpleWeightedLRUCache<String, int>(
        weigher: (key, value) => value,
        maxWeight: 100,
      );
      expect(cache.getOrSet('a', () => 1), equals(1));
      expect(cache.setCalls, equals(['a']));
      cache.update('a', (v) => v + 1);
      expect(cache.setCalls, equals(['a', 'a']));
      cache.setAll({'b': 2, 'c': 3});
      expect(cache.setCalls, equals(['a', 'a', 'b', 'c']));
    });

    test('a doomed weight-exceeding write does not invoke set() at all', () {
      final cache = _LoggingSimpleWeightedLRUCache<String, int>(
        weigher: (key, value) => value,
        maxWeight: 10,
      );
      expect(() => cache.getOrSet('a', () => 100), throwsStateError);
      expect(cache.setCalls, isEmpty);
    });
  });

  group('WeightedLRUCache subclass compatibility', () {
    test('set() override sees every write made through '
        'getOrCompute()/update()/setAll()', () async {
      final cache = _LoggingWeightedLRUCache<String, int>(
        weigher: (key, value) => value,
        maxWeight: 100,
      );
      expect(await cache.getOrCompute('a', () async => 1), equals(1));
      expect(cache.setCalls, equals(['a']));
      await cache.update('a', (v) async => v + 1);
      expect(cache.setCalls, equals(['a', 'a']));
      await cache.setAll({'b': 2, 'c': 3});
      expect(cache.setCalls, equals(['a', 'a', 'b', 'c']));
    });

    test(
      'a doomed weight-exceeding write does not invoke set() at all',
      () async {
        final cache = _LoggingWeightedLRUCache<String, int>(
          weigher: (key, value) => value,
          maxWeight: 10,
        );
        await expectLater(
          () => cache.getOrCompute('a', () async => 100),
          throwsStateError,
        );
        expect(cache.setCalls, isEmpty);
      },
    );
  });

  group('MonitoredWeightedLRUCache subclass compatibility', () {
    test('set() override sees every write made through '
        'getOrCompute()/update()/setAll()', () async {
      final cache = _LoggingMonitoredWeightedLRUCache<String, int>(
        weigher: (key, value) => value,
        maxWeight: 100,
      );
      addTearDown(cache.dispose);
      expect(await cache.getOrCompute('a', () async => 1), equals(1));
      expect(cache.setCalls, equals(['a']));
      await cache.update('a', (v) async => v + 1);
      expect(cache.setCalls, equals(['a', 'a']));
      await cache.setAll({'b': 2, 'c': 3});
      expect(cache.setCalls, equals(['a', 'a', 'b', 'c']));
    });
  });
}
