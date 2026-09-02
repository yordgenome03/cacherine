// Regression coverage for the pre-v3 public API: every bounded cache class
// exposed a non-nullable `int maxSize` field. The v3 engine refactor made
// `Cache.maxSize`/`AsyncCache.maxSize` nullable (since a composed cache may
// have no entry-count cap at all), so every named, always-bounded facade
// must narrow it back to non-nullable `int` to keep `int limit = cache.maxSize`
// compiling for existing callers.
import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  group('maxSize is a non-nullable int on every bounded facade', () {
    test('Simple tier', () {
      int limit;
      limit = SimpleLRUCache<String, String>(5).maxSize;
      expect(limit, equals(5));
      limit = SimpleMRUCache<String, String>(5).maxSize;
      expect(limit, equals(5));
      limit = SimpleFIFOCache<String, String>(5).maxSize;
      expect(limit, equals(5));
      limit = SimpleEphemeralFIFOCache<String, String>(5).maxSize;
      expect(limit, equals(5));
      limit = SimpleLFUCache<String, String>(5).maxSize;
      expect(limit, equals(5));
    });

    test('async tier', () {
      int limit;
      limit = LRUCache<String, String>(5).maxSize;
      expect(limit, equals(5));
      limit = MRUCache<String, String>(5).maxSize;
      expect(limit, equals(5));
      limit = FIFOCache<String, String>(5).maxSize;
      expect(limit, equals(5));
      limit = EphemeralFIFOCache<String, String>(5).maxSize;
      expect(limit, equals(5));
      limit = LFUCache<String, String>(5).maxSize;
      expect(limit, equals(5));
    });

    test('Monitored tier', () {
      final config = CacheAlertConfig(notifyCallback: (_) {});
      int limit;
      limit = MonitoredLRUCache<String, String>(
        maxSize: 5,
        alertConfig: config,
      ).maxSize;
      expect(limit, equals(5));
      limit = MonitoredMRUCache<String, String>(
        maxSize: 5,
        alertConfig: config,
      ).maxSize;
      expect(limit, equals(5));
      limit = MonitoredFIFOCache<String, String>(
        maxSize: 5,
        alertConfig: config,
      ).maxSize;
      expect(limit, equals(5));
      limit = MonitoredEphemeralFIFOCache<String, String>(
        maxSize: 5,
        alertConfig: config,
      ).maxSize;
      expect(limit, equals(5));
      limit = MonitoredLFUCache<String, String>(
        maxSize: 5,
        alertConfig: config,
      ).maxSize;
      expect(limit, equals(5));
    });
  });

  group('maxSize stays nullable where it always was optional', () {
    test('Cache/AsyncCache/MonitoredCache power-user engine', () {
      final cache = Cache<String, String>(
        store: LRUStore<String, String>(),
        weigher: (k, v) => v.length,
        maxWeight: 10,
      );
      expect(cache.maxSize, isNull);
    });

    test('Weighted facades, where maxSize was always optional', () {
      final cache = SimpleWeightedLRUCache<String, String>(
        weigher: (k, v) => v.length,
        maxWeight: 10,
      );
      expect(cache.maxSize, isNull);
    });
  });
}
