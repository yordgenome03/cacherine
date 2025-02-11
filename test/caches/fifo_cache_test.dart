import 'package:cacherine/src/caches/fifo_cache.dart';
import 'package:test/test.dart';

void main() {
  group('FIFOCache - 基本動作', () {
    test('空のキャッシュから get() すると null を返す', () async {
      final cache = FIFOCache<String, String>(3);
      expect(await cache.get('key1'), isNull);
    });

    test('set() したデータが get() で取得できる', () async {
      final cache = FIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.get('key2'), equals('value2'));
    });

    test('clear() でキャッシュが空になる', () async {
      final cache = FIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });

    test('getKeys() の動作（現在のキーを正しく返す）', () async {
      final cache = FIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3');

      expect(cache.getKeys(), containsAll(['key1', 'key2', 'key3']));

      await cache.set('key4', 'value4'); // 'key1' が削除される
      expect(cache.getKeys(), containsAll(['key2', 'key3', 'key4']));
      expect(cache.getKeys(), isNot(contains('key1'))); // 'key1' は削除済み
    });

    test('キャッシュの文字列表現（toString() のテスト）', () async {
      final cache = FIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3');

      final cacheString = cache.toString();
      expect(cacheString, contains('key1: value1'));
      expect(cacheString, contains('key2: value2'));
      expect(cacheString, contains('key3: value3'));
    });
  });

  group('FIFOCache - FIFO エビクションのテスト', () {
    test('キャッシュが maxSize を超えたら FIFO で削除される', () async {
      final cache = FIFOCache<String, String>(2);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3'); // key1 は削除される

      expect(await cache.get('key1'), isNull); // 削除されたはず
      expect(await cache.get('key2'), equals('value2'));
      expect(await cache.get('key3'), equals('value3'));
    });

    test('同じキーを set し直しても順番は変更されない', () async {
      final cache = FIFOCache<String, String>(2);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key1', 'new_value1'); // 順番は変更されない

      await cache.set('key3', 'value3'); // key2 が削除される（FIFO のまま）

      expect(await cache.get('key2'), isNull); // key2 は削除されているはず
      expect(
          await cache.get('key1'), equals('new_value1')); // key1 は新しい値で残っているはず
      expect(await cache.get('key3'), equals('value3')); // key3 はセットされているはず
    });
  });

  group('FIFOCache - スレッドセーフ性のテスト', () {
    test('並列 set() / get() が安全に動作する', () async {
      final cache = FIFOCache<int, String>(5);

      // 並列で 1000 回 set & get を実行
      final futures = List.generate(1000, (i) async {
        await cache.set(i % 5, 'value$i'); // key0 ~ key4 の値が更新され続ける
        return await cache.get(i % 5); // 値が取得できるか
      });

      // すべての非同期処理が完了するのを待つ
      await Future.wait(futures);

      // キャッシュに 5 件だけ残っていることを確認
      expect(cache.getKeys().length, equals(5));

      // key0 ~ key4 のいずれかがキャッシュに存在する
      final keys = cache.getKeys();
      expect(keys, containsAll([0, 1, 2, 3, 4]));
    });

    test('並列で clear() すると全て削除される', () async {
      final cache = FIFOCache<String, String>(5);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3');

      // 並列で clear() を実行
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

  group('FIFOCache - エラーハンドリング', () {
    test('maxSize が 0 以下の時に ArgumentError をスローする', () {
      expect(() => FIFOCache<String, String>(0), throwsArgumentError);
      expect(() => FIFOCache<String, String>(-1), throwsArgumentError);
    });
  });
}
