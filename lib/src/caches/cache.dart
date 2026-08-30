import '../interfaces/simple_cache.dart';
import '../interfaces/weigher.dart';
import '../monitorings/eviction_reason.dart';
import '../stores/cache_store.dart';

/// **Composable, synchronous cache engine.**
///
/// Combines an injected [CacheStore] (which eviction policy applies — FIFO,
/// LRU, MRU, LFU, ...) with optional, independently-configurable capacity and
/// expiry concerns:
///
/// - **[maxSize]**: caps entry count.
/// - **[weigher]** + **[maxWeight]**: caps total entry *weight* (e.g. an
///   estimated byte size), supplied together or not at all. An explicit
///   `weight:` argument on [set] overrides [weigher] for that call.
/// - **[ttl]**: entries expire after this duration unless a per-`set()`
///   `ttl:` override is given.
///
/// Every named cache class in this package (`SimpleLRUCache`,
/// `SimpleWeightedLRUCache`, ...) is a thin, backward-compatible facade
/// configuring this engine with a specific [CacheStore] and concern set.
/// Power users needing a combination without a dedicated name (e.g. a
/// weight-and-TTL-bounded LRU cache) can construct [Cache] directly.
///
/// The [CacheStore] passed in must be empty and must not be touched by
/// anything other than this [Cache] afterward — `Cache` is the sole owner
/// of its weight/expiry ledgers, and has no way to notice entries a caller
/// added directly through the store (they'd never count toward
/// [maxWeight] and would never expire) or removed directly through it
/// (their ledger entries would linger). The constructor rejects a
/// non-empty store; there is no supported way to enforce "don't touch it
/// afterward" beyond not exposing the store itself.
///
/// This class is not async-safe; use [AsyncCache] for concurrent access.
class Cache<K, V> extends SimpleCache<K, V> {
  final CacheStore<K, V> _store;
  final int? maxSize;
  final Weigher<K, V>? weigher;
  final int? maxWeight;
  final Duration? ttl;
  final DateTime Function() clock;

  final Map<K, int> _weights = {};
  int _currentWeight = 0;
  final Map<K, DateTime> _expiry = {};

  /// A lower bound on the earliest expiry deadline among current entries (or
  /// `null` if none is known). Exact right after a full [_purgeExpired] scan,
  /// but never updated on a single-key removal — so it can go stale-low
  /// after eviction/removal, which is safe: it only ever causes an
  /// unnecessary purge scan, never a missed one. Lets [_write] skip the
  /// O(n) purge scan on the common capacity-eviction path where nothing has
  /// actually expired yet.
  DateTime? _minExpiry;

  /// Notified whenever an entry is evicted (capacity, weight, or expiry) —
  /// not called for explicit [remove]. Settable rather than
  /// constructor-injected so [MonitoredCache] can wire it to
  /// `metrics.recordEvictionReason` from its own constructor body.
  void Function(EvictionReason reason)? onEvict;

  bool get _weightEnabled => weigher != null;
  bool get _ttlEnabled => ttl != null;

  /// Creates a [Cache].
  ///
  /// - **[store]**: the eviction-policy backing storage. Must be empty —
  ///   see the class doc comment for why a pre-populated or externally
  ///   mutated store isn't supported.
  /// - **[maxSize]**: optional entry-count cap.
  /// - **[weigher]**/**[maxWeight]**: optional weight cap; both must be
  ///   supplied together, or neither.
  /// - **[ttl]**: optional default expiry duration for entries.
  /// - **[clock]**: injectable time source for testing; defaults to
  ///   [DateTime.now].
  ///
  /// **Throws [ArgumentError]** if [store] is non-empty, if [maxSize] is
  /// `<= 0`, if exactly one of [weigher]/[maxWeight] is supplied, if
  /// [maxWeight] is `<= 0`, or if [ttl] is not a positive duration.
  Cache({
    required CacheStore<K, V> store,
    this.maxSize,
    this.weigher,
    this.maxWeight,
    this.ttl,
    DateTime Function()? clock,
  }) : _store = store,
       clock = clock ?? DateTime.now {
    if (_store.length != 0) {
      throw ArgumentError(
        'store must be empty; Cache cannot adopt a pre-populated store\'s '
        'entries into its weight/expiry ledgers.',
      );
    }
    if (maxSize != null && maxSize! <= 0) {
      throw ArgumentError('maxSize must be greater than 0.');
    }
    if ((weigher == null) != (maxWeight == null)) {
      throw ArgumentError('weigher and maxWeight must be provided together.');
    }
    if (maxWeight != null && maxWeight! <= 0) {
      throw ArgumentError('maxWeight must be greater than 0.');
    }
    if (ttl != null && ttl! <= Duration.zero) {
      throw ArgumentError('ttl must be greater than zero.');
    }
  }

  /// The sum of the weights of all entries currently stored, if weighing is
  /// enabled (always `0` otherwise).
  int get currentWeight => _currentWeight;

  @override
  Iterable<K> getKeys() {
    if (!_ttlEnabled) return _store.keys;
    final now = clock();
    return _store.keys.where((k) => _isLive(k, now)).toList();
  }

  @override
  V? get(K key) {
    if (_ttlEnabled) _dropIfExpired(key, clock());
    return _accessAndReconcile(key);
  }

  /// Atomically checks presence and reads [key] using a single `now`
  /// snapshot, returning `(found, value)`.
  ///
  /// Calling [containsKey] and then separately [get] to implement
  /// check-then-fetch logic (as [getOrSet]/[update] do) is unsafe on a
  /// TTL-enabled instance: each call reads the clock independently, so an
  /// entry can be observed live by the first call and expired by the
  /// second, with the second call purging it and returning `null` (a bad
  /// cast for non-nullable `V`) instead of taking the "absent" branch.
  /// This method makes that check-then-fetch pattern atomic with respect to
  /// expiry. Exposed (not private) so [AsyncCache]/[MonitoredCache]/
  /// [MonitoredTTLCache] can build the same atomicity into their own
  /// `getOrCompute`/`update` overloads.
  (bool, V?) presentValue(K key) {
    if (_ttlEnabled) _dropIfExpired(key, clock());
    if (!_store.containsKey(key)) return (false, null);
    return (true, _accessAndReconcile(key));
  }

  /// Atomically checks presence and reads [key] via [CacheStore.peek] (no
  /// eviction-policy side effect) using a single `now` snapshot, returning
  /// `(found, value)`.
  ///
  /// Use this instead of [presentValue] when the check-then-read must not
  /// perturb policy state — [removeWhere] must not bump LRU recency or LFU
  /// frequency merely by testing an entry for removal, matching [peek]'s
  /// no-side-effect contract.
  (bool, V?) presentPeek(K key) {
    if (_ttlEnabled) _dropIfExpired(key, clock());
    if (!_store.containsKey(key)) return (false, null);
    return (true, _store.peek(key));
  }

  V? _accessAndReconcile(K key) {
    final value = _store.access(key);
    // Some stores remove the entry as a side effect of access() (e.g.
    // EphemeralFIFOStore). When that happens, the weight/expiry ledgers
    // must be reconciled here too, or currentWeight drifts and a stale
    // _expiry entry lingers — neither is cleaned up by any other path,
    // since remove()/eviction/purge are the only other ledger-clearing
    // sites and none of them run for a plain get().
    if ((_weightEnabled || _ttlEnabled) &&
        _store.removesOnAccess &&
        !_store.containsKey(key)) {
      _forgetWeight(key);
      _expiry.remove(key);
    }
    return value;
  }

  /// Throws [ArgumentError] under the same conditions as [set] — supplying
  /// [weight] without a configured [weigher], a negative explicit [weight],
  /// [ttl] without a configured default [ttl], or a non-positive [ttl].
  /// Exposed so [AsyncCache]/[MonitoredCache] can fail fast on invalid
  /// arguments *before* checking cache presence or invoking a
  /// `valueFactory`/`update` callback in `getOrSet`/`getOrCompute`/`update`,
  /// matching [set]'s validate-first contract on a hit as well as a miss —
  /// an explicit negative [weight] must be rejected the same way regardless
  /// of whether the key already exists (a weigher-*computed* negative
  /// weight can still only be caught in `_write`, once a value exists to
  /// weigh).
  void validateSetArgs({int? weight, Duration? ttl}) {
    if (weight != null && !_weightEnabled) {
      throw ArgumentError(
        'weight was supplied but this cache was not configured with a '
        'weigher/maxWeight.',
      );
    }
    if (weight != null && weight < 0) {
      throw ArgumentError('weight must not be negative.');
    }
    if (ttl != null && !_ttlEnabled) {
      throw ArgumentError(
        'ttl was supplied but this cache was not configured with a default '
        'ttl.',
      );
    }
    if (ttl != null && ttl <= Duration.zero) {
      throw ArgumentError('ttl must be greater than zero.');
    }
  }

  @override
  V? peek(K key) {
    if (_ttlEnabled) _dropIfExpired(key, clock());
    return _store.peek(key);
  }

  @override
  bool containsKey(K key) {
    if (_ttlEnabled) _dropIfExpired(key, clock());
    return _store.containsKey(key);
  }

  /// Stores [key]/[value].
  ///
  /// - [weight]: overrides [weigher] for this entry. Ignored (and rejected)
  ///   unless this instance was configured with a [weigher]/[maxWeight].
  /// - [ttl]: overrides the default expiry for this entry. Ignored (and
  ///   rejected) unless this instance was configured with a [ttl].
  ///
  /// If storing the entry would exceed [maxWeight] and/or [maxSize],
  /// existing entries are evicted — oldest-by-policy first — until it fits.
  /// If the entry's own weight exceeds [maxWeight], it cannot fit under any
  /// circumstances and is not cached.
  ///
  /// **Throws [ArgumentError]** if [weight] is supplied without a configured
  /// [weigher], if [ttl] is supplied without a configured default [ttl], or
  /// if [weight] is negative.
  @override
  void set(K key, V value, {int? weight, Duration? ttl}) {
    validateSetArgs(weight: weight, ttl: ttl);
    _write(key, value, weight, ttl);
  }

  /// Like [set], but returns whether [value] was actually stored instead of
  /// silently accepting a weight-exceeds-[maxWeight] rejection. Exposed so
  /// [AsyncCache]/[MonitoredCache] can detect that rejection from their own
  /// `getOrCompute`/`update` overloads (which — unlike [set] — must report
  /// what was actually cached) without duplicating [validateSetArgs] logic.
  bool trySet(K key, V value, {int? weight, Duration? ttl}) {
    validateSetArgs(weight: weight, ttl: ttl);
    return _write(key, value, weight, ttl);
  }

  /// **Throws [StateError]** instead of returning on a miss if the computed
  /// value's weight exceeds [maxWeight] — unlike [set], this method has a
  /// non-`void` return contract, so it cannot silently report a value that
  /// was never actually cached.
  @override
  V getOrSet(K key, V Function() valueFactory, {int? weight, Duration? ttl}) {
    validateSetArgs(weight: weight, ttl: ttl);
    final (found, existing) = presentValue(key);
    if (found) return existing as V;
    final value = valueFactory();
    return _writeOrThrow(key, value, weight, ttl);
  }

  @override
  V putIfAbsent(
    K key,
    V Function() valueFactory, {
    int? weight,
    Duration? ttl,
  }) => getOrSet(key, valueFactory, weight: weight, ttl: ttl);

  /// **Throws [StateError]** if [key] is missing and [ifAbsent] is not
  /// supplied, or if the resulting value's weight exceeds [maxWeight] —
  /// unlike [set], this method has a non-`void` return contract, so it
  /// cannot silently report a value that was never actually cached.
  @override
  V update(
    K key,
    V Function(V value) update, {
    V Function()? ifAbsent,
    int? weight,
    Duration? ttl,
  }) {
    validateSetArgs(weight: weight, ttl: ttl);
    final (found, existing) = presentValue(key);
    if (found) {
      final value = update(existing as V);
      return _writeOrThrow(key, value, weight, ttl);
    }
    if (ifAbsent == null) {
      throw StateError('Cannot update missing cache key: $key');
    }
    final value = ifAbsent();
    return _writeOrThrow(key, value, weight, ttl);
  }

  @override
  void setAll(Map<K, V> entries, {int? weight, Duration? ttl}) {
    validateSetArgs(weight: weight, ttl: ttl);
    for (final entry in entries.entries) {
      _write(entry.key, entry.value, weight, ttl);
    }
  }

  /// The [SimpleCache.getAll] default checks presence and reads each key with
  /// separate [containsKey]/[get] calls; on a TTL-enabled instance each reads
  /// the clock independently, so an entry can expire between the two calls.
  /// This override reads each key with a single [presentValue] snapshot.
  @override
  Map<K, V> getAll(Iterable<K> keys) {
    final values = <K, V>{};
    for (final key in keys) {
      final (found, value) = presentValue(key);
      if (found && (value != null || null is V)) {
        values[key] = value as V;
      }
    }
    return values;
  }

  /// The [SimpleCache.removeWhere] default checks presence and peeks each key
  /// with separate [containsKey]/[peek] calls; on a TTL-enabled instance each
  /// reads the clock independently, so an entry can expire between the two
  /// calls. This override reads each key with a single [presentPeek]
  /// snapshot (peek-based, so testing an entry for removal never perturbs its
  /// eviction-policy state).
  @override
  void removeWhere(bool Function(K key, V value) test) {
    final snapshot = getKeys();
    for (final key in (snapshot is List<K> ? snapshot : snapshot.toList())) {
      final (found, value) = presentPeek(key);
      if (!found) continue;
      if (test(key, value as V)) {
        remove(key);
      }
    }
  }

  /// Removes [key] and reports whether it was present. Used internally by
  /// [MonitoredCache] to attribute a manual-eviction metric only when a
  /// removal actually happened; [remove] (the [SimpleCache] override) is a
  /// thin `void`-returning wrapper around this.
  bool removeIfPresent(K key) {
    final removed = _store.remove(key);
    if (removed) {
      _forgetWeight(key);
      _expiry.remove(key);
    }
    return removed;
  }

  @override
  void remove(K key) => removeIfPresent(key);

  @override
  void clear() {
    _store.clear();
    _weights.clear();
    _currentWeight = 0;
    _expiry.clear();
    _minExpiry = null;
  }

  /// Removes all currently-expired entries and returns how many were
  /// removed. A no-op returning `0` if TTL is not configured.
  int purgeExpired() {
    if (!_ttlEnabled) return 0;
    return _purgeExpired(clock());
  }

  @override
  String toString() {
    return {for (final k in getKeys()) k: _store.peek(k) as V}.toString();
  }

  bool _isLive(K key, DateTime now) {
    final exp = _expiry[key];
    return exp == null || exp.isAfter(now);
  }

  void _dropIfExpired(K key, DateTime now) {
    final exp = _expiry[key];
    if (exp != null && !exp.isAfter(now)) {
      _store.remove(key);
      _forgetWeight(key);
      _expiry.remove(key);
      onEvict?.call(EvictionReason.expired);
    }
  }

  int _purgeExpired(DateTime now) {
    var removed = 0;
    DateTime? newMin;
    for (final k in _store.keys.toList()) {
      final exp = _expiry[k];
      if (exp != null && !exp.isAfter(now)) {
        _store.remove(k);
        _forgetWeight(k);
        _expiry.remove(k);
        onEvict?.call(EvictionReason.expired);
        removed++;
      } else if (exp != null && (newMin == null || exp.isBefore(newMin))) {
        newMin = exp;
      }
    }
    // Exact again for every surviving entry, restoring the fast-skip bound
    // in _write() until the next entry actually expires.
    _minExpiry = newMin;
    return removed;
  }

  void _forgetWeight(K key) {
    final w = _weights.remove(key);
    if (w != null) _currentWeight -= w;
  }

  /// Returns `true` if [value] was actually stored, `false` if its weight
  /// (explicit or weigher-computed) exceeds [maxWeight] and it was rejected
  /// as a no-op — the same "can never fit" case [set] silently accepts.
  /// Callers with a non-`void` return contract (`getOrSet`/`update`) must
  /// check this, or they'd report a value they never actually cached.
  bool _write(K key, V value, int? explicitWeight, Duration? entryTtl) {
    final now = _ttlEnabled ? clock() : null;
    if (now != null) _dropIfExpired(key, now);

    final existed = _store.containsKey(key);

    int? entryWeight;
    if (_weightEnabled) {
      entryWeight = explicitWeight ?? weigher!(key, value);
      if (entryWeight < 0) {
        throw ArgumentError('weight must not be negative.');
      }
      if (entryWeight > maxWeight!) {
        return false; // Can never fit; leave the cache without this entry.
      }
    }

    final oldWeight = _weightEnabled ? _weights[key] : null;
    final extraCount = existed ? 0 : 1;
    final extraWeight = _weightEnabled ? entryWeight! - (oldWeight ?? 0) : 0;

    bool exceedsCount() =>
        maxSize != null && (_store.length + extraCount) > maxSize!;
    bool exceedsWeight() =>
        _weightEnabled && (_currentWeight + extraWeight) > maxWeight!;

    if (exceedsCount() || exceedsWeight()) {
      // Only pay for the O(n) purge scan when something might actually be
      // expired (_minExpiry is a lower bound on the true minimum deadline);
      // otherwise every capacity-triggered write on a TTL+maxSize cache
      // would rescan the whole store for nothing.
      if (now != null && _minExpiry != null && !_minExpiry!.isAfter(now)) {
        _purgeExpired(now);
      }
      while (exceedsCount() || exceedsWeight()) {
        final wasOverWeight = exceedsWeight();
        final evicted = _store.evictOne(excluding: key);
        if (evicted == null) break; // nothing left to evict but `key` itself
        final (victimKey, _) = evicted;
        _forgetWeight(victimKey);
        _expiry.remove(victimKey);
        onEvict?.call(
          wasOverWeight ? EvictionReason.weight : EvictionReason.capacity,
        );
      }
    }

    if (oldWeight != null) _currentWeight -= oldWeight;

    _store.put(key, value);

    if (_weightEnabled) {
      _weights[key] = entryWeight!;
      _currentWeight += entryWeight;
    }
    if (_ttlEnabled) {
      final deadline = now!.add(entryTtl ?? ttl!);
      _expiry[key] = deadline;
      if (_minExpiry == null || deadline.isBefore(_minExpiry!)) {
        _minExpiry = deadline;
      }
    }
    return true;
  }

  /// Writes [key]/[value] via [_write] and returns [value], or throws
  /// [StateError] if the write was rejected because its weight exceeds
  /// [maxWeight] — used by [getOrSet]/[update], which (unlike [set]) must
  /// report what was actually stored rather than silently returning a value
  /// that was never cached.
  V _writeOrThrow(K key, V value, int? weight, Duration? ttl) {
    if (!_write(key, value, weight, ttl)) {
      throw StateError(
        'Cannot store value for cache key: $key — its weight exceeds '
        'maxWeight and can never fit.',
      );
    }
    return value;
  }
}
