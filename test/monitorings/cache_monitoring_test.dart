import 'package:cacherine/src/caches/fifo_cache.dart';
import 'package:cacherine/src/monitorings/cache_monitoring.dart';
import 'package:test/test.dart';

class TestCache with CacheMonitoring<String, String> {}

void main() {
  group('CacheMonitoring - Basic Functionality', () {
    test('monitoredGet() records cache hit correctly', () async {
      final cache = FIFOCache<String, String>(3);
      final monitoringCache = TestCache();

      await cache.set('key1', 'value1');
      final result = await monitoringCache.monitoredGet('key1', () async {
        return await cache.get('key1');
      });

      expect(result, equals('value1'));
      expect(monitoringCache.metrics.hits, equals(1));
      expect(monitoringCache.metrics.misses, equals(0));
    });

    test('monitoredGet() records cache miss correctly', () async {
      final cache = FIFOCache<String, String>(3);
      final monitoringCache = TestCache();

      final result = await monitoringCache.monitoredGet('key1', () async {
        return await cache.get('key1'); // key1 does not exist yet
      });

      expect(result, isNull);
      expect(monitoringCache.metrics.hits, equals(0));
      expect(monitoringCache.metrics.misses, equals(1));
    });
  });

  group('CacheMonitoring - Performance Monitoring', () {
    test('monitoredGet() measures latency', () async {
      final cache = FIFOCache<String, String>(3);
      final monitoringCache = TestCache();

      await cache.set('key1', 'value1');

      // Start stopwatch before calling monitoredGet()
      final stopwatch = Stopwatch()..start();

      // Perform 1000 operations to ensure latency is measurable
      for (int i = 0; i < 1000; i++) {
        await monitoringCache.monitoredGet('key1', () async {
          return await cache.get('key1');
        });
      }

      stopwatch.stop();

      // Expect the elapsed time to be greater than 0ms after 1000 operations
      print('Elapsed time: ${stopwatch.elapsedMilliseconds} ms');
      expect(stopwatch.elapsedMilliseconds, greaterThan(0));
    });
  });

  group('CacheMonitoring - Concurrent Operations', () {
    test('monitoredGet() handles concurrent operations safely', () async {
      final cache = FIFOCache<String, String>(1000);
      final monitoringCache = TestCache();

      // Perform 1000 parallel set & get operations
      final futures = List.generate(1000, (i) async {
        await cache.set('key$i', 'value$i');
        return await monitoringCache.monitoredGet('key$i', () async {
          return await cache.get('key$i');
        });
      });

      // Wait for all async operations to complete
      await Future.wait(futures);

      // Confirm that keys 0 to 999 were handled
      for (int i = 0; i < 1000; i++) {
        expect(await cache.get('key$i'), equals('value$i'));
      }

      // Check the metrics to ensure that hits and misses are counted properly
      expect(monitoringCache.metrics.hits, equals(1000));
      expect(monitoringCache.metrics.misses, equals(0));
    });
  });

  group('CacheMonitoring - Edge Case Handling', () {
    test('monitoredGet() handles empty cache gracefully', () async {
      final cache = FIFOCache<String, String>(3);
      final monitoringCache = TestCache();

      final result = await monitoringCache.monitoredGet('key1', () async {
        return await cache.get('key1');
      });

      expect(result, isNull);
      expect(monitoringCache.metrics.hits, equals(0));
      expect(monitoringCache.metrics.misses, equals(1));
    });
  });
}
