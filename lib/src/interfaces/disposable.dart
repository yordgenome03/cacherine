/// **Disposable Interface**
///
/// Defines a **lifecycle contract for objects that hold resources requiring explicit cleanup**.
/// - Implemented by all `Monitored*` cache classes (`MonitoredLRUCache`, `MonitoredMRUCache`,
///   `MonitoredFIFOCache`, `MonitoredLFUCache`, `MonitoredEphemeralFIFOCache`), each of which
///   starts an internal `Timer.periodic` that must be cancelled to prevent resource leaks.
/// - Calling `dispose()` cancels the alert-monitoring timer and releases all references held
///   by the cache's `CacheAlertManager`.
/// - **`dispose()` is idempotent**: calling it more than once is safe and has no effect.
/// - After `dispose()` is called, cache read/write operations (`get()`, `set()`, etc.) continue
///   to function, but alert monitoring stops.
///
/// **Usage pattern:**
/// ```dart
/// final cache = MonitoredLRUCache<String, String>(
///   maxSize: 100,
///   alertConfig: CacheAlertConfig(notifyCallback: print),
/// );
/// // ... use the cache ...
/// cache.dispose(); // cancel the internal timer when done
/// ```
///
/// **Type-check pattern (when holding a `ThreadSafeCache` reference):**
/// ```dart
/// if (cache is Disposable) cache.dispose();
/// ```
abstract interface class Disposable {
  /// **Cancels any resources held by this object.**
  ///
  /// - Safe to call multiple times (idempotent).
  void dispose();
}
