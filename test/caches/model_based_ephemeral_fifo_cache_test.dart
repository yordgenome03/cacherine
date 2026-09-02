import 'dart:math';

import 'package:cacherine/src/caches/ephemeral_fifo_cache.dart';
import 'package:test/test.dart';

/// An independent, deliberately naive reference model of Ephemeral-FIFO
/// semantics — see `model_based_lru_cache_test.dart` for the methodology
/// this mirrors.
///
/// Same ordering as FIFO, but reading an entry (`get`) *removes* it —
/// retrieved data cannot be read twice; `peek` still reads without removing.
/// This makes `getOrCompute()`/`update()` on a hit behave differently from
/// every other policy: `composedGetOrCompute`/`composedUpdate` read a hit via
/// this class's own `get()`, which consumes the entry as a side effect.
/// `getOrCompute()` returns that value without writing anything back (a hit
/// is indistinguishable from a plain `get()` call — the entry is simply
/// gone afterward), while `update()` immediately re-`set()`s the freshly
/// computed value under the same key — which, because the key was just
/// removed by the read, is inserted as a brand-new entry and lands at the
/// **newest** (tail) position instead of staying put, unlike plain
/// `FIFOCache.update()`. Confirmed empirically against the real
/// `EphemeralFIFOCache` before encoding it here, since it's easy to assume
/// (incorrectly) that this class's `update()` preserves FIFO position the
/// same way `FIFOCache.update()` does.
class _EphemeralFifoModel {
  _EphemeralFifoModel(this.maxSize);
  final int maxSize;
  final _map =
      <String, int>{}; // insertion order == eviction order (oldest first)

  void set(String key, int value) {
    if (!_map.containsKey(key)) _evictIfNeeded();
    _map[key] = value; // overwrite preserves position; insert appends
  }

  /// Mirrors `get()`/`access()`: removes and returns the entry, or returns
  /// `null` without side effects if absent.
  int? get(String key) => _map.remove(key);

  /// Mirrors `peek()`: reads without removing.
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
  group('EphemeralFIFOCache model-based differential test', () {
    test('matches an independent reference model over random operation '
        'sequences', () async {
      const seedCount = 50;
      const stepsPerRun = 200;
      const keyPoolSize = 6;

      for (var seed = 0; seed < seedCount; seed++) {
        final random = Random(seed);
        final maxSize = 2 + random.nextInt(5); // 2..6
        final cache = EphemeralFIFOCache<String, int>(maxSize);
        final model = _EphemeralFifoModel(maxSize);
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

            case 1: // get (destructive)
              final actual = await cache.get(key);
              expect(actual, equals(model.get(key)), reason: '$context get()');
              break;

            case 2: // peek (non-destructive)
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
                // Hit: consumes the entry via the destructive get() — nothing
                // is written back, so the key disappears after this call.
                final expected = model.get(key);
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
                // Hit: the read consumes the entry (destructive get()), then
                // the write-through re-inserts it as a brand-new entry — it
                // lands at the newest (tail) position, not its old one.
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
