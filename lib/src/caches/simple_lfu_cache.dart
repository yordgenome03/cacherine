import '../interfaces/simple_cache.dart';
import '../stores/lfu_store.dart';
import 'cache.dart';

/// **Non-thread-safe LFU (Least Frequently Used) Cache**
///
/// This class is designed for use in **single-threaded environments**
/// or scenarios where **concurrent access is not required**.
/// Since it is not thread-safe and does not perform synchronization,
/// **use `LFUCache` if thread safety is needed.**
///
/// It follows the LFU (Least Frequently Used) eviction policy,
/// meaning **when the cache exceeds `maxSize`, the least frequently used item is removed.**
///
/// Wraps a [Cache] configured with an [LFUStore] — internally a composed
/// engine rather than a subclass, so this class keeps its original
/// `set`/`getOrSet`/`update`/`setAll` signatures (no `weight`/`ttl`
/// parameters) rather than inheriting [Cache]'s wider ones. Only the
/// primitive operations ([getKeys], [get], [peek], [containsKey], [set],
/// [remove], [clear]) forward to the engine directly; bulk/compound helpers
/// ([getAll], [setAll], [getOrSet], [update], [removeWhere]) are left to
/// [SimpleCache]'s default implementations, which call this class's own
/// (overridable) methods — so a subclass overriding, say, [set] still has
/// that override invoked by [setAll]/[update]/etc.
class SimpleLFUCache<K, V> extends SimpleCache<K, V> {
  final Cache<K, V> _engine;

  /// **Creates an instance of [SimpleLFUCache] with the specified maximum size.**
  ///
  /// - **[maxSize]**: The maximum number of entries in the cache.
  ///   If the cache exceeds this size, the **least frequently used item** is removed following the LFU policy.
  ///
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleLFUCache(int maxSize)
    : _engine = Cache(store: LFUStore<K, V>(), maxSize: maxSize);

  /// The maximum number of entries in the cache.
  int get maxSize => _engine.maxSize!;

  @override
  Iterable<K> getKeys() => _engine.getKeys();

  @override
  V? get(K key) => _engine.get(key);

  @override
  V? peek(K key) => _engine.peek(key);

  @override
  bool containsKey(K key) => _engine.containsKey(key);

  @override
  void set(K key, V value) => _engine.set(key, value);

  @override
  void remove(K key) => _engine.remove(key);

  @override
  void clear() => _engine.clear();

  @override
  String toString() => _engine.toString();
}
