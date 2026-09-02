import 'dart:math';

import 'package:cacherine/src/caches/fifo_cache.dart';
import 'package:test/test.dart';

/// An independent, deliberately naive reference model of FIFO semantics — see
/// `model_based_lru_cache_test.dart` for the methodology this mirrors.
///
/// Insertion order is eviction order. Unlike LRU/MRU, neither reading
/// (`get`/`peek`) nor overwriting an existing key's value changes its
/// position — the only thing that ever moves a key is inserting it for the
/// first time.
class _FifoModel {
  _FifoModel(this.maxSize);
  final int maxSize;
  final _map =
      <String, int>{}; // insertion order == eviction order (oldest first)

  void set(String key, int value) {
    if (!_map.containsKey(key)) _evictIfNeeded();
    _map[key] = value; // overwrite preserves position; insert appends
  }

  /// Mirrors `get()`: FIFO's `access()` never reorders, so this is
  /// equivalent to [peek].
  int? get(String key) => _map[key];

  /// Mirrors `peek()`: reads without affecting order.
  int? peek(String key) => _map[key];

  bool containsKey(String key) => _map.containsKey(key);

  void remove(String key) => _map.remove(key);

  void clear() => _map.clear();

  Set<String> get keys => _map.keys.toSet();

  void _evictIfNeeded() {
    if (_map.length >= maxSize) {
      _map.remove(_map.keys.first); // oldest inserted is evicted first
    }
  }
}

void main() {
  group('FIFOCache model-based differential test', () {
    test('matches an independent reference model over random operation '
        'sequences', () async {
      const seedCount = 50;
      const stepsPerRun = 200;
      const keyPoolSize = 6;

      for (var seed = 0; seed < seedCount; seed++) {
        final random = Random(seed);
        final maxSize = 2 + random.nextInt(5); // 2..6
        final cache = FIFOCache<String, int>(maxSize);
        final model = _FifoModel(maxSize);
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
                final expected = model.get(key); // hit: no reorder for FIFO
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
                final existing = model.get(
                  key,
                )!; // mirrors composedUpdate's read
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
                // writeThrough; FIFO position is unaffected by an update to
                // an already-present key, unlike LRU/MRU.
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
          // happened to look right.
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
