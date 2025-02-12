import 'dart:collection';
import 'package:synchronized/synchronized.dart';

import '../interfaces/thread_safe_cache.dart';

/// **スレッドセーフな LFU（Least Frequently Used）キャッシュ**
///
/// このクラスは [ThreadSafeCache] を継承し、**`Lock` を使用してスレッドセーフ性を確保** しています。
/// **複数スレッドや非同期タスクから安全にキャッシュへアクセス** でき、データ競合を防ぎます。
///
/// **LFU（最小使用頻度）方式のエビクション（削除）ポリシーを採用** しており、
/// **キャッシュのサイズが `maxSize` を超えた場合、最も使用頻度の低い要素を削除** します。
class LFUCache<K, V> extends ThreadSafeCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final Map<K, int> _usageCounts = {};
  final _lock = Lock();

  /// **指定された最大サイズで [LFUCache] のインスタンスを作成します。**
  ///
  /// - **[maxSize]**: キャッシュの最大サイズ。
  ///   このサイズを超えると、LFU ポリシーに基づき **最も使用頻度の低いアイテム** から削除されます。
  ///
  /// **[maxSize] が 0 以下の場合、 [ArgumentError] をスローします。**
  LFUCache(this.maxSize) {
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

  /// 指定したキーに対応する値を取得し、使用回数を増やします。
  ///
  /// - **キーが存在しない場合は `null` を返します。**
  ///
  /// **このメソッドはスレッドセーフです**。
  @override
  Future<V?> get(K key) async {
    return await _lock.synchronized(() {
      if (!_cache.containsKey(key)) return null;

      // 使用回数を増加
      _usageCounts[key] = (_usageCounts[key] ?? 0) + 1;
      return _cache[key];
    });
  }

  /// 指定したキーと値をキャッシュに保存します。
  ///
  /// - 既存のキーに対して `set()` を呼び出すと、**その値を更新** しますが、**使用回数はリセットされません**。
  /// - キャッシュのサイズが **[maxSize]** を超えた場合、LFUポリシーに基づき、**最も使用頻度の低い要素が削除** されます。
  ///
  /// **このメソッドはスレッドセーフです**。
  @override
  Future<void> set(K key, V value) async {
    await _lock.synchronized(() {
      if (_cache.length >= maxSize) {
        _evictLFUEntry(); // LFU方式でエビクション
      }
      _cache[key] = value;
      _usageCounts[key] = 1; // 初回は使用回数1とする
    });
  }

  /// LFU（最小使用頻度）方式でエビクション（削除）を行う
  Future<void> _evictLFUEntry() async {
    if (_cache.isEmpty) return;

    // 最小使用回数のキーを取得
    final K lfuKey = _usageCounts.entries
        .reduce(
          (a, b) => a.value < b.value ? a : b,
        )
        .key;

    // キーを削除
    _cache.remove(lfuKey);
    _usageCounts.remove(lfuKey);
  }

  /// キャッシュをクリアし、すべてのデータを削除します。
  ///
  /// **このメソッドはスレッドセーフです**。
  @override
  Future<void> clear() async {
    await _lock.synchronized(() {
      _cache.clear();
      _usageCounts.clear();
    });
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
