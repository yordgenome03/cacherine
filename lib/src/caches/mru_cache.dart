import 'dart:collection';
import 'package:synchronized/synchronized.dart';

import '../interfaces/thread_safe_cache.dart';

/// **スレッドセーフな MRU（Most Recently Used）キャッシュ**
///
/// **複数スレッドや非同期タスクから安全にキャッシュへアクセス** できるように、
/// `Lock` を使用してスレッドセーフ性を確保しています。
///
/// **MRU 方式（最も最近使用されたアイテムを削除）** を採用しており、
/// **キャッシュのサイズが `maxSize` を超えた場合、直近でアクセスされた要素を削除** します。
class MRUCache<K, V> extends ThreadSafeCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final _lock = Lock();

  /// **指定された最大サイズで [MRUCache] のインスタンスを作成します。**
  ///
  /// - **[maxSize]**: キャッシュの最大サイズ。
  ///   このサイズを超えると、MRU ポリシーに基づき **最も最近使用された要素** が削除されます。
  ///
  /// **[maxSize] が 0 以下の場合、 [ArgumentError] をスローします。**
  MRUCache(this.maxSize) {
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

  /// **指定したキーに対応する値を取得します。**
  ///
  /// - **キーが存在する場合、そのキーを削除し、再追加することで「最近使用された」とマーク** します。
  /// - **キーが存在しない場合は `null` を返します。**
  ///
  /// **このメソッドはスレッドセーフです**。
  @override
  Future<V?> get(K key) async {
    return await _lock.synchronized(() {
      if (!_cache.containsKey(key)) return null;

      final value = _cache.remove(key);
      if (value != null) {
        _cache[key] = value; // MRU: 再追加して「最近使用された」ことを記録
      }
      return value;
    });
  }

  /// **指定したキーと値をキャッシュに保存します。**
  ///
  /// - 既存のキーに対して `set()` を呼び出すと、**その値を更新** しますが、**順番は変更されません**。
  /// - キャッシュのサイズが **[maxSize]** を超えた場合、MRUポリシーに基づき、**最も最近使用された要素が削除** されます。
  ///
  /// **このメソッドはスレッドセーフです**。
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      if (_cache.length >= maxSize) {
        _evictMRUEntry(); // MRU方式でエビクション
      }
      _cache[key] = value;
    });
  }

  /// **MRU（最も最近使用された）方式でエビクション（削除）を行う**
  Future<void> _evictMRUEntry() async {
    if (_cache.isEmpty) return;

    // 最後に追加されたキー（最近使用されたキー）を削除
    final K mruKey = _cache.keys.last;
    _cache.remove(mruKey);
  }

  /// キャッシュをクリアし、すべてのデータを削除します。
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
