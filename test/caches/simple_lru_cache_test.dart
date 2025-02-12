import 'package:test/test.dart';
import 'package:cacherine/src/caches/simple_lru_cache.dart';

void main() {
  group('SimpleLRUCache - 基本動作', () {
    test('空のキャッシュから get() すると null を返す', () {
      final cache = SimpleLRUCache<String, String>(3);
      expect(cache.get('key1'), isNull);
    });

    test('set() したデータが get() で取得できる', () {
      final cache = SimpleLRUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      expect(cache.get('key1'), equals('value1'));
      expect(cache.get('key2'), equals('value2'));
    });

    test('clear() でキャッシュが空になる', () {
      final cache = SimpleLRUCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.clear();

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('SimpleLRUCache - LRU エビクションのテスト', () {
    test('キャッシュが maxSize を超えたら LRU で削除される', () {
      final cache = SimpleLRUCache<String, String>(2);

      // key1 と key2 を追加
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      // key1 を使ってアクセス回数を増やす
      cache.get('key1');

      // key3 を追加してキャッシュサイズを超える
      cache.set('key3', 'value3'); // key2 は最も長く使用されていないため削除される

      // key2 が削除されたか確認
      expect(cache.get('key2'), isNull); // key2 は削除されたはず
      expect(cache.get('key1'), equals('value1')); // key1 は使用されているので残る
      expect(cache.get('key3'), equals('value3')); // key3 は新しく追加されたので残る
    });

    test('同じキーを set し直すとそのキーが最新の位置に配置される', () {
      final cache = SimpleLRUCache<String, String>(2);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key1', 'new_value1'); // key1 は最も新しい位置に配置される

      cache.set('key3', 'value3'); // 最も長く使用されていない 'key2' が削除される

      expect(cache.get('key2'), isNull); // key2 は削除されたはず
      expect(cache.get('key1'), equals('new_value1')); // key1 は最新の値で残っているはず
      expect(cache.get('key3'), equals('value3')); // key3 は新しく追加されたので残っているはず
    });
  });

  group('SimpleLRUCache - エラーハンドリング', () {
    test('maxSize が 0 以下の時に ArgumentError をスローする', () {
      expect(() => SimpleLRUCache<String, String>(0), throwsArgumentError);
      expect(() => SimpleLRUCache<String, String>(-1), throwsArgumentError);
    });
  });
}
