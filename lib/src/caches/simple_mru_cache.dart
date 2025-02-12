import 'dart:collection';
import '../interfaces/simple_cache.dart';

/// **非スレッドセーフな MRU（Most Recently Used）キャッシュ**
///
/// **単一スレッド環境** での使用を想定した **MRU（最も最近使用された）方式** のキャッシュです。
/// - **最も最近使用されたアイテムを削除する方式を採用。**
/// - **スレッドセーフではないため、並行処理環境では `MRUCache` を使用してください。**
///
/// ### **特徴**
/// - **キーの取得時にアクセス履歴を更新。**
/// - **キャッシュが最大サイズを超えた場合、最も最近使用されたアイテムを削除。**
class SimpleMRUCache<K, V> extends SimpleCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();

  /// **指定された最大サイズで [SimpleMRUCache] のインスタンスを作成します。**
  ///
  /// - **[maxSize]**: キャッシュの最大サイズ。
  ///   このサイズを超えると、MRUポリシーに基づき **最も最近使用されたアイテム** から削除されます。
  ///
  /// **[maxSize] が 0 以下の場合、 [ArgumentError] をスローします。**
  SimpleMRUCache(this.maxSize) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize は 0 より大きい必要があります。');
    }
  }

  /// **キャッシュに格納されているすべてのキーを取得する。**
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  Iterable<K> getKeys() => _cache.keys;

  /// **指定したキーに対応する値を取得する。**
  ///
  /// - キーが存在する場合、そのキーを削除して再追加することで **「最近使用された」とマーク** する。
  /// - **キーが存在しない場合は `null` を返す。**
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  V? get(K key) {
    if (!_cache.containsKey(key)) return null;

    // MRUのため、キーを削除し、再追加する（最も最近使用されたことを記録）
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value;
    }
    return value;
  }

  /// **指定したキーと値をキャッシュに保存する。**
  ///
  /// - 既存のキーに対して `set()` を呼び出すと、**その値を更新** しますが、**順番は変更されません**。
  /// - キャッシュのサイズが **[maxSize]** を超えた場合、MRUポリシーに基づき、**最も最近使用された要素が削除** されます。
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  void set(K key, V value) {
    if (_cache.length >= maxSize) {
      _evictMRUEntry(); // MRU方式でエビクション
    }
    _cache[key] = value;
  }

  /// **MRU（最も最近使用された）方式でエビクション（削除）を行う**
  void _evictMRUEntry() {
    if (_cache.isEmpty) return;

    // 最後に追加されたキー（最近使用されたキー）を削除
    final K mruKey = _cache.keys.last;
    _cache.remove(mruKey);
  }

  /// **キャッシュ内のすべてのデータをクリアします。**
  ///
  /// - キャッシュ内のすべてのキーと値を削除します。
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  void clear() {
    _cache.clear();
  }

  /// **キャッシュの現在の状態を文字列で返します。**
  ///
  /// - キャッシュ内に格納されている **キーと値のペア** を文字列形式で出力します。
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  String toString() {
    return _cache.toString();
  }
}
