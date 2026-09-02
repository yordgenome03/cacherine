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

  /// Whether [access] can remove the entry as a side effect (`true` only for
  /// [EphemeralFIFOStore]). Lets callers like [Cache] skip a post-access
  /// presence recheck for every other policy, where it would always be a
  /// wasted lookup.
  bool get removesOnAccess;

  /// Inserts a new key, or updates an existing key's value. Implementations
  /// must preserve any per-key policy state (e.g. LFU frequency) on update,
  /// only refreshing recency — never resetting it — matching each policy's
  /// documented `set()`-on-existing-key semantics.
  void put(K key, V value);

  /// Chooses (without removing) the key this store would evict next, or
  /// `null` if the store is empty or every remaining key is [excluding].
  ///
  /// The result is wrapped in a single-field record rather than returned as
  /// a bare `K?`: when `K` is a nullable type, an entry actually stored
  /// under the literal key `null` is a legitimate victim, and a bare `K?`
  /// return can't tell that apart from "no victim" (both would be `null`).
  /// Wrapping moves the "found anything?" signal to the record's own
  /// nullability, leaving the wrapped key free to be `null` on its own
  /// account — so `(null,)` (found, victim key is `null`) and `null` (no
  /// victim) are distinguishable regardless of `K`.
  ///
  /// **Remaining nullable-`K` limitation on [excluding]:** unlike the return
  /// value above, [excluding] itself is not wrapped, so its own default
  /// (`null`, meaning "exclude nothing") is indistinguishable from an
  /// explicit request to exclude the literal key `null`. A store holding
  /// *only* a `null`-keyed entry, queried with [excluding] left at its
  /// default, therefore still reports "nothing evictable" — every
  /// implementation's `k != excluding` eligibility check sees `null !=
  /// null` (`false`) and treats that entry as excluded rather than as the
  /// sole candidate. This doesn't affect [Cache]'s own eviction loop, which
  /// always passes the key it is currently writing as [excluding] and so
  /// never relies on the default; it only affects a caller driving this
  /// interface directly. Fixing it too would need the same record-wrapping
  /// treatment applied to [excluding], which isn't done here — use a
  /// non-nullable key type if this matters for your use of a [CacheStore]
  /// directly.
  (K,)? selectVictim({K? excluding});

  /// Removes and returns the selected victim as a `(key, value)` record, or
  /// `null` under the same "nothing evictable" conditions as [selectVictim]
  /// (including its remaining [excluding]-side limitation).
  /// Like [selectVictim], the outer nullability alone signals "no victim" —
  /// a `null` key wrapped in a non-`null` record (`(null, value)`) means a
  /// victim *was* found and evicted, and its key happens to be `null`.
  (K, V)? evictOne({K? excluding});

  /// Removes [key] unconditionally. Returns `true` if it was present.
  bool remove(K key);

  /// Removes all entries.
  void clear();
}
