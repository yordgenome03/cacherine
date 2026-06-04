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

    test('putIfAbsent returns existing stored null without computing', () {
      final cache = _DefaultSimpleCache<String, String?>();
      var computes = 0;

      cache.set('key', null);

      expect(
        cache.putIfAbsent('key', () {
          computes++;
          return 'computed';
        }),
        isNull,
      );
      expect(computes, equals(0));
    });

    test('getAll returns present values including stored nulls', () {
      final cache = _DefaultSimpleCache<String, String?>();

      cache.set('present', 'value');
      cache.set('null', null);

      expect(
        cache.getAll(['present', 'missing', 'null']),
        equals({'present': 'value', 'null': null}),
      );
    });

    test('setAll stores entries and removeAll removes matching keys', () {
      final cache = _DefaultSimpleCache<String, int>();

      cache.setAll({'a': 1, 'b': 2, 'c': 3});
      cache.removeAll(['b', 'missing']);

      expect(cache.getAll(['a', 'b', 'c']), equals({'a': 1, 'c': 3}));
    });

    test('update changes existing values and supports ifAbsent', () {
      final cache = _DefaultSimpleCache<String, int>();

      cache.set('key', 1);

      expect(cache.update('key', (value) => value + 1), equals(2));
      expect(cache.get('key'), equals(2));
      expect(
        cache.update('missing', (value) => value + 1, ifAbsent: () => 10),
        equals(10),
      );
      expect(cache.get('missing'), equals(10));
      expect(() => cache.update('absent', (value) => value), throwsStateError);
    });

    test(
      'removeWhere removes matching entries without consuming peekable state',
      () {
        final SimpleCache<String, String> cache =
            SimpleEphemeralFIFOCache<String, String>(3);

        cache.set('a', 'A');
        cache.set('b', 'B');
        cache.set('c', 'C');

        cache.removeWhere((key, value) => key == 'b' || value == 'C');

        expect(cache.containsKey('a'), isTrue);
        expect(cache.containsKey('b'), isFalse);
        expect(cache.containsKey('c'), isFalse);
        expect(cache.get('a'), equals('A'));
      },
    );

    test('getAll applies get policy side effects for present keys', () {
      final SimpleCache<String, String> cache =
          SimpleEphemeralFIFOCache<String, String>(3);

      cache.set('a', 'A');
      cache.set('b', 'B');

      expect(cache.getAll(['a', 'missing', 'b']), equals({'a': 'A', 'b': 'B'}));
      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isFalse);
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

    test(
      'putIfAbsent returns existing stored null without computing',
      () async {
        final cache = _DefaultThreadSafeCache<String, String?>();
        var computes = 0;

        await cache.set('key', null);

        expect(
          await cache.putIfAbsent('key', () {
            computes++;
            return 'computed';
          }),
          isNull,
        );
        expect(computes, equals(0));
      },
    );

    test('getAll returns present values including stored nulls', () async {
      final cache = _DefaultThreadSafeCache<String, String?>();

      await cache.set('present', 'value');
      await cache.set('null', null);

      expect(
        await cache.getAll(['present', 'missing', 'null']),
        equals({'present': 'value', 'null': null}),
      );
    });

    test('setAll stores entries and removeAll removes matching keys', () async {
      final cache = _DefaultThreadSafeCache<String, int>();

      await cache.setAll({'a': 1, 'b': 2, 'c': 3});
      await cache.removeAll(['b', 'missing']);

      expect(await cache.getAll(['a', 'b', 'c']), equals({'a': 1, 'c': 3}));
    });

    test(
      'update changes existing values and supports async ifAbsent',
      () async {
        final cache = _DefaultThreadSafeCache<String, int>();

        await cache.set('key', 1);

        expect(await cache.update('key', (value) => value + 1), equals(2));
        expect(await cache.get('key'), equals(2));
        expect(
          await cache.update(
            'missing',
            (value) => value + 1,
            ifAbsent: () async => 10,
          ),
          equals(10),
        );
        expect(await cache.get('missing'), equals(10));
        await expectLater(
          () => cache.update('absent', (value) => value),
          throwsStateError,
        );
      },
    );

    test(
      'removeWhere removes matching entries without updating LRU recency',
      () async {
        final ThreadSafeCache<String, String> cache = LRUCache<String, String>(
          3,
        );

        await cache.set('a', 'A');
        await cache.set('b', 'B');
        await cache.set('c', 'C');

        await cache.removeWhere((key, value) => key == 'b' || value == 'C');
        await cache.set('d', 'D');

        expect(await cache.containsKey('a'), isTrue);
        expect(await cache.containsKey('b'), isFalse);
        expect(await cache.containsKey('c'), isFalse);
        expect(await cache.containsKey('d'), isTrue);
      },
    );

    test('getAll applies get policy side effects for present keys', () async {
      final ThreadSafeCache<String, String> cache =
          EphemeralFIFOCache<String, String>(3);

      await cache.set('a', 'A');
      await cache.set('b', 'B');

      expect(
        await cache.getAll(['a', 'missing', 'b']),
        equals({'a': 'A', 'b': 'B'}),
      );
      expect(await cache.containsKey('a'), isFalse);
      expect(await cache.containsKey('b'), isFalse);
    });
  });
}
