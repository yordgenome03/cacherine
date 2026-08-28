/// **Eviction-policy storage contract.**
///
/// Captures exactly the part of a cache implementation that differs between
/// eviction policies (FIFO, LRU, MRU, LFU, ...): which key is evicted next,
/// and what a read/write does to that ordering. Everything else — capacity
/// limits, weight accounting, TTL expiry, monitoring, locking — is handled
/// once by [Cache]/[AsyncCache]/[MonitoredCache], which drive a store through
/// this interface instead of duplicating policy logic per class.
abstract interface class CacheStore<K, V> {
  /// The number of entries currently stored.
  int get length;

  /// All keys, in this store's policy-defined order (not necessarily
  /// eviction order for every policy — see each implementation).
  Iterable<K> get keys;

  /// Whether [key] is currently stored.
  bool containsKey(K key);

  /// Reads [key] without any policy side effect. Returns `null` if absent.
  V? peek(K key);

  /// Reads [key], applying this store's on-read policy (e.g. LRU/MRU move
  /// the entry, LFU promotes its frequency bucket, EphemeralFIFO removes it).
  /// Returns `null` if absent.
  V? access(K key);

  /// Inserts a new key, or updates an existing key's value. Implementations
  /// must preserve any per-key policy state (e.g. LFU frequency) on update,
  /// only refreshing recency — never resetting it — matching each policy's
  /// documented `set()`-on-existing-key semantics.
  void put(K key, V value);

  /// Chooses (without removing) the key this store would evict next, or
  /// `null` if the store is empty or every remaining key is [excluding].
  K? selectVictim({K? excluding});

  /// Removes and returns the selected victim as a `(key, value)` pair, or
  /// `null` under the same conditions as [selectVictim].
  (K, V)? evictOne({K? excluding});

  /// Removes [key] unconditionally. Returns `true` if it was present.
  bool remove(K key);

  /// Removes all entries.
  void clear();
}
