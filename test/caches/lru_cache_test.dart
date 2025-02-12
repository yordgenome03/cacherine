import 'package:test/test.dart';
import 'package:cacherine/src/caches/lru_cache.dart';

void main() {
  group('LRUCache - 基本動作', () {
    test('空のキャッシュから get() すると null を返す', () async {
      final cache = LRUCache<String, String>(3);
      expect(await cache.get('key1'), isNull);
    });

    test('set() したデータが get() で取得できる', () async {
      final cache = LRUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.get('key2'), equals('value2'));
    });

    test('clear() でキャッシュが空になる', () async {
      final cache = LRUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('LRUCache - LRU エビクションのテスト', () {
    test('キャッシュが maxSize を超えたら LRU で削除される', () async {
      final cache = LRUCache<String, String>(2);

      // key1 と key2 を追加
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      // key1 をアクセスして最近使用された状態にする
      await cache.get('key1');

      // key3 を追加（key2 が削除されるはず）
      await cache.set('key3', 'value3');

      expect(await cache.get('key2'), isNull); // key2 は削除されたはず
      expect(await cache.get('key1'), equals('value1')); // key1 は残る
      expect(await cache.get('key3'), equals('value3')); // key3 は残る
    });

    test('同じキーを set し直すとそのキーが最新の位置に配置される', () async {
      final cache = LRUCache<String, String>(2);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key1', 'new_value1'); // key1 を再設定

      // key3 を追加（最も長く使用されていない key2 が削除される）
      await cache.set('key3', 'value3');

      expect(await cache.get('key2'), isNull); // key2 は削除されたはず
      expect(await cache.get('key1'), equals('new_value1')); // key1 は新しい値で残る
      expect(await cache.get('key3'), equals('value3')); // key3 は残る
    });
  });

  group('LRUCache - スレッドセーフ性のテスト', () {
    test('並列 set() / get() が安全に動作する', () async {
      final cache = LRUCache<int, String>(5);

      // 並列で 1000 回 set & get を実行
      final futures = List.generate(1000, (i) async {
        await cache.set(i % 5, 'value$i'); // key0 ~ key4 の値が更新され続ける
        return await cache.get(i % 5); // 値が取得できるか
      });

      await Future.wait(futures);

      // キャッシュに 5 件だけ残っていることを確認
      expect(cache.getKeys().length, equals(5));

      // key0 ~ key4 のいずれかがキャッシュに存在する
      final keys = cache.getKeys();
      expect(keys, containsAll([0, 1, 2, 3, 4]));
    });

    test('並列で clear() すると全て削除される', () async {
      final cache = LRUCache<String, String>(5);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3');

      await Future.wait([
        cache.clear(),
        cache.clear(),
        cache.clear(),
      ]);

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(await cache.get('key3'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('LRUCache - エラーハンドリング', () {
    test('maxSize が 0 以下の時に ArgumentError をスローする', () {
      expect(() => LRUCache<String, String>(0), throwsArgumentError);
      expect(() => LRUCache<String, String>(-1), throwsArgumentError);
    });
  });
}
