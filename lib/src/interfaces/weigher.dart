/// **Entry weigher for weight-based caches**
///
/// Computes the weight of a cache entry (e.g. its estimated byte size) from
/// its [key] and [value]. Used by [Cache], [AsyncCache], and [MonitoredCache]
/// (and the named `Weighted*` facades built on them) to decide how much of
/// the cache's `maxWeight` an entry consumes.
///
/// **Cached values should be treated as immutable once stored.** The weight
/// recorded for an entry is computed once, at `set()` time, and never
/// recomputed. If a stored value is later mutated in place such that its
/// "true" weight would change, the cache's internal weight ledger will
/// silently drift from reality — there is no automatic re-weighing. If a
/// value's cost can legitimately change over time, re-`set()` the key (with
/// an explicit `weight:` override if desired) to make the cache re-account
/// for it.
typedef Weigher<K, V> = int Function(K key, V value);
