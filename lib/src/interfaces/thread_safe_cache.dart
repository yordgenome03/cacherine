/// **Thread-safe Cache Interface**
///
/// An abstract class defining the basic cache operations for **multi-threaded environments**
/// and **asynchronous processing**.
/// - Provides **thread-safe cache operations** using **asynchronous processing (`Future`)**.
/// - Designed to **safely handle access from multiple threads**.
abstract class ThreadSafeCache<K, V> {
  /// **Retrieves all keys stored in the cache.**
  ///
  /// **Returns:** A list of all keys in the cache.
  Iterable<K> getKeys();

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

  /// **Removes all data stored in the cache (asynchronously).**
  Future<void> clear();
}
