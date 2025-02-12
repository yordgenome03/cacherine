import 'dart:collection';

import '../interfaces/simple_cache.dart';

/// **非スレッドセーフな LFU（Least Frequently Used）キャッシュ**
///
/// **単一スレッド環境** での使用を想定した **LFU（最小使用頻度）方式** のキャッシュです。
/// - **最も使用頻度が低いアイテム** を削除する方式を採用。
/// - **スレッドセーフではないため、並行処理環境では `ThreadSafeLFUCache` を使用してください。**
///
/// ### **特徴**
/// - **キーごとのアクセス回数を記録** し、最小使用頻度のアイテムを削除
class SimpleLFUCache<K, V> extends SimpleCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final Map<K, int> _usageCounts = {};

  /// **指定された最大サイズで [SimpleLFUCache] のインスタンスを作成します。**
  ///
  /// - **[maxSize]**: キャッシュの最大サイズ。
  ///   このサイズを超えると、LFUポリシーに基づき **最も使用頻度の低いアイテム** から削除されます。
  ///
  /// **[maxSize] が 0 以下の場合、 [ArgumentError] をスローします。**
  SimpleLFUCache(this.maxSize) {
    if (maxSize <= 0) {
      throw ArgumentError('maxSize は 0 より大きい必要があります。');
    }
  }

  /// 現在キャッシュに格納されているすべてのキーを返します。
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  Iterable<K> getKeys() => _cache.keys;

  /// 指定したキーに対応する値を取得し、使用回数を増やします。
  ///
  /// - **キーが存在しない場合は `null` を返します。**
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  V? get(K key) {
    if (!_cache.containsKey(key)) return null;

    // 使用回数を増加
    _usageCounts[key] = (_usageCounts[key] ?? 0) + 1;
    return _cache[key];
  }

  /// 指定したキーと値をキャッシュに保存します。
  ///
  /// - 既存のキーに対して `set()` を呼び出すと、**その値を更新** しますが、**使用回数はリセットされません**。
  /// - キャッシュのサイズが **[maxSize]** を超えた場合、LFUポリシーに基づき、**最も使用頻度の低い要素が削除** されます。
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  void set(K key, V value) {
    if (_cache.length >= maxSize) {
      _evictLFUEntry(); // LFU方式でエビクション
    }
    _cache[key] = value;
    _usageCounts[key] = 1; // 初回は使用回数1とする
  }

  /// **LFU（最小使用頻度）方式でエビクション（削除）を行う**
  void _evictLFUEntry() {
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

  /// **キャッシュ内のすべてのデータをクリアします。**
  ///
  /// - キャッシュ内のすべてのキーと値を削除します。
  ///
  /// **このメソッドはスレッドセーフではありません。**
  @override
  void clear() {
    _cache.clear();
    _usageCounts.clear();
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
