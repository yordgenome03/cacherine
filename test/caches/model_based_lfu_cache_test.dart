import 'dart:math';

import 'package:cacherine/src/caches/lfu_cache.dart';
import 'package:test/test.dart';

/// An independent, deliberately naive reference model of LFU semantics — see
/// `model_based_lru_cache_test.dart` for the methodology this mirrors.
///
/// The entry with the lowest access frequency is evicted first; ties break
/// by recency (the least-recently-touched entry among the lowest-frequency
/// group is evicted). A read (`get`) increments frequency; overwriting an
/// existing key via `set` deliberately does **not** — it only refreshes
/// recency within the key's current frequency, matching `LFUStore.put()`'s
/// documented "preserve frequency on update" contract. `peek` affects
/// neither. A brand-new key always starts at frequency 1 (the global
/// minimum) and, being freshly touched, can never itself be the
/// least-recently-touched candidate — so unlike MRU, eviction here is safe
/// to run either before or after the insert; this model runs it before,
/// for consistency with the MRU/FIFO/EphemeralFIFO models alongside it.
///
/// Recency is tracked as a monotonically increasing touch counter rather
/// than reordering a map, since (unlike the other four policies) LFU's
/// eviction order does not follow insertion/recency order directly — it's
/// keyed by frequency first — and `LFUCache.getKeys()`'s order is
/// documented as unspecified, so only the key *set* is cross-checked below.
class _LfuModel {
  _LfuModel(this.maxSize);
  final int maxSize;
  final _values = <String, int>{};
  final _freq = <String, int>{};
  final _touch = <String, int>{}; // higher == touched more recently
  int _clock = 0;

  void set(String key, int value) {
    final existed = _values.containsKey(key);
    if (!existed) {
      _evictIfNeeded();
      _freq[key] = 1;
    }
    _values[key] = value;
    _touch[key] = _clock++; // refresh recency regardless of hit/miss
  }

  /// Mirrors `get()`: promotes frequency and refreshes recency, or returns
  /// `null` without side effects if absent.
  int? get(String key) {
    if (!_values.containsKey(key)) return null;
    _freq[key] = _freq[key]! + 1;
    _touch[key] = _clock++;
    return _values[key];
  }

  /// Mirrors `peek()`: reads without affecting frequency or recency.
  int? peek(String key) => _values[key];

  bool containsKey(String key) => _values.containsKey(key);

  void remove(String key) {
    _values.remove(key);
    _freq.remove(key);
    _touch.remove(key);
  }

  void clear() {
    _values.clear();
    _freq.clear();
    _touch.clear();
  }

  Set<String> get keys => _values.keys.toSet();

  void _evictIfNeeded() {
    if (_values.length < maxSize) return;
    String? victim;
    for (final key in _values.keys) {
      if (victim == null ||
          _freq[key]! < _freq[victim]! ||
          (_freq[key] == _freq[victim] && _touch[key]! < _touch[victim]!)) {
        victim = key;
      }
    }
    remove(victim!);
  }
}

void main() {
  group('LFUCache model-based differential test', () {
    test('matches an independent reference model over random operation '
        'sequences', () async {
      const seedCount = 50;
      const stepsPerRun = 200;
      const keyPoolSize = 6;

      for (var seed = 0; seed < seedCount; seed++) {
        final random = Random(seed);
        final maxSize = 2 + random.nextInt(5); // 2..6
        final cache = LFUCache<String, int>(maxSize);
        final model = _LfuModel(maxSize);
        final keyPool = List.generate(keyPoolSize, (i) => 'k$i');

        for (var step = 0; step < stepsPerRun; step++) {
          final key = keyPool[random.nextInt(keyPool.length)];
          final context = 'seed=$seed step=$step key=$key';

          switch (random.nextInt(7)) {
            case 0: // set
              final value = random.nextInt(1000);
              await cache.set(key, value);
              model.set(key, value);
              break;

            case 1: // get
              final actual = await cache.get(key);
              expect(actual, equals(model.get(key)), reason: '$context get()');
              break;

            case 2: // peek
              final actual = await cache.peek(key);
              expect(
                actual,
                equals(model.peek(key)),
                reason: '$context peek()',
              );
              break;

            case 3: // containsKey
              expect(
                await cache.containsKey(key),
                equals(model.containsKey(key)),
                reason: '$context containsKey()',
              );
              break;

            case 4: // remove
              await cache.remove(key);
              model.remove(key);
              break;

            case 5: // getOrCompute
              if (model.containsKey(key)) {
                final expected = model.get(key); // hit: promotes frequency
                final actual = await cache.getOrCompute(key, () async => -1);
                expect(
                  actual,
                  equals(expected),
                  reason: '$context getOrCompute() [hit]',
                );
              } else {
                final value = random.nextInt(1000);
                final actual = await cache.getOrCompute(key, () async => value);
                expect(
                  actual,
                  equals(value),
                  reason: '$context getOrCompute() [miss]',
                );
                model.set(key, value);
              }
              break;

            case 6: // update (with ifAbsent, so it never throws)
              final delta = random.nextInt(100) + 1;
              if (model.containsKey(key)) {
                // Hit: the read (mirrors composedUpdate's get()) promotes
                // frequency once; the write-through set() on this now-
                // existing key does not promote it again.
                final existing = model.get(key)!;
                final expected = existing + delta;
                final actual = await cache.update(
                  key,
                  (v) async => v + delta,
                  ifAbsent: () async => delta,
                );
                expect(
                  actual,
                  equals(expected),
                  reason: '$context update() [existing]',
                );
                model.set(key, expected);
              } else {
                final actual = await cache.update(
                  key,
                  (v) async => v + delta,
                  ifAbsent: () async => delta,
                );
                expect(
                  actual,
                  equals(delta),
                  reason: '$context update() [ifAbsent]',
                );
                model.set(key, delta);
              }
              break;
          }

          // Cross-check the full key set after every single step — this is
          // where an eviction-order or bookkeeping drift would surface even
          // if the immediately-preceding operation's own return value
          // happened to look right. Only the *set* is compared, per
          // LFUCache.getKeys()'s documented unspecified order.
          expect(
            (await cache.getKeys()).toSet(),
            equals(model.keys),
            reason: '$context key-set mismatch after the operation above',
          );
        }

        await cache.clear();
        model.clear();
        expect(await cache.getKeys(), isEmpty);
      }
    });
  });
}
