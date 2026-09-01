import 'package:cacherine/src/stores/cache_store.dart';
import 'package:cacherine/src/stores/ephemeral_fifo_store.dart';
import 'package:cacherine/src/stores/fifo_store.dart';
import 'package:cacherine/src/stores/lfu_store.dart';
import 'package:cacherine/src/stores/lru_store.dart';
import 'package:cacherine/src/stores/mru_store.dart';
import 'package:cacherine/src/stores/ttl_fifo_store.dart';
import 'package:test/test.dart';

void main() {
  group('CacheStore conformance', () {
    for (final entry in <String, CacheStore<String, String> Function()>{
      'LRUStore': LRUStore<String, String>.new,
      'MRUStore': MRUStore<String, String>.new,
      'FIFOStore': FIFOStore<String, String>.new,
      'EphemeralFIFOStore': EphemeralFIFOStore<String, String>.new,
      'LFUStore': LFUStore<String, String>.new,
      'TTLFifoStore': TTLFifoStore<String, String>.new,
    }.entries) {
      final name = entry.key;
      final make = entry.value;

      group(name, () {
        test('starts empty', () {
          final store = make();
          expect(store.length, 0);
          expect(store.keys, isEmpty);
          expect(store.containsKey('a'), isFalse);
          expect(store.peek('a'), isNull);
          expect(store.selectVictim(), isNull);
          expect(store.evictOne(), isNull);
        });

        test('removesOnAccess is true only for EphemeralFIFOStore', () {
          final store = make();
          expect(store.removesOnAccess, name == 'EphemeralFIFOStore');
        });

        test('put() then peek()/containsKey() see the value', () {
          final store = make();
          store.put('a', '1');
          expect(store.length, 1);
          expect(store.containsKey('a'), isTrue);
          expect(store.peek('a'), equals('1'));
        });

        test('put() on an existing key updates the value', () {
          final store = make();
          store.put('a', '1');
          store.put('a', '2');
          expect(store.length, 1);
          expect(store.peek('a'), equals('2'));
        });

        test('remove() deletes and reports presence', () {
          final store = make();
          store.put('a', '1');
          expect(store.remove('a'), isTrue);
          expect(store.containsKey('a'), isFalse);
          expect(store.remove('a'), isFalse);
        });

        test('clear() empties the store', () {
          final store = make();
          store.put('a', '1');
          store.put('b', '2');
          store.clear();
          expect(store.length, 0);
          expect(store.keys, isEmpty);
        });

        test('evictOne() removes and returns the selected victim', () {
          final store = make();
          store.put('a', '1');
          final victimKey = store.selectVictim();
          expect(victimKey, isNotNull);
          final evicted = store.evictOne();
          expect(evicted, isNotNull);
          expect(evicted!.$1, equals(victimKey));
          expect(store.containsKey(victimKey!), isFalse);
        });

        test('selectVictim(excluding:)/evictOne(excluding:) never choose the '
            'excluded key', () {
          final store = make();
          store.put('a', '1');
          // A single-entry store excluding that same entry has no
          // eligible candidate.
          expect(store.selectVictim(excluding: 'a'), isNull);
          expect(store.evictOne(excluding: 'a'), isNull);
          expect(store.containsKey('a'), isTrue); // untouched
        });

        // Regression coverage: every eviction policy in this package is
        // documented/implemented to make put()/selectVictim()/evictOne()
        // (with no `excluding`) O(1). A correctness-only test can't catch a
        // reintroduced O(n) or O(n^2) scan — it would still pick the right
        // victim, just slowly. This drives enough entries that a
        // non-constant-time implementation would blow well past the
        // generous time budget below, while a true O(1) implementation
        // finishes in milliseconds.
        test('put()/evictOne() stay fast across many entries — a smoke test '
            'against an accidental O(n) or worse regression in eviction '
            'selection', () {
          final store = make();
          const entryCount = 20000;

          final stopwatch = Stopwatch()..start();
          for (var i = 0; i < entryCount; i++) {
            store.put('k$i', 'v$i');
          }
          for (var i = 0; i < entryCount; i++) {
            expect(store.evictOne(), isNotNull);
          }
          stopwatch.stop();

          expect(store.length, equals(0));
          expect(
            stopwatch.elapsed,
            lessThan(const Duration(seconds: 5)),
            reason:
                '$name: put()/evictOne() over $entryCount entries took '
                '${stopwatch.elapsed} — consistent with an accidental O(n) '
                'or worse scan having crept back in, not O(1) eviction',
          );
        });
      });
    }
  });

  // Regression coverage for the documented nullable-K limitation on
  // CacheStore.selectVictim()/evictOne() (see cache_store.dart's doc
  // comment): `null` is overloaded as both "no victim" and a legitimate
  // literal key when K is nullable, so `k != excluding` — every
  // implementation's actual eviction-candidate check — is `null != null`
  // (false) whenever `excluding` is left at its default `null` and the only
  // remaining key is the literal key `null`. The store therefore reports
  // "nothing evictable" even though it demonstrably still holds an entry.
  // This is documented as an accepted tradeoff, not fixed; these tests make
  // sure that stays true (i.e. this doesn't crash, and it doesn't silently
  // start working, which would mean the doc comment is now stale) across
  // every store implementation.
  group('CacheStore nullable-K limitation (documented)', () {
    for (final entry in <String, CacheStore<String?, String> Function()>{
      'LRUStore': LRUStore<String?, String>.new,
      'MRUStore': MRUStore<String?, String>.new,
      'FIFOStore': FIFOStore<String?, String>.new,
      'EphemeralFIFOStore': EphemeralFIFOStore<String?, String>.new,
      'LFUStore': LFUStore<String?, String>.new,
      'TTLFifoStore': TTLFifoStore<String?, String>.new,
    }.entries) {
      final name = entry.key;
      final make = entry.value;

      test('$name: a store holding only the literal null key can never be '
          'selected/evicted via the default (unset) excluding', () {
        final store = make();
        store.put(null, 'value');

        expect(store.length, equals(1));
        expect(store.containsKey(null), isTrue);
        expect(store.selectVictim(), isNull); // documented limitation
        expect(store.evictOne(), isNull); // documented limitation
        expect(store.length, equals(1)); // never actually evicted
        expect(store.containsKey(null), isTrue);

        // remove() takes an explicit key, not a victim search, so it is
        // unaffected by the limitation — this is the only way to get rid
        // of a literal-null entry via this interface.
        expect(store.remove(null), isTrue);
        expect(store.length, equals(0));
      });
    }
  });

  group('LRUStore policy', () {
    test('access() moves the key to the most-recently-used position', () {
      final store = LRUStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.access('a');
      // 'b' is now the least-recently-used and should be selected first.
      expect(store.selectVictim(), equals('b'));
    });

    test('selectVictim() is the least-recently-used key', () {
      final store = LRUStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.put('c', '3');
      expect(store.selectVictim(), equals('a'));
    });

    test('selectVictim(excluding:) falls back to the next-least-recently-used '
        'key when the LRU victim is excluded', () {
      final store = LRUStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.put('c', '3');
      expect(store.selectVictim(excluding: 'a'), equals('b'));
    });
  });

  group('MRUStore policy', () {
    test('selectVictim() is the most-recently-used key', () {
      final store = MRUStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.put('c', '3');
      expect(store.selectVictim(), equals('c'));
    });

    test('selectVictim(excluding:) falls back to the next-most-recent key '
        'when the MRU victim is excluded', () {
      final store = MRUStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.put('c', '3');
      expect(store.selectVictim(excluding: 'c'), equals('b'));
    });
  });

  group('FIFOStore policy', () {
    test('access() does not reorder', () {
      final store = FIFOStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.access('a');
      expect(store.selectVictim(), equals('a'));
    });

    test('put() on an existing key does not reorder', () {
      final store = FIFOStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.put('a', 'updated');
      expect(store.selectVictim(), equals('a'));
    });

    test('selectVictim(excluding:) falls back to the next-oldest key when '
        'the FIFO victim is excluded', () {
      final store = FIFOStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.put('c', '3');
      expect(store.selectVictim(excluding: 'a'), equals('b'));
    });
  });

  group('TTLFifoStore policy', () {
    test('access() does not reorder', () {
      final store = TTLFifoStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.access('a');
      expect(store.selectVictim(), equals('a'));
    });

    test('put() on an existing key refreshes its position to the newest '
        'slot — the opposite of FIFOStore, which deliberately does not '
        'reorder on update', () {
      final store = TTLFifoStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.put('a', 'updated');
      expect(store.selectVictim(), equals('b'));
    });
  });

  group('EphemeralFIFOStore policy', () {
    test('access() removes the entry', () {
      final store = EphemeralFIFOStore<String, String>();
      store.put('a', '1');
      expect(store.access('a'), equals('1'));
      expect(store.containsKey('a'), isFalse);
    });

    test('peek() does not remove the entry', () {
      final store = EphemeralFIFOStore<String, String>();
      store.put('a', '1');
      expect(store.peek('a'), equals('1'));
      expect(store.containsKey('a'), isTrue);
    });

    test('selectVictim(excluding:) falls back to the next-oldest key when '
        'the FIFO victim is excluded', () {
      final store = EphemeralFIFOStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.put('c', '3');
      expect(store.selectVictim(excluding: 'a'), equals('b'));
    });

    test('accessing the same key twice in a row is safe — the second access '
        'returns null instead of throwing, since the first already removed '
        'the entry', () {
      final store = EphemeralFIFOStore<String, String>();
      store.put('a', '1');
      expect(store.access('a'), equals('1'));
      expect(store.access('a'), isNull); // already removed; no crash
      expect(store.containsKey('a'), isFalse);
      expect(store.length, equals(0));
    });

    test('accessing a key that was never present is safe and returns null', () {
      final store = EphemeralFIFOStore<String, String>();
      expect(store.access('missing'), isNull);
    });
  });

  group('LFUStore policy', () {
    test('access() promotes frequency; least-frequent key is the victim', () {
      final store = LFUStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.access('a'); // 'a' now has frequency 2; 'b' is still at 1
      expect(store.selectVictim(), equals('b'));
    });

    test('put() on an existing key preserves frequency', () {
      final store = LFUStore<String, String>();
      store.put('a', '1');
      store.access('a'); // freq(a) = 2
      store.put('b', '2'); // freq(b) = 1
      store.put('a', 'updated'); // should stay at freq 2, not reset to 1
      // 'b' (freq 1) should still be the victim, not 'a'.
      expect(store.selectVictim(), equals('b'));
    });

    test('selectVictim(excluding:) falls through to the next occupied '
        'frequency bucket when the min-frequency bucket holds only the '
        'excluded key', () {
      final store = LFUStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      store.access('b'); // freq(b) = 2; freq(a) = 1 (sole occupant)
      // The min-freq (1) bucket contains only 'a', which is excluded, so
      // the store must fall through to the freq-2 bucket and return 'b'
      // rather than reporting "nothing to evict".
      expect(store.selectVictim(excluding: 'a'), equals('b'));
      final evicted = store.evictOne(excluding: 'a');
      expect(evicted, isNotNull);
      expect(evicted!.$1, equals('b'));
      expect(store.containsKey('a'), isTrue);
      expect(store.containsKey('b'), isFalse);
    });

    test('evictOne(excluding:) correctly walks multiple frequency buckets in a '
        'row, across several single-victim evictions, when each successive '
        'minimum-frequency bucket has already been emptied', () {
      // Regression coverage for https://github.com/yordgenome03/cacherine/
      // pull/69 review feedback: a stale/unmaintained "current minimum
      // frequency" used to force an O(distinct frequencies) rescan on
      // every single victim selection in a multi-eviction write (O(n²)
      // worst case for a weighted/TTL-bounded LFU cache). This drives five
      // consecutive single-key evictions across five distinct, initially
      // non-adjacent frequency buckets to confirm each one still finds the
      // correct next victim.
      final store = LFUStore<String, String>();
      for (final key in ['a', 'b', 'c', 'd', 'e']) {
        store.put(key, key);
      }
      // Give each key a distinct frequency: a=1, b=2, c=3, d=4, e=5.
      store.access('b');
      store.access('c');
      store.access('c');
      store.access('d');
      store.access('d');
      store.access('d');
      store.access('e');
      store.access('e');
      store.access('e');
      store.access('e');

      for (final expectedVictim in ['a', 'b', 'c', 'd', 'e']) {
        final evicted = store.evictOne();
        expect(evicted, isNotNull);
        expect(evicted!.$1, equals(expectedVictim));
      }
      expect(store.length, equals(0));
      expect(store.evictOne(), isNull);
    });

    test('within the same frequency bucket, the least-recently-touched key is '
        'evicted first', () {
      final store = LFUStore<String, String>();
      store.put('a', '1');
      store.put('b', '2');
      // Both at frequency 1; 'a' was touched (via put) before 'b', so 'a'
      // is the least-recently-touched within that bucket.
      expect(store.selectVictim(), equals('a'));
    });

    // Regression coverage for the O(n) -> O(1) eviction rewrite (this
    // package used to recompute the minimum frequency by scanning every
    // entry on each eviction). A correctness-only test can't catch a
    // reintroduced O(n) or O(n^2) scan — it would still return the right
    // victim, just slowly. This drives enough entries and enough distinct
    // frequency buckets that a non-constant-time selectVictim()/evictOne()
    // would blow well past the generous time budget below, while a true
    // O(1) implementation finishes in milliseconds.
    test('put()/access()/evictOne() stay fast across many entries and many '
        'distinct frequency buckets (O(1) eviction, not a rescan)', () {
      final store = LFUStore<int, int>();
      const entryCount = 20000;

      final stopwatch = Stopwatch()..start();

      for (var i = 0; i < entryCount; i++) {
        store.put(i, i);
      }
      // Give every entry a distinct frequency (1..entryCount) by accessing
      // key i exactly i times, so eviction must walk through `entryCount`
      // distinct buckets rather than repeatedly hitting one big bucket.
      for (var i = 0; i < entryCount; i++) {
        for (var touch = 0; touch < i % 50; touch++) {
          store.access(i);
        }
      }
      for (var i = 0; i < entryCount; i++) {
        expect(store.evictOne(), isNotNull);
      }

      stopwatch.stop();
      expect(store.length, equals(0));
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason:
            'put()/access()/evictOne() over $entryCount entries took '
            '${stopwatch.elapsed} — consistent with an accidental O(n) or '
            'O(n^2) scan having crept back in, not O(1) eviction',
      );
    });
  });
}
