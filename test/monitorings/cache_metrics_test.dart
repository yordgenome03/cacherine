import 'package:cacherine/src/monitorings/cache_metrics.dart';
import 'package:test/test.dart';

void main() {
  group('CacheMetrics - Basic Functionality', () {
    test('Hit and miss recording works correctly', () {
      final metrics = CacheMetrics();

      metrics.recordHit(const Duration(milliseconds: 10));
      metrics.recordHit(const Duration(milliseconds: 20));
      metrics.recordMiss(Duration.zero);
      metrics.recordMiss(Duration.zero);
      metrics.recordMiss(Duration.zero);

      expect(metrics.hits, equals(2));
      expect(metrics.misses, equals(3));
      expect(metrics.totalRequests, equals(5));
    });

    test('Hit rate and miss rate calculations are correct', () {
      final metrics = CacheMetrics();

      metrics.recordHit(const Duration(milliseconds: 10));
      metrics.recordHit(const Duration(milliseconds: 20));
      metrics.recordMiss(Duration.zero);
      metrics.recordMiss(Duration.zero);

      expect(metrics.hitRate, closeTo(0.5, 0.01)); // 2/4 = 0.5
      expect(metrics.missRate, closeTo(0.5, 0.01)); // 2/4 = 0.5
    });

    test('Latency calculations (average & percentiles) work correctly', () {
      final metrics = CacheMetrics();

      metrics.recordHit(const Duration(milliseconds: 10));
      metrics.recordHit(const Duration(milliseconds: 20));
      metrics.recordHit(const Duration(milliseconds: 30));
      metrics.recordHit(const Duration(milliseconds: 40));

      expect(
        metrics.averageLatency.inMilliseconds,
        equals(25),
      ); // (10+20+30+40) / 4 = 25
      expect(
        metrics.getLatencyPercentile(50).inMilliseconds,
        equals(25),
      ); // 50th percentile = median
      expect(
        metrics.getLatencyPercentile(100).inMilliseconds,
        equals(40),
      ); // 100th percentile = max value
    });

    test('averageLatency includes miss samples', () {
      final metrics = CacheMetrics();

      metrics.recordHit(const Duration(milliseconds: 10));
      metrics.recordHit(const Duration(milliseconds: 20));
      metrics.recordMiss(const Duration(milliseconds: 30));

      // (10 + 20 + 30) / 3 = 20ms
      expect(metrics.averageLatency.inMilliseconds, equals(20));
    });

    test('Evictions are recorded correctly', () {
      final metrics = CacheMetrics();

      metrics.recordEviction();
      metrics.recordEviction();
      metrics.recordEviction();

      expect(
        metrics.getRecentStats(
          const Duration(minutes: 1),
        )['evictions_per_minute'],
        greaterThan(0),
      );
    });
  });

  group('CacheMetrics - Time Window Stats', () {
    test(
      'getRecentStats() filters events correctly based on time window',
      () async {
        final metrics = CacheMetrics();

        metrics.recordHit(const Duration(milliseconds: 15));
        metrics.recordMiss(Duration.zero);
        metrics.recordEviction();

        await Future.delayed(
          const Duration(seconds: 2),
        ); // Simulate passage of time

        metrics.recordHit(const Duration(milliseconds: 25));
        metrics.recordMiss(Duration.zero);
        metrics.recordEviction();

        final recentStats = metrics.getRecentStats(const Duration(seconds: 1));

        expect(
          recentStats['hit_rate'],
          equals(0.5),
        ); // Only the last hit/miss counts
        expect(recentStats['miss_rate'], equals(0.5));
        expect(recentStats['evictions_per_minute'], greaterThan(0));
      },
    );
  });

  group('CacheMetrics - Reset Functionality', () {
    test('reset() clears all recorded data', () {
      final metrics = CacheMetrics();

      metrics.recordHit(const Duration(milliseconds: 10));
      metrics.recordMiss(Duration.zero);
      metrics.recordEviction();

      metrics.reset();

      expect(metrics.hits, equals(0));
      expect(metrics.misses, equals(0));
      expect(metrics.totalRequests, equals(0));
      expect(metrics.averageLatency.inMilliseconds, equals(0));
      expect(
        metrics.getRecentStats(
          const Duration(minutes: 1),
        )['evictions_per_minute'],
        equals(0),
      );
    });
  });

  group('CacheMetrics - getRecentStats() validation', () {
    test('getRecentStats(Duration.zero) throws ArgumentError', () {
      final metrics = CacheMetrics();
      expect(
        () => metrics.getRecentStats(Duration.zero),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getRecentStats() with negative Duration throws ArgumentError', () {
      final metrics = CacheMetrics();
      expect(
        () => metrics.getRecentStats(const Duration(milliseconds: -1)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getRecentStats() with positive Duration succeeds', () {
      final metrics = CacheMetrics();
      expect(
        () => metrics.getRecentStats(const Duration(minutes: 1)),
        returnsNormally,
      );
    });
  });

  group('CacheMetrics - Bounded Storage', () {
    test(
      '_latencies does not exceed maxLatencySamples entries after many recordHit calls',
      () {
        final metrics = CacheMetrics();
        // First hit: 0ms. Next maxLatencySamples hits: 100ms each.
        // The 0ms entry is rolled off when the cap is reached.
        metrics.recordHit(Duration.zero);
        for (var i = 0; i < CacheMetrics.maxLatencySamples; i++) {
          metrics.recordHit(const Duration(milliseconds: 100));
        }
        // Bounded (1 000 entries, all 100ms) → average = 100ms.
        // Unbounded (1 001 entries) → average = 100 000 / 1 001 ≈ 99ms.
        expect(metrics.averageLatency.inMilliseconds, equals(100));
      },
    );

    test(
      'averageLatency reflects the most recent maxLatencySamples after cap is exceeded',
      () {
        final metrics = CacheMetrics();
        for (var i = 0; i < CacheMetrics.maxLatencySamples; i++) {
          metrics.recordHit(Duration.zero);
        }
        metrics.recordHit(
          const Duration(milliseconds: CacheMetrics.maxLatencySamples),
        );
        // Bounded: oldest 0ms entry dropped → [0×999, 1000ms] → average = 1ms.
        // Unbounded: [0×1000, 1000ms] → average = 1000/1001 ≈ 0ms.
        expect(metrics.averageLatency.inMilliseconds, equals(1));
      },
    );

    test(
      'getLatencyPercentile operates on the most recent maxLatencySamples after cap',
      () {
        final metrics = CacheMetrics();
        for (var i = 0; i < CacheMetrics.maxLatencySamples; i++) {
          metrics.recordHit(const Duration(milliseconds: 5));
        }
        metrics.recordHit(const Duration(milliseconds: 100));
        // Most-recent entry (100ms) must be retained; oldest 5ms entry is dropped.
        expect(metrics.getLatencyPercentile(100).inMilliseconds, equals(100));
        // 999 entries at 5ms dominate, so median is 5ms.
        expect(metrics.getLatencyPercentile(50).inMilliseconds, equals(5));
      },
    );

    test(
      '_evictions does not exceed maxEvictionSamples entries after many recordEviction calls',
      () {
        final metrics = CacheMetrics();
        for (var i = 0; i < CacheMetrics.maxEvictionSamples + 1; i++) {
          metrics.recordEviction();
        }
        // All evictions happened now → all within a 1-minute window.
        // evictions_per_minute = recentEvictions × 60000 / 60000 = recentEvictions.
        // Bounded: 10 000. Unbounded: 10 001.
        final stats = metrics.getRecentStats(const Duration(minutes: 1));
        expect(
          stats['evictions_per_minute'],
          equals(CacheMetrics.maxEvictionSamples),
        );
      },
    );

    test(
      'getRecentStats evictions_per_minute is correct when eviction count is within cap',
      () {
        final metrics = CacheMetrics();
        for (var i = 0; i < 60; i++) {
          metrics.recordEviction();
        }
        expect(
          metrics.getRecentStats(
            const Duration(minutes: 1),
          )['evictions_per_minute'],
          equals(60),
        );
      },
    );

    test(
      'hits, misses, and totalRequests remain exact beyond the latency cap',
      () {
        final metrics = CacheMetrics();
        const totalHits = CacheMetrics.maxLatencySamples * 2;
        const totalMisses = 500;
        for (var i = 0; i < totalHits; i++) {
          metrics.recordHit(const Duration(milliseconds: 1));
        }
        for (var i = 0; i < totalMisses; i++) {
          metrics.recordMiss(Duration.zero);
        }
        expect(metrics.hits, equals(totalHits));
        expect(metrics.misses, equals(totalMisses));
        expect(metrics.totalRequests, equals(totalHits + totalMisses));
      },
    );

    test('reset() clears bounded stores and resets counters to zero', () {
      final metrics = CacheMetrics();
      for (var i = 0; i < 100; i++) {
        metrics.recordHit(const Duration(milliseconds: 5));
        metrics.recordEviction();
      }
      metrics.reset();
      expect(metrics.hits, equals(0));
      expect(metrics.misses, equals(0));
      expect(metrics.totalRequests, equals(0));
      expect(metrics.averageLatency, equals(Duration.zero));
      expect(
        metrics.getRecentStats(
          const Duration(minutes: 1),
        )['evictions_per_minute'],
        equals(0),
      );
    });
  });
}
