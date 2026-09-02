library;

// Interfaces
export 'src/interfaces/disposable.dart';
export 'src/interfaces/periodic_sweeper.dart';
export 'src/interfaces/simple_cache.dart';
export 'src/interfaces/simple_ttl_cache.dart';
export 'src/interfaces/thread_safe_cache.dart';
export 'src/interfaces/thread_safe_ttl_cache.dart';
export 'src/interfaces/weigher.dart';

// Monitorings
export 'src/monitorings/cache_alert_manager.dart';
export 'src/monitorings/cache_metrics.dart';
export 'src/monitorings/cache_monitoring.dart';
export 'src/monitorings/cache_stats_dashboard.dart';
export 'src/monitorings/eviction_reason.dart';

// Eviction-policy stores (for the composable Cache/AsyncCache/MonitoredCache
// engine below, and for anyone implementing a custom CacheStore)
export 'src/stores/cache_store.dart';
export 'src/stores/ephemeral_fifo_store.dart';
export 'src/stores/fifo_store.dart';
export 'src/stores/lfu_store.dart';
export 'src/stores/lru_store.dart';
export 'src/stores/mru_store.dart';
export 'src/stores/ttl_fifo_store.dart';

// Composable cache engine — power users needing a capacity/weight/TTL
// combination without a dedicated named class below can configure this
// directly; every named class in this file is a thin facade over it.
export 'src/caches/async_cache.dart';
export 'src/caches/cache.dart';
export 'src/caches/monitored_cache.dart';

// Simple Caches
export 'src/caches/simple_ephemeral_fifo_cache.dart';
export 'src/caches/simple_fifo_cache.dart';
export 'src/caches/simple_lru_cache.dart';
export 'src/caches/simple_mru_cache.dart';
export 'src/caches/simple_lfu_cache.dart';
export 'src/caches/simple_ttl_cache.dart';
export 'src/caches/simple_weighted_lru_cache.dart';

// Standard Caches
export 'src/caches/ephemeral_fifo_cache.dart';
export 'src/caches/fifo_cache.dart';
export 'src/caches/lru_cache.dart';
export 'src/caches/mru_cache.dart';
export 'src/caches/lfu_cache.dart';
export 'src/caches/weighted_lru_cache.dart';

// Monitored Caches
export 'src/caches/monitored_ephemeral_fifo_cache.dart';
export 'src/caches/monitored_fifo_cache.dart';
export 'src/caches/monitored_lru_cache.dart';
export 'src/caches/monitored_mru_cache.dart';
export 'src/caches/monitored_lfu_cache.dart';
export 'src/caches/monitored_ttl_cache.dart';
export 'src/caches/monitored_weighted_lru_cache.dart';

// TTL Cache
export 'src/caches/ttl_cache.dart';
