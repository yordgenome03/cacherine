/// **Why a cache entry was evicted.**
///
/// Passed to [CacheMetrics.recordEvictionReason] so per-cause eviction rates can be
/// broken out in [CacheMetricsSnapshot.evictionsPerMinuteByReason] and
/// [CacheAlertConfig.evictionsPerReasonThreshold], in addition to the
/// existing aggregate [CacheMetricsSnapshot.evictionsPerMinute].
enum EvictionReason {
  /// The caller recorded an eviction without specifying a cause (the
  /// zero-argument `recordEviction()` call site, kept for callers written
  /// before this enum existed).
  unspecified,

  /// Removed to make room under an entry-count (`maxSize`) limit.
  capacity,

  /// Removed to make room under a weight (`maxWeight`) limit.
  weight,

  /// Removed because its TTL elapsed.
  expired,

  /// Removed by an explicit `remove()` call.
  manual,
}
