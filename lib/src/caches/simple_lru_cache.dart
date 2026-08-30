import '../interfaces/simple_cache.dart';
import '../stores/lru_store.dart';
import 'cache.dart';

/// **Non-thread-safe LRU (Least Recently Used) Cache**
///
/// This class is designed for use in **single-threaded environments**
/// or scenarios where **concurrent access is not required**.
/// Since it is not thread-safe and does not perform synchronization,
/// **use `LRUCache` if thread safety is needed.**
///
/// It follows the LRU (Least Recently Used) eviction policy,
/// meaning **when the cache exceeds `maxSize`, the least recently used element is removed**.
///
/// Wraps a [Cache] configured with an [LRUStore] — internally a composed
/// engine rather than a subclass, so this class keeps its original
/// `set`/`getOrSet`/`update`/`setAll` signatures (no `weight`/`ttl`
/// parameters) rather than inheriting [Cache]'s wider ones.
class SimpleLRUCache<K, V> extends SimpleCache<K, V> {
  final Cache<K, V> _engine;

  /// Creates an instance of [SimpleLRUCache] with the specified maximum size.
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, the **least recently used element** is removed following the LRU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleLRUCache(int maxSize)
    : _engine = Cache(store: LRUStore<K, V>(), maxSize: maxSize);

  /// The maximum number of entries in the cache.
  int get maxSize => _engine.maxSize!;

  @override
  Iterable<K> getKeys() => _engine.getKeys();

  @override
  V? get(K key) => _engine.get(key);

  @override
  Map<K, V> getAll(Iterable<K> keys) => _engine.getAll(keys);

  @override
  V? peek(K key) => _engine.peek(key);

  @override
  bool containsKey(K key) => _engine.containsKey(key);

  @override
  void set(K key, V value) => _engine.set(key, value);

  @override
  void setAll(Map<K, V> entries) => _engine.setAll(entries);

  @override
  V getOrSet(K key, V Function() valueFactory) =>
      _engine.getOrSet(key, valueFactory);

  @override
  V update(K key, V Function(V value) update, {V Function()? ifAbsent}) =>
      _engine.update(key, update, ifAbsent: ifAbsent);

  @override
  void remove(K key) => _engine.remove(key);

  @override
  void removeWhere(bool Function(K key, V value) test) =>
      _engine.removeWhere(test);

  @override
  void clear() => _engine.clear();

  @override
  String toString() => _engine.toString();
}
