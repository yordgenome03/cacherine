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

  /// **Retrieves values for all currently present [keys].**
  ///
  /// Missing keys are omitted from the returned map. Stored `null` values are
  /// included when `V` is nullable.
  ///
  /// Implementations that update access state from [get] apply the same access
  /// behavior for each present key.
  Future<Map<K, V>> getAll(Iterable<K> keys) async {
    final values = <K, V>{};
    for (final key in keys) {
      if (await containsKey(key)) {
        values[key] = await get(key) as V;
      }
    }
    return values;
  }

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

  /// **Stores all key-value pairs from [entries].**
  ///
  /// Each entry follows the same behavior as [set], including eviction policy
  /// effects.
  Future<void> setAll(Map<K, V> entries) async {
    for (final entry in entries.entries) {
      await set(entry.key, entry.value);
    }
  }

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

  /// **Stores and returns a value only when [key] is absent.**
  ///
  /// If [key] is already present, the existing value is returned and
  /// [valueFactory] is not called. Stored `null` values are treated as present.
  ///
  /// Implementations may override this method to make the
  /// check/compute/store sequence atomic for their synchronization model.
  Future<V> putIfAbsent(K key, FutureOr<V> Function() valueFactory) =>
      getOrCompute(key, valueFactory);

  /// **Updates the value for [key] and returns the new value.**
  ///
  /// If [key] is absent and [ifAbsent] is provided, [ifAbsent] supplies the
  /// value to store. If [key] is absent and [ifAbsent] is omitted, this throws
  /// [StateError].
  ///
  /// Implementations may override this method to make the read/update/store
  /// sequence atomic for their synchronization model.
  Future<V> update(
    K key,
    FutureOr<V> Function(V value) update, {
    FutureOr<V> Function()? ifAbsent,
  }) async {
    if (await containsKey(key)) {
      final value = await update(await get(key) as V);
      await set(key, value);
      return value;
    }
    if (ifAbsent == null) {
      throw StateError('Cannot update missing cache key: $key');
    }
    final value = await ifAbsent();
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

  /// **Removes all entries with keys in [keys].**
  ///
  /// Missing keys are ignored.
  Future<void> removeAll(Iterable<K> keys) async {
    for (final key in keys) {
      await remove(key);
    }
  }

  /// **Removes all entries that match [test].**
  ///
  /// The predicate receives a snapshot value for each key that is still present
  /// when it is visited.
  Future<void> removeWhere(FutureOr<bool> Function(K key, V value) test) async {
    for (final key in (await getKeys()).toList()) {
      if (!await containsKey(key)) continue;
      final value = await peek(key) as V;
      if (await test(key, value)) {
        await remove(key);
      }
    }
  }

  /// **Removes all data stored in the cache (asynchronously).**
  Future<void> clear();
}
