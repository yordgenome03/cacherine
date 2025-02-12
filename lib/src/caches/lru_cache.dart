import 'dart:collection';
import 'package:synchronized/synchronized.dart';

import '../interfaces/thread_safe_cache.dart';

/// **スレッドセーフな LRU（Least Recently Used）キャッシュ**
///
/// このクラスは [ThreadSafeCache] を継承し、**`Lock` を使用してスレッドセーフ性を確保** しています。
/// **複数スレッドや非同期タスクから安全にキャッシュへアクセス** でき、データ競合を防ぎます。
///
/// **LRU（最も長く使用されていないデータを削除する）方式のエビクションポリシーを採用** しており、
/// **キャッシュのサイズが `maxSize` を超えた場合、最も長く使用されていない要素を削除** します。
class LRUCache<K, V> extends ThreadSafeCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final _lock = Lock();

  /// 指定された最大サイズで [LRUCache] のインスタンスを作成します。
  ///
  /// - **[maxSize]**: キャッシュの最大サイズ。
  ///   このサイズを超えると、LRU ポリシーに基づき **最も長く使用されていない要素** から削除されます。
  ///
  /// **[maxSize] が 0 以下の場合、 [ArgumentError] をスローします。**
  LRUCache(this.maxSize) {
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
  /// - **LRU 方式を採用** しており、値を取得した際に **その要素をリストの末尾へ移動** します。
  /// - **キーが存在しない場合は `null` を返します。**
  ///
  /// **このメソッドはスレッドセーフです**。
  @override
  Future<V?> get(K key) async {
    return await _lock.synchronized(() {
      if (!_cache.containsKey(key)) return null;
      final value = _cache.remove(key);
      if (value == null) return null;
      _cache[key] = value; // LRU: アクセスした要素を末尾へ移動
      return value;
    });
  }

  /// 指定したキーと値をキャッシュに保存します。
  ///
  /// - すでに存在するキーに対して `set()` すると、**その値を更新** し、リストの末尾へ移動します。（LRUポリシー）
  /// - キャッシュのサイズが **[maxSize] を超えた場合、LRU ルールに基づき**
  ///   **最も長く使用されていない要素が削除** されます。
  ///
  /// **このメソッドはスレッドセーフです。**
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      if (_cache.containsKey(key)) {
        _cache.remove(key); // 既存のキーを削除し、新しい値を登録
      } else if (_cache.length >= maxSize) {
        _cache.remove(_cache.keys.first); // LRU に基づき最も古い要素を削除
      }
      _cache[key] = value;
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
