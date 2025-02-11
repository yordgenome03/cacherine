import 'package:test/test.dart';
import 'package:cacherine/src/caches/simple_lfu_cache.dart';

void main() {
  group('SimpleLFUCache - 基本動作', () {
    test('空のキャッシュから get() すると null を返す', () {
      final cache = SimpleLFUCache<String, String>(3);
      expect(cache.get('key1'), isNull);
    });

    test('set() したデータが get() で取得できる', () {
      final cache = SimpleLFUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      expect(cache.get('key1'), equals('value1'));
      expect(cache.get('key2'), equals('value2'));
    });

    test('clear() でキャッシュが空になる', () {
      final cache = SimpleLFUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.clear();

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('SimpleLFUCache - LFU エビクションのテスト', () {
    test('キャッシュが maxSize を超えたら LFU で削除される', () {
      final cache = SimpleLFUCache<String, String>(2);

      // まずは key1 と key2 を追加
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      // key1 を1回getして使用回数を増やす
      cache.get('key1');

      // key3 を追加してキャッシュサイズを超える
      cache.set('key3', 'value3'); // key2 が最も使用されていないため削除される

      // key2 が削除されたか確認
      expect(cache.get('key2'), isNull); // key2 は削除されたはず
      expect(cache.get('key1'), equals('value1')); // key1 は使用頻度が高いので残る
      expect(cache.get('key3'), equals('value3')); // key3 は新しく追加されたので残る
    });

    test('同じキーを set し直すとそのキーが最新の位置に配置される', () {
      final cache = SimpleLFUCache<String, String>(2);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key1', 'new_value1'); // key1 は最も新しい位置に配置される

      cache.set('key3', 'value3'); // 最も使用頻度が低い 'key2' が削除される

      expect(cache.get('key2'), isNull); // key2 は削除されたはず
      expect(cache.get('key1'), equals('new_value1')); // key1 は最新の値で残っているはず
      expect(cache.get('key3'), equals('value3')); // key3 は新しく追加されたので残っているはず
    });
  });

  group('SimpleLFUCache - エラーハンドリング', () {
    test('maxSize が 0 以下の時に ArgumentError をスローする', () {
      expect(() => SimpleLFUCache<String, String>(0), throwsArgumentError);
      expect(() => SimpleLFUCache<String, String>(-1), throwsArgumentError);
    });
  });
}
