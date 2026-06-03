import 'dart:async';

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

  /// **Returns the number of entries currently stored in the cache.**
  ///
  /// TTL cache implementations count only live, non-expired entries.
  Future<int> get size async => (await getKeys()).length;

  /// **Returns whether the cache currently has no entries.**
  Future<bool> get isEmpty async => (await size) == 0;

  /// **Returns whether the cache currently has one or more entries.**
  Future<bool> get isNotEmpty async => !(await isEmpty);

  /// **Retrieves the value associated with the specified key (asynchronously).**
  ///
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **Arguments:**
  /// - `key`: The key for the data to retrieve.
  ///
  /// **Returns:** `Future<V?>` (The value associated with the key, or `null`).
  Future<V?> get(K key);

  /// **Retrieves the value for [key] without updating cache access state.**
  ///
  /// This method returns `null` if the key does not exist. Package cache
  /// implementations override this method so it does not update eviction policy
  /// state such as LRU/MRU order, LFU frequency, or Ephemeral FIFO consumption.
  ///
  /// Custom cache implementations should override this method when [get] has
  /// side effects.
  Future<V?> peek(K key) => get(key);

  /// **Checks whether the specified key is currently stored in the cache.**
  ///
  /// This method distinguishes a present key with a `null` value from an
  /// absent key.
  ///
  /// **Arguments:**
  /// - `key`: The key to check.
  ///
  /// **Returns:** `Future<bool>` (`true` if the key exists, otherwise `false`).
  Future<bool> containsKey(K key);

  /// **Stores the specified key-value pair in the cache (asynchronously).**
  ///
  /// - If the key already exists, its corresponding value is updated.
  ///
  /// **Arguments:**
  /// - `key`: The key for the data to store.
  /// - `value`: The value of the data to store.
  Future<void> set(K key, V value);

  /// **Returns the existing value for [key], or computes, stores, and returns a new one.**
  ///
  /// Presence is checked with [containsKey], so a stored `null` value is treated
  /// as an existing value when `V` is nullable.
  ///
  /// Implementations may override this method to make the check/compute/store
  /// sequence atomic for their synchronization model.
  Future<V> getOrCompute(K key, FutureOr<V> Function() valueFactory) async {
    if (await containsKey(key)) {
      return await get(key) as V;
    }
    final value = await valueFactory();
    await set(key, value);
    return value;
  }

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
