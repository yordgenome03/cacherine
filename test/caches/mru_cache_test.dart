import 'package:test/test.dart';
import 'package:cacherine/src/caches/mru_cache.dart';

void main() {
  group('MRUCache - 基本動作', () {
    test('空のキャッシュから get() すると null を返す', () async {
      final cache = MRUCache<String, String>(3);
      expect(await cache.get('key1'), isNull);
    });

    test('set() したデータが get() で取得できる', () async {
      final cache = MRUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.get('key2'), equals('value2'));
    });

    test('clear() でキャッシュが空になる', () async {
      final cache = MRUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('MRUCache - MRU エビクションのテスト', () {
    test('キャッシュが maxSize を超えたら MRU で削除される', () async {
      final cache = MRUCache<String, String>(2);

      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.get('key2'); // key2 を最近使用

      await cache.set('key3', 'value3'); // key2 が削除される

      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.get('key2'), isNull);
      expect(await cache.get('key3'), equals('value3'));
    });
  });

  group('MRUCache - スレッドセーフ性のテスト', () {
    test('並列 set() / get() が安全に動作する', () async {
      final cache = MRUCache<int, String>(5);

      final futures = List.generate(1000, (i) async {
        await cache.set(i % 5, 'value$i');
        return await cache.get(i % 5);
      });

      await Future.wait(futures);

      expect(cache.getKeys().length, equals(5));
      expect(cache.getKeys(), containsAll([0, 1, 2, 3, 4]));
    });
  });

  group('MRUCache - エラーハンドリング', () {
    test('maxSize が 0 以下の時に ArgumentError をスローする', () {
      expect(() => MRUCache<String, String>(0), throwsArgumentError);
      expect(() => MRUCache<String, String>(-1), throwsArgumentError);
    });
  });
}
