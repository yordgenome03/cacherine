## Unreleased - Composable Cache Engine, Weight-Based Eviction

### Maintenance

- Extracted the `getOrCompute`/`update` control flow that every legacy facade composing (not extending) an engine had hand-rolled identically — this PR's own history is direct evidence of the resulting cost: the "write through this class's own `set` instead of the engine directly" fix had to be independently discovered and applied three separate times at three separate generality tiers. `LRUCache`/`MRUCache`/`FIFOCache`/`LFUCache`/`EphemeralFIFOCache`/`TTLCache` now call shared top-level functions (`composedGetOrCompute`/`composedUpdate` in the new `lib/src/caches/_composed_engine_ops.dart`, plus sync counterparts `syncComposedGetOrSet`/`syncComposedUpdate` used by `SimpleTTLCache`); their `Monitored*` counterparts (`MonitoredLRUCache`/`MonitoredMRUCache`/`MonitoredFIFOCache`/`MonitoredLFUCache`/`MonitoredEphemeralFIFOCache`/`MonitoredTTLCache`) call new `monitoredGetOrCompute`/`monitoredUpdate` methods added to the `CacheMonitoring` mixin. No public API changed; each facade keeps its own narrow signature and dispatch-through-`set` behavior — only the previously-duplicated method bodies moved.
- Fixed `AsyncCache`/`MonitoredCache`/`MonitoredTTLCache`/`MonitoredEphemeralFIFOCache`'s `getAll()`/`removeWhere()` acquiring the instance lock once per key instead of once for the whole batch — `setAll()` already did this; these now match it, cutting a 10,000-key `getAll()` from 10,000-20,000 lock acquisitions down to 1. `Cache.getAll()`/`removeWhere()` (the sync engine) similarly now read the clock once for the whole batch instead of once per key, which is still one consistent point-in-time view (this method's own contract) at a fraction of the cost on a TTL-enabled instance.
- Consolidated `Cache`'s two internal call sites of `checkWeightRejection()` (`trySet()` and `_storeOrThrow()`) down to one: `_storeOrThrow()` now delegates to `trySet()` instead of duplicating its "check then write through `set()`" logic. `checkWeightRejection()`'s doc comment now spells out the correct-vs-incorrect usage explicitly, since a future caller of this public method (the docs already invite subclassing `Cache`/`AsyncCache`/`MonitoredCache` directly) could otherwise silently reopen the exact double-weigher-invocation issue this method exists to prevent.

### Fixes

- Fixed `EphemeralFIFOCache`/`MonitoredEphemeralFIFOCache`'s `getAll()`/`removeWhere()`, which were left to `ThreadSafeCache`'s default implementations (correct for every other legacy facade, since their `get`/`peek` are non-destructive) — but `get()` for this store *is* destructive (an entry is removed on retrieval), so the default's separate `containsKey()`-then-`get()`/`peek()` calls, each independently acquiring the lock, left a gap where a concurrent caller's `get()` could consume the entry first: `getAll()` would silently omit a key that was confirmed present a moment earlier, and `removeWhere()` would throw a `TypeError` casting the resulting `null` to a non-nullable `V`. Both now read (and, per `get()`'s documented behavior, consume) each key via a single atomic snapshot instead, matching the fix already applied elsewhere in this release for TTL/weight check-then-fetch races.
- Fixed `CacheMetrics.getLatencyPercentile(50)` (and `CacheMetricsSnapshot.p50Latency`) discarding all sub-millisecond precision on an even sample count — the median branch truncated both middle samples to whole milliseconds via `.inMilliseconds` before averaging, so two latencies like 400µs/800µs (realistic for an in-memory cache) incorrectly reported a median of `0`, disagreeing with `averageLatency`'s correct `600µs` for the same data. Now averages in microseconds throughout.

### Testing

- Following up on the set()-bypass fixes above, audited the suite for missing coverage of documented performance/robustness/behavioral guarantees and closed the highest-confidence gaps: `Cache.update()`'s callback-throws-mid-computation path now asserts the cache/weight ledger is left untouched and the instance stays usable afterward; `AsyncCache`/`MonitoredCache`'s `getOrCompute()`/`update()` now assert the instance's lock is actually released (not just that the exception propagates) when the caller's `valueFactory`/`update` callback throws, guarding against a silent deadlock on every later call; `EvictionReason` attribution is now tested with `maxSize` and `maxWeight` configured together (previously each was only tested in isolation), pinning down that a write exceeding both at once is always attributed `.weight`, never `.capacity`; and `TTLFifoStore` was added to the shared `CacheStore` conformance suite (it was the only store implementation not covered by it) plus a dedicated policy test for its "update refreshes FIFO position" behavior, the one place it deliberately diverges from `FIFOStore`.
- Closed the remaining backlog of performance/robustness/behavioral test gaps from the same audit: weigher invocation count on `getOrSet`/`update`/`trySet`/`getOrCompute` is now pinned down explicitly (see the `checkWeightRejection` fix below); a slow `getOrCompute()` on one key is confirmed to actually block a concurrent `set()` on an unrelated key, per `AsyncCache`'s documented single-instance-lock tradeoff; a `set()` override that reentrantly calls a *different* public method (`clear()`) mid-write is confirmed not to deadlock or corrupt state; a fully unbounded `Cache` (no `maxSize`/`maxWeight`/`ttl`) is confirmed to hold 50,000 entries correctly; a temporarily backward-jumping injected clock is confirmed not to corrupt cache state and to resume normal purging once the clock catches back up; `Cache._minExpiry`'s post-purge restoration is now verified to keep short-circuiting a *subsequent* write, not just the write that triggered the purge; a weight-bounded LFU cache's `excluding`-key eviction fallthrough (previously only tested against `LFUStore` in isolation) is now driven end-to-end through `Cache`; `CacheMetrics.snapshot()` is now smoke-tested for O(n)-not-worse cost at the full `maxEvictionSamples` retention cap, and for correct window-filtering under sustained churn well past that cap; `CacheAlertConfig`'s strict-inequality thresholds are now tested at their exact boundary (hit rate and per-reason eviction rate) to catch an accidental `<=`/`>=` flip; `LRUStore`/`FIFOStore`/`EphemeralFIFOStore` gained the same `selectVictim(excluding:)` multi-candidate fallback test `MRUStore`/`LFUStore` already had; `LFUCache.getKeys()` — the only policy whose key order is documented as unspecified — was added to the canonical order-contract test file, asserting the correct key *set* rather than an order; and `PeriodicSweeper` gained a dedicated test file, including a direct test of its documented "an in-flight sweep still runs to completion after `dispose()`" guarantee.
- Fixed a latent correctness gap the above audit surfaced in the set()-bypass fix itself: `trySet()`/`getOrSet()`/`update()`/`AsyncCache.storeOrThrow()` computed a write's weight twice — once as a pre-check (to decide whether to reject/throw), once again inside the delegated `set()`/`_write()` — so a non-deterministic `weigher` (unsupported per its documented "should be pure" contract, but not otherwise guarded against) could disagree with itself between the two calls, letting `trySet()` report success (or `getOrSet()`/`update()` return a value) for a write that was actually silently rejected for exceeding `maxWeight`. `Cache.wouldRejectWrite()` was replaced with `checkWeightRejection()`, which computes the weight once and threads it back into the delegated `set()` call as an explicit `weight:`, so the weigher is now invoked exactly once per logical write (down from up to twice) and the two call sites can no longer disagree.

### New Features

- **Weight-based eviction (closes #67)**: Added `SimpleWeightedLRUCache`, `WeightedLRUCache`, and `MonitoredWeightedLRUCache` — LRU caches bounded by a caller-supplied per-entry weight (e.g. estimated byte size) via a `weigher` callback and `maxWeight`, optionally alongside an entry-count `maxSize`. An explicit `weight:` argument can also be passed per `set()` call.
- **Composable cache engine**: Added public `Cache`/`AsyncCache`/`MonitoredCache` classes and a `CacheStore` interface (with `LRUStore`/`MRUStore`/`FIFOStore`/`EphemeralFIFOStore`/`LFUStore` implementations). Every named cache class in this package (`SimpleLRUCache`, `TTLCache`, `MonitoredWeightedLRUCache`, ...) is now a thin facade over this engine — power users can configure combinations that don't have a dedicated name (e.g. a weight-and-TTL-bounded LRU cache) by constructing `Cache`/`AsyncCache`/`MonitoredCache` directly.
- **Per-cause eviction tracking**: Added `EvictionReason` (`capacity`, `weight`, `expired`, `manual`, `unspecified`) as an optional argument to `CacheMetrics.recordEviction()`, and an additive `evictionsPerMinuteByReason` field on `CacheMetricsSnapshot`/`DashboardSnapshot`. `CacheAlertConfig` gained an optional `evictionsPerReasonThreshold` so alerting can distinguish an expected `expired` rate from a `capacity`/`weight` rate that signals the cache is undersized.
- Added a shared `PeriodicSweeper` mixin (implements `Disposable`) that centralizes the "owns a periodic timer" lifecycle previously hand-rolled per TTL/Monitored class.

### Documentation

- Documented that cached values should be treated as immutable once stored under a `weigher` — the recorded weight is never recomputed, so a value mutated in place after caching will silently drift from the ledger; re-`set()` (with an explicit `weight:` override if needed) to refresh it.
- Documented that `getOrCompute`/`update` hold the whole cache instance's lock across the awaited callback (not just the affected key), so slow work (e.g. a network request) should not run directly inside it.
- Documented `LFUStore`'s eviction-candidate fallthrough: when the min-frequency bucket's only occupant is the key currently being excluded from eviction, selection falls through to the next occupied frequency bucket rather than reporting nothing evictable.

### Maintenance

- All ~19 pre-existing concrete cache classes (FIFO/EphemeralFIFO/LRU/MRU/LFU/TTL × Simple/async/Monitored) were internally rewritten to compose the new engine, with byte-for-byte-preserved public constructors and behavior — the full pre-existing test suite passes unchanged against them.
- Fixed a remaining set of TTL check-then-fetch races (the same class of bug as `presentValue()` above fixed for `getOrSet`/`getOrCompute`/`update`), where a separate presence check and read/peek could each read the clock independently and observe an entry expire in between: `Cache.getAll()`/`removeWhere()`, `AsyncCache.getAll()`/`removeWhere()` (previously falling back to the base interfaces' racy defaults), and `SimpleTTLCache.getOrSet()`/`update()`/`getAll()`/`removeWhere()`, `TTLCache.update()`/`getAll()`/`removeWhere()`, `MonitoredTTLCache.update()`/`getAll()`/`removeWhere()` (previously falling back to their parent interfaces' racy defaults instead of the composed engine's atomic helpers). Added `Cache.presentPeek()` — a peek-based (non-mutating) counterpart to `presentValue()` — so `removeWhere()` can test entries for removal without perturbing LRU/LFU eviction-policy state as a side effect.
- Fixed `LFUStore`'s eviction-candidate fallthrough degrading to `O(distinct frequencies)` per victim (and repeating per victim across a multi-eviction write, i.e. up to `O(n × distinct frequencies)`) by chaining frequency buckets into their own linked list instead of rescanning a plain frequency map; eviction, promotion, and selection (including the excluded-key fallthrough) are now O(1) worst case.
- Fixed `MonitoredCache.getAll()`/`update()` and `MonitoredTTLCache.getAll()`/`removeWhere()`/`update()` silently dropping the hit/miss/latency/eviction metrics `doc/monitored_cache.md` documents, by delegating straight to an unmonitored inner engine call instead of routing through the monitored `get()`/`remove()` path (`update()`'s gap was a regression from the `presentValue()`-based TTL-race fix above, which bypassed the old default implementation's `get()` call that used to record these metrics via virtual dispatch).
- Fixed `Cache.validateSetArgs()` silently accepting a negative explicit `weight:` on `getOrSet()`/`getOrCompute()`/`update()` when the key was already present (only a miss reached the negative-weight check inside `_write()`); it's now rejected eagerly regardless of hit or miss, matching `set()`'s validate-first contract.
- Fixed `getOrSet()`/`getOrCompute()`/`update()` (`Cache`, `AsyncCache`, `MonitoredCache`) reporting a value as cached when its weight actually exceeded `maxWeight` and `_write()` silently rejected it as a no-op — the same "can never fit" case `set()` accepts silently, but these methods have a non-`void` return contract, so a caller previously got back a value (the newly-computed one, or the update callback's result) that was never actually stored, while any prior entry under that key was left unchanged with no signal anything went wrong. They now throw `StateError` instead when the write is rejected.
- `Cache._write()` no longer scans every stored key to purge expired entries on a capacity-triggered write when nothing has actually expired yet (tracked via a cheap lower-bound on the earliest expiry deadline), so inserting into a TTL-and-`maxSize`-bounded cache at steady-state capacity stays O(1) amortized instead of O(n) per insert. Added `CacheStore.removesOnAccess` so `Cache.get()` skips a redundant presence recheck for every policy (LRU/LFU/FIFO/MRU/TTL) except `EphemeralFIFOStore`, the only one where `access()` removes the entry.
- Fixed a source-compatibility break in `SimpleLRUCache`/`SimpleFIFOCache`/`SimpleLFUCache`/`SimpleMRUCache`/`SimpleEphemeralFIFOCache`, their async equivalents, and the corresponding `Monitored*Cache` classes: extending `Cache`/`AsyncCache`/`MonitoredCache` directly (rather than composing them, as `TTLCache`/`MonitoredTTLCache`/`SimpleTTLCache` already correctly did) pulled the new engine's `weight`/`ttl` named parameters into these classes' inherited `set`/`setAll`/`getOrSet`/`getOrCompute`/`update`, so any pre-existing downstream subclass overriding one of those methods with the old, narrower signature would fail to compile (Dart doesn't allow an override to drop optional named parameters the overridden method declares). All 15 of these "legacy" facades now compose an internal engine instead, restoring their original method surface; the `Monitored*` ones additionally mix in `CacheMonitoring`/`PeriodicSweeper` directly (matching `MonitoredTTLCache`) so `is CacheMonitoring<K, V>`/`is Disposable` keep holding.
- Fixed these same 15 legacy facades' bulk/compound helpers (`setAll`/`getAll`/`getOrSet`/`getOrCompute`/`update`/`removeWhere`) delegating straight to the internal engine, bypassing a downstream subclass's override of `set`/`get`/etc. entirely — before the composable-engine refactor, these were inherited from `SimpleCache`/`ThreadSafeCache` and dynamically called the (overridable) facade methods. The non-monitored facades now leave these to the interface defaults, which call this class's own methods; the `Monitored*` ones keep custom `getOrCompute`/`update` (for hit/miss metrics) but now write through their own `set` instead of the engine directly. `AsyncCache`'s internal lock is now reentrant so that in-lock write can happen without deadlocking, preserving the existing no-duplicate-computation-for-a-racing-key guarantee for `getOrCompute`/`update`.
- Fixed `CacheMetrics.recordEviction()` gaining an optional `EvictionReason` parameter, which was source-breaking for the same reason as above (downstream override with the original zero-argument signature). Split it back into a genuine zero-argument `recordEviction()` and a new `recordEvictionReason(EvictionReason)`.
- Fixed the weight-based-eviction README/`doc/weighted_lru_cache.md` examples labeling a `List<int>`'s `.length` as a byte-size weight — a `List<int>` has substantial per-element overhead beyond one byte, so this understated real memory usage. Switched the examples to `Uint8List`/`lengthInBytes`, which is exactly the byte count.
- Found and fixed the same `set`-bypass issue in `TTLCache`/`MonitoredTTLCache`/`SimpleTTLCache`'s `getOrCompute`/`getOrSet`/`update`, which wrote through the internal engine directly instead of this class's own `set`. Unlike the 15 facades above, these classes' `getAll`/`removeWhere` were deliberately left calling the engine directly (not fixed) — they need a single atomic clock snapshot per key to avoid a TTL check-then-fetch race already fixed earlier in this same effort, which routing through separate `get`/`peek`/`containsKey` calls would reintroduce; `getOrCompute`/`update` don't have that conflict since they already run under a single lock hold, so the same reentrant-lock technique applies.
- Found and fixed the same `set`-bypass issue at its root, in `Cache`/`AsyncCache`/`MonitoredCache` themselves: `Cache.getOrSet()`/`update()`/`setAll()` wrote via private `_write`/`_writeOrThrow` helpers, and `AsyncCache`/`MonitoredCache`'s `getOrCompute()`/`update()`/`setAll()` wrote via `storeOrThrow()` calling the composed `Cache` engine's `trySet()` directly — both bypassing `this.set()` entirely. Since `SimpleWeightedLRUCache`/`WeightedLRUCache`/`MonitoredWeightedLRUCache` extend these classes directly and add no `set()` of their own, they (and any subclass overriding `set()` on any of these six classes) were silently affected. `Cache.getOrSet()`/`update()`/`setAll()`/(the now-`set()`-delegating) `trySet()` and `AsyncCache.storeOrThrow()`/`setAll()` now write through `this.set()`; a new `Cache.wouldRejectWrite()` lets each of these detect a weight-exceeds-`maxWeight` rejection *before* delegating to `set()` (which, like `_write()` before it, has no way to report back what it actually stored), so the reject-and-throw contract on `getOrSet`/`update`/`getOrCompute` is preserved without needing `set()` itself to return anything. Added `test/caches/core_engine_subclass_compat_test.dart`, covering all six classes, to guard against this regressing again.

## 2.4.0 - Conditional Mutation Helpers and Bulk Operations

### New Features

- Added `putIfAbsent()`, `update()`, and `removeWhere()` default APIs to simple, async-safe, and TTL cache interfaces.
- Added TTL-aware `putIfAbsent()` and `update()` overloads so new or updated entries can receive per-entry TTL overrides through TTL abstractions.
- Added `getAll()`, `setAll()`, and `removeAll()` bulk operation APIs to simple, async-safe, and TTL cache interfaces.
- Added TTL-aware `setAll()` overloads so batches can receive a shared per-entry TTL override through TTL abstractions.

### Documentation

- Documented conditional mutation helpers and clarified `getOrCompute()` same-instance serialization semantics.
- Documented bulk operation helpers and their cache policy side effects.

### Maintenance

- Added injectable clock support to `CacheMetrics` for deterministic eviction-window and dashboard tests.
- Expanded contract coverage for conditional mutation helpers, bulk operations, TTL helper forwarding, and TTL `getOrCompute()` concurrent computation behavior.

## 2.3.0 - Peek, Occupancy APIs, and TTL Purge Cleanup

### Documentation

- Expanded the runnable example and README cache-aside snippets to cover both `getOrSet()` and TTL-aware `getOrCompute()`.
- Documented the non-mutating `peek()` API across README and cache guides.
- Documented occupancy APIs (`size`, `isEmpty`, and `isNotEmpty`) across README and cache guides.
- Documented explicit TTL expiry cleanup with `purgeExpired()`.

### New Features

- Added `peek()` to simple, async-safe, monitored, and TTL cache variants so callers can read values without updating cache eviction state.
- Added `size`, `isEmpty`, and `isNotEmpty` to simple, async-safe, monitored, and TTL cache variants so callers can inspect cache occupancy without materializing keys directly.
- Added `purgeExpired()` to `SimpleTTLCache`, `TTLCache`, `MonitoredTTLCache`, and the TTL cache interfaces so callers can explicitly remove expired TTL entries and inspect how many were removed.

### Maintenance

- Updated dependency constraints for `synchronized` and `lints` to the newest resolvable versions for the current SDK range.
- Added regression coverage for `peek()` nullable-value behavior, policy side effects, monitored traffic metrics, and TTL expiry.
- Added regression coverage for cache occupancy APIs across standard, simple, monitored, ephemeral, and TTL caches.
- Added regression coverage for explicit TTL expiry cleanup and monitored eviction metrics.

## 2.2.0 - Simple TTL Cache, Cache-Aside Helpers, and Contract Coverage

### New Features

- **SimpleTTLCache**: Added a synchronous TTL cache variant with global and per-entry TTL, lazy expiry, `containsKey()`, optional `maxSize`, and FIFO capacity eviction.
- **TTL cache interfaces**: Added `SimpleTTLCacheInterface` and `ThreadSafeTTLCacheInterface` so abstract cache references can still expose per-entry TTL overrides.
- **Cache-aside population**: Added `getOrSet()` to simple caches and `getOrCompute()` to async-safe caches, including TTL per-entry override support through TTL-specific interfaces.

### Documentation

- Added runnable package examples covering `SimpleTTLCache`, `TTLCache`, and monitored cache dashboard snapshots.
- Documented synchronous TTL usage in the README and TTL guide.
- Documented TTL-specific interfaces for callers that need per-entry expiry through cache abstractions.
- Documented `getKeys()` ordering contracts, `Disposable` lifecycle behavior, and bounded `CacheMetrics` sample storage.

### Maintenance

- Added regression coverage for `SimpleTTLCache`, `TTLCache`, and `MonitoredTTLCache` through the new TTL-specific interfaces.
- Added regression coverage for cache-aside population, `dispose()` idempotency, post-dispose operations, and `getKeys()` ordering contracts.

## 2.1.0 - Monitored TTL Cache, containsKey API, and Monitoring Improvements

### New Features

- **MonitoredTTLCache**: Added a monitored TTL cache variant with hit/miss and latency metrics, eviction tracking for expiry/capacity/manual removals, alert support, and the same TTL configuration options as `TTLCache`.
- **containsKey() API**: Added `containsKey()` to simple, async-safe, monitored, and TTL cache variants so callers can distinguish stored `null` values from missing keys without mutating eviction state.
- **CacheMetricsSnapshot**: Added a typed `CacheMetrics.snapshot(Duration window)` API with hit/miss rates, latency percentiles, eviction rate, total requests, and capture time.
- **Monitored cache constructors**: Made `CacheAlertConfig` optional for monitored cache variants by providing a default no-op alert callback and default thresholds.

### Performance

- **MonitoredLFUCache**: Replaced O(n) eviction scans with frequency buckets for constant-time LFU eviction.
- **CacheMetrics**: Reused a single sorted latency snapshot when computing multiple percentiles for metrics snapshots and dashboards.
- **TTLCache**: Added a capacity benchmark to quantify expired-entry cleanup and FIFO capacity enforcement costs.

### Bug Fixes

- **Nullable monitored values**: Fixed monitored caches so stored `null` values are recorded as hits when the key exists.
- **TTLCache**: Validates `sweepInterval` and per-entry TTL values so zero or negative intervals fail fast.
- **CacheStatsDashboard**: Migrated dashboard snapshots to the typed metrics snapshot source for consistent captured timestamps and metric values.

### Documentation

- Clarified async-safe cache contracts and isolate boundaries for `ThreadSafeCache` implementations.
- Documented `containsKey()` semantics, nullable value behavior, and TTL expiry behavior.
- Documented MonitoredTTLCache usage in the TTL guide and README.
- Clarified monitored cache `toString()` output as diagnostic point-in-time state.

### Maintenance

- Split CI formatting suggestions into a separate least-privilege Reviewdog job.
- Reduced default workflow token permissions to read-only for CI jobs.
- Added regression coverage for nullable cached values, `containsKey()` policy side effects, monitored cache constructors, metrics snapshots, and MonitoredTTLCache expiry paths.

## 2.0.1 - LFU Performance Improvements, Bug Fixes, and Maintenance

### Performance

- **LFUCache**: Replaced O(n) eviction scan with an O(1) frequency-bucket structure. Eviction is now constant-time regardless of cache size.
- **LFUCache**: Eliminated O(n) `_minFreq` recomputation in `remove()`. The minimum-frequency pointer is now maintained incrementally.

### Bug Fixes

- **LFUCache**: `toString()` now eagerly snapshots `_keyMap` before formatting, preventing a data-race window between the map read and string construction in async contexts.

### Documentation

- **LFUCache**: Class-level note added clarifying that `toString()` is not covered by the lock-based thread-safety guarantee; result is a point-in-time snapshot.
- **LFUCache**: Documented unspecified iteration order for `getKeys()` and `toString()`.
- **LRUCache / MRUCache**: Documented LRU-recency-refresh behavior of `set()` on an existing key and the tiebreak semantics.

### Maintenance

- Adjusted SDK constraint floor to `>=3.8.0` (minimum required by `synchronized ^3.4.0`)
- Kept `synchronized` at `^3.3.1` (resolves to 3.4.0+1 in practice, which requires SDK >=3.8.0)
- Updated `lints` dev dependency from `^5.0.0` to `^5.1.1` to align with the revised SDK baseline
- Raised `test` dev dependency from `^1.25.8` to `^1.31.0` (resolved: 1.31.1)
- Removed `dart_code_metrics ^5.7.6` (incompatible with the `analyzer` versions required by modern test tooling)
- CI: Added matrix testing across Dart 3.8.0 and stable; updated GitHub Actions to v4; optimized permissions and tightened job timeouts; added Reviewdog-based format suggestions on PR
- Added `.fvm/` and `.fvmrc` to `.gitignore`
- No public API changes; no breaking changes

## 2.0.0 - CacheStatsDashboard, TTLCache, and Lifecycle Management

### New Features

- **CacheStatsDashboard**: New class that wraps `CacheMetrics` to produce typed `DashboardSnapshot` objects for terminal-ready metric display.
- **TTLCache**: Added a standalone cache implementation supporting Time-To-Live (TTL) for both global and per-entry expiry.
- **Disposable Interface**: Introduced a standard `Disposable` interface to handle resource cleanup (timers, controllers) across monitored and TTL caches.
- **DashboardSnapshot**: Immutable value type capturing `hitRate`, `missRate`, latency percentiles (`p50`, `p95`, `p99`), `evictionsPerMinute`, `totalRequests`, and `capturedAt`.
- **formatDashboard()**: New top-level function that renders a `DashboardSnapshot` as a Unicode box-drawing terminal panel with adaptive unit formatting (µs, ms, s).

### Breaking Changes

- **Interface Implementation**: All `Monitored*` caches and `TTLCache` now implement `Disposable`. Callers managing these instances should call `.dispose()` to prevent timer leaks.
- `CacheStatsDashboard.snapshot(Duration window)` now throws `ArgumentError` for zero or negative `window` values (previously undefined behaviour propagated from `CacheMetrics.getRecentStats`).
- `CacheStatsDashboard.stream(Duration window, Duration interval)` now throws `ArgumentError` for zero or negative `interval` values.

## 1.1.5 - Bug Fixes

- Fixed spurious eviction in FIFO `set()` when updating an existing key.
- Fixed unawaited `Future` in LFU/MRU eviction causing silent async errors.
- Fixed LFU `set()` incorrectly resetting usage count and spuriously evicting when updating an existing key.
- Fixed unbounded memory growth in `CacheMetrics` by capping stored latency samples.
- Fixed miss latency silently discarded in `CacheMetrics`/`CacheMonitoring`.
- Fixed incorrect cache descriptions for LRU and MRU.

## 1.1.4 - Add Project Logo to README

- Added project logo to README header for improved visual branding.

## 1.1.3 - Add Cache Algorithm Documentation

- Added documentation for Cache algorithms to the README.
- Updated Dart SDK constraints to require version 3.7.2 or higher in `pubspec.yaml`.

## 1.1.2 - Add Badges to README

- Added the following badges to the README:
  - Dart CI Badge
  - OpenSSF Scorecard Badge
  - Codecov Badge
  - Documentation Badge

## 1.1.1 - Maintenance and Dependency Updates

- Renamed `docs` directory to `doc` to comply with pub.dev package layout convention.
- Updated dependencies:
  - Resolved version constraints for `lints`, `synchronized`, and `js` packages.
- Refactored project structure for improved consistency across environments.
- No functionality changes; preparation for release and ongoing maintenance.

## 1.1.0 - Introduce MonitoredCache with Performance Metrics

### New Features

- **MonitoredCache**: Added a new cache variant with built-in performance monitoring.
  - Tracks **hit rate, miss rate, request latency, and eviction events**.
  - Provides percentile-based latency insights (e.g., **p95, p99**).
  - Includes an **alert system** that triggers warnings when performance thresholds are exceeded.
  - Supports **FIFO, LRU, MRU, LFU**, and **EphemeralFIFO** strategies.
- **Updated README**:
  - Introduced MonitoredCache as a tool for **debugging and optimizing cache selection**.
  - Added **API references** and **usage instructions** for monitored caches.
  - Provided a link to **detailed documentation** in `docs/monitored_cache.md`.

This update enables developers to **analyze cache performance in real-time** and choose the optimal caching strategy based on actual usage patterns.

## 1.0.2 - Improve package description

- Updated the `description` field in `pubspec.yaml` to meet `pub.dev` requirements.
- Expanded the package description to provide a clearer explanation of its functionality and target use cases.

## 1.0.1 - Fix description in pubspec.yaml

- Updated the `description` field in `pubspec.yaml` to provide a more specific and accurate explanation of the package's functionality.

## 1.0.0 - Initial release

- First release of `cacherine` package on pub.dev
- Provides basic memory cache implementations: FIFO, LRU, MRU, and LFU
- Includes two types of cache implementations:
  - Simple, single-threaded usage
  - Async-enabled versions for concurrent environments
- Designed to provide flexible, easy-to-use caching solutions for Dart applications

This is the first stable release. Feedback and contributions are welcome!
