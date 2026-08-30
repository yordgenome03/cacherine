import '../interfaces/simple_ttl_cache.dart';
import '../stores/ttl_fifo_store.dart';
import 'cache.dart';

/// **Non-thread-safe TTL (Time-To-Live) Cache**
///
/// Entries are automatically treated as absent once their TTL has elapsed.
/// Expiry is checked lazily on [get] and [containsKey].
///
/// This class is designed for use in **single-threaded environments**
/// or scenarios where **concurrent access is not required**.
/// Since it is not thread-safe and does not perform synchronization,
/// **use `TTLCache` if async-safe access is needed.**
///
/// Wraps a [Cache] configured with a [TTLFifoStore] — internally a composed
/// engine rather than a subclass, so this class can keep extending
/// [SimpleTTLCacheInterface] for backward compatibility.
class SimpleTTLCache<K, V> extends SimpleTTLCacheInterface<K, V> {
  final Cache<K, V> _engine;

  /// Creates a [SimpleTTLCache].
  ///
  /// - [ttl]: Default expiry duration for all entries stored via [set].
  /// - [maxSize]: Optional capacity limit; the oldest-inserted live entry is
  ///   evicted (FIFO) when the limit is exceeded.
  /// - [clock]: Injectable time source for testing; defaults to [DateTime.now].
  ///
  /// **Throws [ArgumentError] if [ttl] is zero or negative.**
  /// **Throws [ArgumentError] if [maxSize] is 0 or less.**
  SimpleTTLCache({
    required Duration ttl,
    int? maxSize,
    DateTime Function()? clock,
  }) : _engine = Cache(
         store: TTLFifoStore<K, V>(),
         maxSize: maxSize,
         ttl: ttl,
         clock: clock,
       );

  /// Returns all non-expired keys currently stored in the cache.
  ///
  /// **This method is not thread-safe.**
  @override
  Iterable<K> getKeys() => _engine.getKeys();

  /// Removes expired entries and returns how many entries were removed.
  ///
  /// **This method is not thread-safe.**
  @override
  int purgeExpired() => _engine.purgeExpired();

  /// Retrieves the value associated with the specified key.
  ///
  /// - Returns `null` if the key does not exist or has expired.
  /// - Removes expired entries lazily.
  ///
  /// **This method is not thread-safe.**
  @override
  V? get(K key) => _engine.get(key);

  /// Retrieves [key] without changing insertion order.
  ///
  /// Expired entries are removed lazily and treated as absent.
  ///
  /// **This method is not thread-safe.**
  @override
  V? peek(K key) => _engine.peek(key);

  /// Checks whether [key] exists and has not expired.
  ///
  /// **This method is not thread-safe.**
  @override
  bool containsKey(K key) => _engine.containsKey(key);

  /// Stores [key]/[value] in the cache.
  ///
  /// - [ttl]: Per-entry TTL override. When omitted, the global TTL is used.
  /// - If the key already exists, its value and expiry are updated and its
  ///   insertion order is refreshed (it becomes the newest entry for FIFO purposes).
  ///
  /// **This method is not thread-safe.**
  @override
  void set(K key, V value, {Duration? ttl}) =>
      _engine.set(key, value, ttl: ttl);

  /// Returns the existing value for [key], or stores and returns a new one.
  ///
  /// The inherited [SimpleTTLCacheInterface] default checks presence and
  /// reads [key] with separate `containsKey`/`get` calls, which independently
  /// read the clock and can race with expiry; this override reads via a
  /// single [Cache.presentValue] snapshot instead, and writes through this
  /// class's own [set] (rather than the engine directly) so a subclass
  /// override of [set] still runs.
  ///
  /// **This method is not thread-safe.**
  @override
  V getOrSet(K key, V Function() valueFactory, {Duration? ttl}) {
    _engine.validateSetArgs(ttl: ttl);
    final (found, existing) = _engine.presentValue(key);
    if (found) return existing as V;
    final value = valueFactory();
    set(key, value, ttl: ttl);
    return value;
  }

  /// Updates the value for [key] and returns the new value.
  ///
  /// The inherited [SimpleTTLCacheInterface] default checks presence and
  /// reads [key] with separate `containsKey`/`get` calls, which independently
  /// read the clock and can race with expiry; this override reads via a
  /// single [Cache.presentValue] snapshot instead, and — see [getOrSet] —
  /// writes through this class's own [set].
  ///
  /// **This method is not thread-safe.**
  @override
  V update(
    K key,
    V Function(V value) update, {
    V Function()? ifAbsent,
    Duration? ttl,
  }) {
    _engine.validateSetArgs(ttl: ttl);
    final (found, existing) = _engine.presentValue(key);
    if (found) {
      final value = update(existing as V);
      set(key, value, ttl: ttl);
      return value;
    }
    if (ifAbsent == null) {
      throw StateError('Cannot update missing cache key: $key');
    }
    final value = ifAbsent();
    set(key, value, ttl: ttl);
    return value;
  }

  /// Retrieves values for all currently present [keys].
  ///
  /// The inherited [SimpleCache] default checks presence and reads each key
  /// with separate `containsKey`/`get` calls; this override reads each key
  /// via a single [Cache.presentValue] snapshot instead.
  ///
  /// **This method is not thread-safe.**
  @override
  Map<K, V> getAll(Iterable<K> keys) => _engine.getAll(keys);

  /// Removes all entries that match [test].
  ///
  /// The inherited [SimpleCache] default checks presence and peeks each key
  /// with separate `containsKey`/`peek` calls; this override reads each key
  /// via a single [Cache.presentPeek] snapshot instead.
  ///
  /// **This method is not thread-safe.**
  @override
  void removeWhere(bool Function(K key, V value) test) =>
      _engine.removeWhere(test);

  /// Removes the entry with the given key from the cache.
  ///
  /// - If the key does not exist, this call is a no-op.
  ///
  /// **This method is not thread-safe.**
  @override
  void remove(K key) => _engine.remove(key);

  /// Clears all data stored in the cache.
  ///
  /// **This method is not thread-safe.**
  @override
  void clear() => _engine.clear();

  /// Returns a string representation of the current live cache state.
  ///
  /// Expired entries are excluded from the returned representation.
  ///
  /// **This method is not thread-safe.**
  @override
  String toString() => _engine.toString();
}
