import 'dart:collection';

import '../interfaces/simple_cache.dart';

/// **非スレッドセーフな FIFO（First In, First Out）キャッシュ**
///
/// このクラスは **単一スレッド環境** や **並行アクセスが不要な場面** での使用を想定しています。
/// スレッドセーフではなく、同期処理も行わないため、
/// **スレッドセーフな実装が必要な場合は `ThreadSafeFIFOCache` を使用してください。**
///
/// FIFO 方式のエビクション（削除）ポリシーを採用しており、
/// **キャッシュのサイズが `maxSize` を超えた場合、最も古い要素を削除** します。
class SimpleFIFOCache<K, V> extends SimpleCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();

  /// 指定された最大サイズで [SimpleFIFOCache] のインスタンスを作成します。
  ///
  /// - **[maxSize]**: キャッシュの最大サイズ。
  ///   このサイズを超えると、FIFO ポリシーに基づき **最も古い要素** から削除されます。
  ///
  /// **[maxSize] が 0 以下の場合、 [ArgumentError] をスローします。**
  SimpleFIFOCache(this.maxSize) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize は 0 より大きい必要があります。');
    }
  }

  /// キャッシュに現在格納されているすべてのキーを返します。
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  Iterable<K> getKeys() => _cache.keys;

  /// 指定したキーに対応する値を取得します。
  ///
  /// - FIFO 方式では **データの優先順位は変更されません**（`get()` しても削除順は変わらない）。
  /// - **キーが存在しない場合は `null` を返します。**
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  V? get(K key) {
    return _cache[key];
  }

/// 指定したキーと値をキャッシュに保存します。
///
/// - 既存のキーに対して `set()` を呼び出すと、**その値を更新** します。
/// - 更新されたキーは、**最も新しいデータ** として扱われ、順番が更新されます。
/// - キャッシュのサイズが **[maxSize]** を超えた場合、FIFOポリシーに基づき、**最も古い要素が削除** されます。
///
/// **このメソッドはスレッドセーフではありません。**
 @override
  void set(K key, V value) {
    if (_cache.length >= maxSize) {
      _cache.remove(_cache.keys.first); // FIFO に基づき最も古い要素を削除
    }
    _cache[key] = value; // 値の更新（順番変更なし）
  }

  /// キャッシュ内のすべてのデータをクリアします。
  ///
  /// - キャッシュ内のすべてのキーと値を削除します。
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  void clear() {
    _cache.clear();
  }

  /// キャッシュの現在の状態を文字列で返します。
  ///
  /// - キャッシュ内に格納されている **キーと値のペア** を文字列形式で出力します。
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  String toString() {
    return _cache.toString();
  }
}
