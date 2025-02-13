/// **Simple Cache Interface**
///
/// An abstract class defining the **basic operations of a non-thread-safe cache**.
/// - Designed for use in **single-threaded environments**.
/// - Provides basic operations for **getting, saving, and deleting keys**.
abstract class SimpleCache<K, V> {
  /// **Retrieves all keys stored in the cache.**
  ///
  /// **Returns:** A list of all keys in the cache.
  Iterable<K> getKeys();

  /// **Retrieves the value associated with the specified key.**
  ///
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **Arguments:**
  /// - `key`: The key for the data to retrieve.
  ///
  /// **Returns:** The value associated with the key, or `null`.
  V? get(K key);

  /// **Stores the specified key-value pair in the cache.**
  ///
  /// - If the key already exists, its corresponding value is updated.
  ///
  /// **Arguments:**
  /// - `key`: The key for the data to store.
  /// - `value`: The value of the data to store.
  void set(K key, V value);

  /// **Removes all data stored in the cache.**
  void clear();
}
