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
  });
}
