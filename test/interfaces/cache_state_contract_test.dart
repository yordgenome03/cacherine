import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

class _DefaultSimpleCache<K, V> extends SimpleCache<K, V> {
  final Map<K, V> _cache = {};

  @override
  Iterable<K> getKeys() => _cache.keys.toList();

  @override
  V? get(K key) => _cache[key];

  @override
  bool containsKey(K key) => _cache.containsKey(key);

  @override
  void set(K key, V value) {
    _cache[key] = value;
  }

  @override
  void remove(K key) {
    _cache.remove(key);
  }

  @override
  void clear() {
    _cache.clear();
  }
}

class _DefaultThreadSafeCache<K, V> extends ThreadSafeCache<K, V> {
  final Map<K, V> _cache = {};

  @override
  Future<Iterable<K>> getKeys() async => _cache.keys.toList();

  @override
  Future<V?> get(K key) async => _cache[key];

  @override
  Future<bool> containsKey(K key) async => _cache.containsKey(key);

  @override
  Future<void> set(K key, V value) async {
    _cache[key] = value;
  }

  @override
  Future<void> remove(K key) async {
    _cache.remove(key);
  }

  @override
  Future<void> clear() async {
    _cache.clear();
  }
}

void main() {
  group('SimpleCache state contract', () {
    test('default occupancy getters derive from getKeys()', () {
      final cache = _DefaultSimpleCache<String, String>();

      expect(cache.size, equals(0));
      expect(cache.isEmpty, isTrue);
      expect(cache.isNotEmpty, isFalse);

      cache.set('a', 'A');
      cache.set('b', 'B');

      expect(cache.size, equals(2));
      expect(cache.isEmpty, isFalse);
      expect(cache.isNotEmpty, isTrue);
    });

    test('peek does not consume SimpleEphemeralFIFOCache entries', () {
      final SimpleCache<String, String> cache =
          SimpleEphemeralFIFOCache<String, String>(2);

      cache.set('a', 'A');

      expect(cache.peek('a'), equals('A'));
      expect(cache.get('a'), equals('A'));
      expect(cache.containsKey('a'), isFalse);
    });

    test('peek does not update SimpleLRUCache recency', () {
      final SimpleCache<String, String> cache = SimpleLRUCache<String, String>(
        2,
      );

      cache.set('a', 'A');
      cache.set('b', 'B');
      expect(cache.peek('a'), equals('A'));
      cache.set('c', 'C');

      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
      expect(cache.containsKey('c'), isTrue);
    });

    test('peek does not update SimpleMRUCache recency', () {
      final SimpleCache<String, String> cache = SimpleMRUCache<String, String>(
        2,
      );

      cache.set('a', 'A');
      cache.set('b', 'B');
      expect(cache.peek('a'), equals('A'));
      cache.set('c', 'C');

      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.containsKey('c'), isTrue);
    });

    test('peek does not increment SimpleLFUCache frequency', () {
      final SimpleCache<String, String> cache = SimpleLFUCache<String, String>(
        2,
      );

      cache.set('a', 'A');
      cache.set('b', 'B');
      expect(cache.peek('a'), equals('A'));
      cache.set('c', 'C');

      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
      expect(cache.containsKey('c'), isTrue);
    });
  });

  group('ThreadSafeCache state contract', () {
    test('default occupancy getters derive from getKeys()', () async {
      final cache = _DefaultThreadSafeCache<String, String>();

      expect(await cache.size, equals(0));
      expect(await cache.isEmpty, isTrue);
      expect(await cache.isNotEmpty, isFalse);

      await cache.set('a', 'A');
      await cache.set('b', 'B');

      expect(await cache.size, equals(2));
      expect(await cache.isEmpty, isFalse);
      expect(await cache.isNotEmpty, isTrue);
    });
  });
}
