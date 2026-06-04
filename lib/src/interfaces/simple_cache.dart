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

  /// **Returns the number of entries currently stored in the cache.**
  ///
  /// TTL cache implementations count only live, non-expired entries.
  int get size => getKeys().length;

  /// **Returns whether the cache currently has no entries.**
  bool get isEmpty => size == 0;

  /// **Returns whether the cache currently has one or more entries.**
  bool get isNotEmpty => !isEmpty;

  /// **Retrieves the value associated with the specified key.**
  ///
  /// - **Returns `null` if the key does not exist.**
  ///
  /// **Arguments:**
  /// - `key`: The key for the data to retrieve.
  ///
  /// **Returns:** The value associated with the key, or `null`.
  V? get(K key);

  /// **Retrieves the value for [key] without updating cache access state.**
  ///
  /// This method returns `null` if the key does not exist. Package cache
  /// implementations override this method so it does not update eviction policy
  /// state such as LRU/MRU order, LFU frequency, or Ephemeral FIFO consumption.
  ///
  /// Custom cache implementations should override this method when [get] has
  /// side effects.
  V? peek(K key) => get(key);

  /// **Checks whether the specified key is currently stored in the cache.**
  ///
  /// This method distinguishes a present key with a `null` value from an
  /// absent key.
  ///
  /// **Arguments:**
  /// - `key`: The key to check.
  ///
  /// **Returns:** `true` if the key exists, otherwise `false`.
  bool containsKey(K key);

  /// **Stores the specified key-value pair in the cache.**
  ///
  /// - If the key already exists, its corresponding value is updated.
  ///
  /// **Arguments:**
  /// - `key`: The key for the data to store.
  /// - `value`: The value of the data to store.
  void set(K key, V value);

  /// **Returns the existing value for [key], or stores and returns a new one.**
  ///
  /// Presence is checked with [containsKey], so a stored `null` value is treated
  /// as an existing value when `V` is nullable.
  ///
  /// Implementations that update access state from [get] apply the same access
  /// behavior when the key already exists.
  V getOrSet(K key, V Function() valueFactory) {
    if (containsKey(key)) {
      return get(key) as V;
    }
    final value = valueFactory();
    set(key, value);
    return value;
  }

  /// **Stores and returns a value only when [key] is absent.**
  ///
  /// If [key] is already present, the existing value is returned and
  /// [valueFactory] is not called. Stored `null` values are treated as present.
  V putIfAbsent(K key, V Function() valueFactory) =>
      getOrSet(key, valueFactory);

  /// **Updates the value for [key] and returns the new value.**
  ///
  /// If [key] is absent and [ifAbsent] is provided, [ifAbsent] supplies the
  /// value to store. If [key] is absent and [ifAbsent] is omitted, this throws
  /// [StateError].
  V update(K key, V Function(V value) update, {V Function()? ifAbsent}) {
    if (containsKey(key)) {
      final value = update(get(key) as V);
      set(key, value);
      return value;
    }
    if (ifAbsent == null) {
      throw StateError('Cannot update missing cache key: $key');
    }
    final value = ifAbsent();
    set(key, value);
    return value;
  }

  /// **Removes the entry with the given key from the cache.**
  ///
  /// - If the key does not exist, this call is a no-op.
  ///
  /// **Arguments:**
  /// - `key`: The key of the entry to remove.
  void remove(K key);

  /// **Removes all entries that match [test].**
  ///
  /// The predicate receives a snapshot value for each key that is still present
  /// when it is visited.
  void removeWhere(bool Function(K key, V value) test) {
    for (final key in getKeys().toList()) {
      if (!containsKey(key)) continue;
      final value = peek(key) as V;
      if (test(key, value)) {
        remove(key);
      }
    }
  }

  /// **Removes all data stored in the cache.**
  void clear();
}
