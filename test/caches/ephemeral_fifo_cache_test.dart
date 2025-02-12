import 'package:test/test.dart';
import 'package:cacherine/src/caches/ephemeral_fifo_cache.dart';

void main() {
  group('EphemeralFIFOCache - 基本動作', () {
    test('空のキャッシュから get() すると null を返す', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      expect(await cache.get('key1'), isNull);
    });

    test('set() したデータが get() で取得できる', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      expect(await cache.get('key1'), equals('value1'));
    });

    test('get() で取得したデータはキャッシュから削除される', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      expect(await cache.get('key1'), equals('value1'));
      expect(await cache.get('key1'), isNull); // 取得後は削除されている
    });

    test('clear() でキャッシュが空になる', () async {
      final cache = EphemeralFIFOCache<String, String>(3);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.clear();

      expect(await cache.get('key1'), isNull);
      expect(await cache.get('key2'), isNull);
      expect(cache.getKeys(), isEmpty);
    });
  });

  group('EphemeralFIFOCache - FIFO エビクションのテスト', () {
    test('キャッシュが maxSize を超えたら FIFO で削除される', () async {
      final cache = EphemeralFIFOCache<String, String>(2);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key3', 'value3'); // key1 が削除される（FIFO）

      expect(await cache.get('key1'), isNull); // key1 は削除されたはず
      expect(await cache.get('key2'), equals('value2'));
      expect(await cache.get('key3'), equals('value3'));
    });

    test('同じキーを set() しても順番は変更されない', () async {
      final cache = EphemeralFIFOCache<String, String>(2);
      await cache.set('key1', 'value1');
      await cache.set('key2', 'value2');
      await cache.set('key1', 'new_value1'); // key1 は最も新しい位置に配置される

      await cache.set('key3', 'value3'); // 最も古い key2 が削除される

      expect(await cache.get('key2'), isNull); // key2 は削除されたはず
      expect(await cache.get('key1'), equals('new_value1'));
      expect(await cache.get('key3'), equals('value3'));
    });
  });

  group('EphemeralFIFOCache - スレッドセーフ性のテスト', () {
    test('並列 set() / get() が安全に動作する', () async {
      final cache = EphemeralFIFOCache<int, String>(5);

      // 並列で 1000 回 set & get を実行
      final futures = List.generate(1000, (i) async {
        await cache.set(i % 5, 'value$i'); // key0 ~ key4 の値が更新され続ける
        return await cache.get(i % 5); // 値が取得できるか（取得と同時にその値は削除される）
      });

      // すべての非同期処理が完了するのを待つ
      await Future.wait(futures);

      // キャッシュに値が残っていないことを確認
      expect(cache.getKeys().isEmpty, isTrue);
    });

    test('並列で clear() すると全て削除される', () async {
      final cache = EphemeralFIFOCache<String, String>(5);
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

    test('並列処理中に toString() を呼び出してもエラーにならない', () async {
      final cache = EphemeralFIFOCache<int, String>(5);
      await cache.set(1, 'value1');
      await cache.set(2, 'value2');
      await cache.set(3, 'value3');

      // 並列で get() と toString() を呼び出す
      final futures = List.generate(1000, (i) async {
        await cache.get(i % 3);
        return cache.toString();
      });

      final results = await Future.wait(futures);
      expect(results.length, equals(1000)); // すべての toString() が正常に動作
    });
  });

  group('EphemeralFIFOCache - エラーハンドリング', () {
    test('maxSize が 0 以下の時に ArgumentError をスローする', () {
      expect(() => EphemeralFIFOCache<String, String>(0), throwsArgumentError);
      expect(() => EphemeralFIFOCache<String, String>(-1), throwsArgumentError);
    });
  });
}
