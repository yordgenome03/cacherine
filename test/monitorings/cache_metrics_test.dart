import 'package:cacherine/src/monitorings/cache_metrics.dart';
import 'package:test/test.dart';

void main() {
  group('CacheMetrics - Basic Functionality', () {
    test('Hit and miss recording works correctly', () {
      final metrics = CacheMetrics();

      metrics.recordHit(const Duration(milliseconds: 10));
      metrics.recordHit(const Duration(milliseconds: 20));
      metrics.recordMiss();
      metrics.recordMiss();
      metrics.recordMiss();

      expect(metrics.hits, equals(2));
      expect(metrics.misses, equals(3));
      expect(metrics.totalRequests, equals(5));
    });

    test('Hit rate and miss rate calculations are correct', () {
      final metrics = CacheMetrics();

      metrics.recordHit(const Duration(milliseconds: 10));
      metrics.recordHit(const Duration(milliseconds: 20));
      metrics.recordMiss();
      metrics.recordMiss();

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
        metrics.recordMiss();
        metrics.recordEviction();

        await Future.delayed(
          const Duration(seconds: 2),
        ); // Simulate passage of time

        metrics.recordHit(const Duration(milliseconds: 25));
        metrics.recordMiss();
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
      metrics.recordMiss();
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
}
