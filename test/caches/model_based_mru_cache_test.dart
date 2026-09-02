import 'dart:math';

import 'package:cacherine/src/caches/mru_cache.dart';
import 'package:test/test.dart';

/// An independent, deliberately naive reference model of MRU semantics — see
/// `model_based_lru_cache_test.dart` for the methodology this mirrors.
///
/// Reading or writing an entry moves it to the most-recently-used (tail)
/// position, same as LRU — but eviction removes that *same* tail entry
/// (`MRUStore._findVictim` walks from `_order.last`), not the head. Because a
/// brand-new key would itself become the tail the instant it's inserted,
/// eviction here must run **before** the insert (mirroring `Cache._write`'s
/// evict-before-put, `excluding: key`), never after — unlike the LRU model,
/// which can safely evict-after-insert since a fresh key can never be its
/// own least-recently-used victim.
class _MruModel {
  _MruModel(this.maxSize);
  final int maxSize;
  final _map =
      <
        String,
        int
      >{}; // insertion order == recency order (tail == most-recently-used)

  void set(String key, int value) {
    if (!_map.containsKey(key)) _evictIfNeeded();
    _map.remove(key);
    _map[key] = value; // (re)insert at the most-recently-used (tail) position
  }

  /// Mirrors `get()`: returns the value and moves the key to
  /// most-recently-used, or returns `null` without side effects if absent.
  int? get(String key) {
    if (!_map.containsKey(key)) return null;
    final value = _map.remove(key) as int;
    _map[key] = value;
    return value;
  }

  /// Mirrors `peek()`: reads without affecting recency.
  int? peek(String key) => _map[key];

  bool containsKey(String key) => _map.containsKey(key);

  void remove(String key) => _map.remove(key);

  void clear() => _map.clear();

  Set<String> get keys => _map.keys.toSet();

  void _evictIfNeeded() {
    if (_map.length >= maxSize) {
      _map.remove(
        _map.keys.last,
      ); // the most-recently-used entry is evicted first
    }
  }
}

void main() {
  group('MRUCache model-based differential test', () {
    test('matches an independent reference model over random operation '
        'sequences', () async {
      const seedCount = 50;
      const stepsPerRun = 200;
      const keyPoolSize = 6;

      for (var seed = 0; seed < seedCount; seed++) {
        final random = Random(seed);
        final maxSize = 2 + random.nextInt(5); // 2..6
        final cache = MRUCache<String, int>(maxSize);
        final model = _MruModel(maxSize);
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
                final expected = model.get(key); // hit: moves to MRU
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
                model.set(key, expected); // writeThrough; moves to MRU too
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
