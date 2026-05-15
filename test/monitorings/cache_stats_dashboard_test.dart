import 'package:cacherine/src/monitorings/cache_metrics.dart';
import 'package:cacherine/src/monitorings/cache_stats_dashboard.dart';
import 'package:test/test.dart';

DashboardSnapshot _makeSnap({
  double hitRate = 0.75,
  double missRate = 0.25,
  Duration averageLatency = const Duration(milliseconds: 10),
  Duration p50Latency = const Duration(milliseconds: 8),
  Duration p95Latency = const Duration(milliseconds: 20),
  Duration p99Latency = const Duration(milliseconds: 50),
  int evictionsPerMinute = 3,
  int totalRequests = 100,
  DateTime? capturedAt,
}) =>
    DashboardSnapshot(
      hitRate: hitRate,
      missRate: missRate,
      averageLatency: averageLatency,
      p50Latency: p50Latency,
      p95Latency: p95Latency,
      p99Latency: p99Latency,
      evictionsPerMinute: evictionsPerMinute,
      totalRequests: totalRequests,
      capturedAt: capturedAt ?? DateTime.now(),
    );

void main() {
  group('DashboardSnapshot', () {
    test('all fields have the declared types', () {
      final snap = _makeSnap();

      expect(snap.hitRate, isA<double>());
      expect(snap.missRate, isA<double>());
      expect(snap.averageLatency, isA<Duration>());
      expect(snap.p50Latency, isA<Duration>());
      expect(snap.p95Latency, isA<Duration>());
      expect(snap.p99Latency, isA<Duration>());
      expect(snap.evictionsPerMinute, isA<int>());
      expect(snap.totalRequests, isA<int>());
      expect(snap.capturedAt, isA<DateTime>());
    });

    test('fields return the values they were created with', () {
      final now = DateTime(2026, 5, 15, 12, 0, 0);
      final snap = _makeSnap(
        hitRate: 0.8,
        missRate: 0.2,
        averageLatency: const Duration(milliseconds: 15),
        p50Latency: const Duration(milliseconds: 12),
        p95Latency: const Duration(milliseconds: 30),
        p99Latency: const Duration(milliseconds: 80),
        evictionsPerMinute: 7,
        totalRequests: 500,
        capturedAt: now,
      );

      expect(snap.hitRate, equals(0.8));
      expect(snap.missRate, equals(0.2));
      expect(snap.averageLatency, equals(const Duration(milliseconds: 15)));
      expect(snap.p50Latency, equals(const Duration(milliseconds: 12)));
      expect(snap.p95Latency, equals(const Duration(milliseconds: 30)));
      expect(snap.p99Latency, equals(const Duration(milliseconds: 80)));
      expect(snap.evictionsPerMinute, equals(7));
      expect(snap.totalRequests, equals(500));
      expect(snap.capturedAt, equals(now));
    });
  });

  group('CacheStatsDashboard.snapshot()', () {
    test('capturedAt is within 1 second of call time', () {
      final metrics = CacheMetrics()
        ..recordHit(const Duration(milliseconds: 5));
      final dashboard = CacheStatsDashboard(metrics);

      final before = DateTime.now();
      final snap = dashboard.snapshot(const Duration(minutes: 1));
      final after = DateTime.now();

      expect(
        snap.capturedAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(
          before.millisecondsSinceEpoch - 1000,
        ),
      );
      expect(
        snap.capturedAt.millisecondsSinceEpoch,
        lessThanOrEqualTo(
          after.millisecondsSinceEpoch + 1000,
        ),
      );
    });

    test('snapshot returns metric values matching the wrapped CacheMetrics', () {
      final metrics = CacheMetrics()
        ..recordHit(const Duration(milliseconds: 10))
        ..recordHit(const Duration(milliseconds: 20))
        ..recordMiss(const Duration(milliseconds: 30));

      final snap =
          CacheStatsDashboard(metrics).snapshot(const Duration(minutes: 1));

      expect(snap.hitRate, closeTo(2 / 3, 0.001));
      expect(snap.missRate, closeTo(1 / 3, 0.001));
      expect(snap.totalRequests, equals(3));
    });

    test('throws ArgumentError on zero window', () {
      final dashboard = CacheStatsDashboard(CacheMetrics());
      expect(
        () => dashboard.snapshot(Duration.zero),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError on negative window', () {
      final dashboard = CacheStatsDashboard(CacheMetrics());
      expect(
        () => dashboard.snapshot(const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });
  });

  group('CacheStatsDashboard.stream()', () {
    test('emits DashboardSnapshot values', () async {
      final metrics = CacheMetrics()
        ..recordHit(const Duration(milliseconds: 5));
      final dashboard = CacheStatsDashboard(metrics);
      final snapshots = <DashboardSnapshot>[];

      final sub = dashboard
          .stream(
            const Duration(minutes: 1),
            const Duration(milliseconds: 50),
          )
          .listen(snapshots.add);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      await sub.cancel();

      expect(snapshots, isNotEmpty);
      expect(snapshots.first, isA<DashboardSnapshot>());
    });

    test('no further events emitted after cancellation', () async {
      final metrics = CacheMetrics()
        ..recordHit(const Duration(milliseconds: 5));
      final dashboard = CacheStatsDashboard(metrics);
      final snapshots = <DashboardSnapshot>[];

      final sub = dashboard
          .stream(
            const Duration(minutes: 1),
            const Duration(milliseconds: 50),
          )
          .listen(snapshots.add);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      final countAtCancel = snapshots.length;
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(snapshots.length, equals(countAtCancel));
    });
  });

  group('formatDashboard()', () {
    test('output contains Hit Rate, Latency, and Evictions labels', () {
      final output = formatDashboard(_makeSnap(hitRate: 0.8, missRate: 0.2));

      expect(output, contains('Hit Rate'));
      expect(output, contains('Latency'));
      expect(output, contains('Evictions'));
    });

    test('output contains box-drawing border characters', () {
      final output = formatDashboard(_makeSnap());

      expect(output, contains('┌'));
      expect(output, contains('┐'));
      expect(output, contains('└'));
      expect(output, contains('┘'));
      expect(output, contains('├'));
      expect(output, contains('┤'));
      expect(output, contains('│'));
    });

    test('hit-rate bar has exactly 10 filled and 10 empty cells for hitRate=0.5', () {
      final output = formatDashboard(_makeSnap(hitRate: 0.5, missRate: 0.5));

      expect('█'.allMatches(output).length, equals(10));
      expect('░'.allMatches(output).length, equals(10));
    });

    test('output includes capturedAt under Captured at: label', () {
      final capturedAt = DateTime(2026, 5, 15, 16, 10, 0);
      final output = formatDashboard(_makeSnap(capturedAt: capturedAt));

      expect(output, contains('Captured at:'));
      expect(output, contains('2026-05-15 16:10:00'));
    });

    test('latency uses µs unit for sub-millisecond values', () {
      final output = formatDashboard(
        _makeSnap(
          p50Latency: const Duration(microseconds: 250),
          p95Latency: const Duration(microseconds: 800),
          p99Latency: const Duration(microseconds: 999),
        ),
      );
      expect(output, contains('250µs'));
      expect(output, contains('800µs'));
      expect(output, contains('999µs'));
    });

    test('latency uses ms unit for millisecond values', () {
      final output = formatDashboard(
        _makeSnap(
          p50Latency: const Duration(milliseconds: 12),
          p95Latency: const Duration(milliseconds: 48),
          p99Latency: const Duration(milliseconds: 110),
        ),
      );
      expect(output, contains('12ms'));
      expect(output, contains('48ms'));
      expect(output, contains('110ms'));
    });

    test('latency uses s unit for second-level values', () {
      final output = formatDashboard(
        _makeSnap(
          p50Latency: const Duration(milliseconds: 1200),
          p95Latency: const Duration(milliseconds: 3500),
          p99Latency: const Duration(seconds: 5),
        ),
      );
      expect(output, contains('1.2s'));
      expect(output, contains('3.5s'));
      expect(output, contains('5.0s'));
    });
  });
}
