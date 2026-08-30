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
  });
}
