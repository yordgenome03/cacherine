import 'dart:collection';
import 'package:synchronized/synchronized.dart';

import '../interfaces/thread_safe_cache.dart';

/// **スレッドセーフな FIFO（First In, First Out）キャッシュ**
///
/// このクラスは [ThreadSafeCache] を継承し、**`Lock` を使用してスレッドセーフ性を確保** しています。
/// **複数スレッドや非同期タスクから安全にキャッシュへアクセス** でき、データ競合を防ぎます。
///
/// **FIFO 方式のエビクション（削除）ポリシーを採用** しており、
/// **キャッシュのサイズが `maxSize` を超えた場合、最も古い要素を削除** します。
class FIFOCache<K, V> extends ThreadSafeCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final _lock = Lock();

  /// **指定された最大サイズで [FIFOCache] のインスタンスを作成します。**
  ///
  /// - **[maxSize]**: キャッシュの最大サイズ。
  ///   このサイズを超えると、FIFO ポリシーに基づき **最も古い要素** から削除されます。
  ///
  /// **[maxSize] が 0 以下の場合、 [ArgumentError] をスローします。**
  FIFOCache(this.maxSize) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize は 0 より大きい必要があります。');
    }
  }

  /// 現在キャッシュに格納されているすべてのキーを返します。
  ///
  /// **このメソッドはスレッドセーフです**。
  @override
  Iterable<K> getKeys() {
    return Map<K, V>.of(_cache).keys;
  }

  /// 指定したキーに対応する値を取得します。
  ///
  /// - FIFO 方式では **データの優先順位は変更されません**（`get()` しても削除順は変わらない）。
  /// - **キーが存在しない場合は `null` を返します。**
  ///
  /// **このメソッドはスレッドセーフです**。
  @override
  Future<V?> get(K key) async {
    return await _lock.synchronized(() {
      return _cache[key];
    });
  }

  /// 指定したキーと値をキャッシュに保存します。
  ///
  /// - 既存のキーに対して `set()` を呼び出すと、**その値を更新** します。
  /// - 更新されたキーは、**最も新しいデータ** として扱われ、順番が更新されます。
  /// - キャッシュのサイズが **[maxSize]** を超えた場合、FIFOポリシーに基づき、**最も古い要素が削除** されます。
  ///
  /// **このメソッドはスレッドセーフです**。
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      if (_cache.length >= maxSize) {
        _cache.remove(_cache.keys.first); // FIFO に基づき最も古い要素を削除
      }
      _cache[key] = value; // 値の更新（最も新しい順番）
    });
  }

  /// キャッシュ内のすべてのデータをクリアします。
  ///
  /// - キャッシュ内のすべてのキーと値を削除します。
  ///
  /// **このメソッドはスレッドセーフです**。
  @override
  Future<void> clear() async {
    await _lock.synchronized(_cache.clear);
  }

  /// キャッシュの現在の状態を文字列で返します。
  ///
  /// - キャッシュ内に格納されている **キーと値のペア** を文字列形式で出力します。
  ///
  /// **このメソッドはスレッドセーフです**。
  @override
  String toString() {
    final snapshot = Map.of(_cache); // キャッシュのスナップショットを取得
    return snapshot.toString();
  }
}
