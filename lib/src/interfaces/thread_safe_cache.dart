/// **Async-safe Cache Interface**
///
/// An abstract class defining basic cache operations for asynchronous use.
///
/// Implementations serialize concurrent async calls on the same cache instance
/// within the same isolate. They are not shared-memory synchronization
/// primitives across Dart isolates.
abstract class ThreadSafeCache<K, V> {
  /// **Retrieves all keys stored in the cache.**
  ///
  /// **Returns:** A snapshot of all keys in the cache at the time of the call.
  Future<Iterable<K>> getKeys();

  /// **Retrieves the value associated with the specified key (asynchronously).**
  ///
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **Arguments:**
  /// - `key`: The key for the data to retrieve.
  ///
  /// **Returns:** `Future<V?>` (The value associated with the key, or `null`).
  Future<V?> get(K key);

  /// **Stores the specified key-value pair in the cache (asynchronously).**
  ///
  /// - If the key already exists, its corresponding value is updated.
  ///
  /// **Arguments:**
  /// - `key`: The key for the data to store.
  /// - `value`: The value of the data to store.
  Future<void> set(K key, V value);

  /// **Removes the entry with the given key from the cache (asynchronously).**
  ///
  /// - If the key does not exist, this call is a no-op.
  /// - The operation is executed inside the instance's lock to prevent data races.
  ///
  /// **Arguments:**
  /// - `key`: The key of the entry to remove.
  Future<void> remove(K key);

  /// **Removes all data stored in the cache (asynchronously).**
  Future<void> clear();
}
