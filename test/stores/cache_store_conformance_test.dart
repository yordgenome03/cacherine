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
  });
}
