import 'package:test/test.dart';
import 'package:cacherine/src/caches/lfu_cache.dart';

void main() {
  group('LFUCache - 基本動作', () {
    test('空のキャッシュから get() すると null を返す', () async {
      final cache = LFUCache<String, String>(3);
      expect(await cache.get('key1'), isNull);
    });

    test('set() したデータが get() で取得できる', () async {
      final cache = LFUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.get('key2'), equals('value2'));
    });

    test('clear() でキャッシュが空になる', () async {
      final cache = LFUCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('LFUCache - LFU エビクションのテスト', () {
    test('キャッシュが maxSize を超えたら LFU で削除される', () async {
      final cache = LFUCache<String, String>(2);

      // key1, key2 を追加
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');

      // key1 の使用回数を増やす
      await cache.get('key1');

      // key3 を追加して maxSize を超える
      await cache.set('key3', 'value3'); // key2 が削除される（使用回数が低いため）

      expect(await cache.get('key2'), isNull); // key2 は削除されたはず
      expect(await cache.get('key1'), equals('value1')); // key1 は使用頻度が高いので残る
      expect(await cache.get('key3'), equals('value3')); // key3 は新しく追加されたので残る
    });
  });

  group('LFUCache - スレッドセーフ性のテスト', () {
    test('並列 set() / get() が安全に動作する', () async {
      final cache = LFUCache<int, String>(5);

      // 並列で 1000 回 set & get を実行
      final futures = List.generate(1000, (i) async {
        await cache.set(i % 5, 'value$i'); // key0 ~ key4 の値が更新され続ける
        return await cache.get(i % 5);
      });

      await Future.wait(futures);
      expect(cache.getKeys().length, lessThanOrEqualTo(5));
    });

    test('並列 clear() でキャッシュが完全にクリアされる', () async {
      final cache = LFUCache<String, String>(5);
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

  group('LFUCache - エラーハンドリング', () {
    test('maxSize が 0 以下の時に ArgumentError をスローする', () {
      expect(() => LFUCache<String, String>(0), throwsArgumentError);
      expect(() => LFUCache<String, String>(-1), throwsArgumentError);
    });
  });
}
