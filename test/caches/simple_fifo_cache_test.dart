import 'package:test/test.dart';
import 'package:cacherine/src/caches/simple_fifo_cache.dart';

void main() {
  group('SimpleFIFOCache - 基本動作', () {
    test('空のキャッシュから get() すると null を返す', () {
      final cache = SimpleFIFOCache<String, String>(3);
      expect(cache.get('key1'), isNull);
    });

    test('set() したデータが get() で取得できる', () {
      final cache = SimpleFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');

      expect(cache.get('key1'), equals('value1'));
      expect(cache.get('key2'), equals('value2'));
    });

    test('clear() でキャッシュが空になる', () {
      final cache = SimpleFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.clear();

      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('SimpleFIFOCache - FIFO エビクションのテスト', () {
    test('キャッシュが maxSize を超えたら FIFO で削除される', () {
      final cache = SimpleFIFOCache<String, String>(2);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key3', 'value3'); // key1 は削除される

      expect(cache.get('key1'), isNull); // 削除されたはず
      expect(cache.get('key2'), equals('value2'));
      expect(cache.get('key3'), equals('value3'));
    });

    test('同じキーを set し直すとそのキーが最新の位置に配置される', () {
      final cache = SimpleFIFOCache<String, String>(2);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key1', 'new_value1'); // key1 は最も新しい位置に配置される

      cache.set('key3', 'value3'); // 最も古い key2 が削除される

      expect(cache.get('key2'), isNull); // key2 は削除されたはず
      expect(cache.get('key1'), equals('new_value1'));
      expect(cache.get('key3'), equals('value3'));
    });
  });

  group('SimpleFIFOCache - 追加の動作検証', () {
    test('maxSize=1 の動作（常に最新の1つだけ保持）', () {
      final cache = SimpleFIFOCache<String, String>(1);
      cache.set('key1', 'value1');
      expect(cache.get('key1'), equals('value1'));

      cache.set('key2', 'value2'); // 'key1' が削除され、'key2' だけが残る
      expect(cache.get('key1'), isNull);
      expect(cache.get('key2'), equals('value2'));
    });

    test('存在しないキーの取得（null が返る）', () {
      final cache = SimpleFIFOCache<String, String>(3);
      expect(cache.get('non_existing_key'), isNull);
    });

    test('getKeys() の動作（現在のキーを正しく返す）', () {
      final cache = SimpleFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key3', 'value3');

      expect(cache.getKeys(), containsAll(['key1', 'key2', 'key3']));

      cache.set('key4', 'value4'); // 'key1' が削除される
      expect(cache.getKeys(), containsAll(['key2', 'key3', 'key4']));
      expect(cache.getKeys(), isNot(contains('key1'))); // 'key1' は削除済み
    });

    test('キャッシュの文字列表現（toString() のテスト）', () {
      final cache = SimpleFIFOCache<String, String>(3);
      cache.set('key1', 'value1');
      cache.set('key2', 'value2');
      cache.set('key3', 'value3');

      final cacheString = cache.toString();
      expect(cacheString, contains('key1: value1'));
      expect(cacheString, contains('key2: value2'));
      expect(cacheString, contains('key3: value3'));
    });
  });

  group('SimpleFIFOCache - エラーハンドリング', () {
    test('maxSize が 0 以下の時に ArgumentError をスローする', () {
      expect(() => SimpleFIFOCache<String, String>(0), throwsArgumentError);
      expect(() => SimpleFIFOCache<String, String>(-1), throwsArgumentError);
    });
  });
}
