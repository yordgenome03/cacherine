import 'package:cacherine/src/monitorings/cache_metrics.dart';
import 'package:cacherine/src/monitorings/eviction_reason.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;
  DateTime clock() => now;

  setUp(() {
    now = DateTime(2026, 5, 15, 12);
  });

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

    test('getLatencyPercentile()/averageLatency return Duration.zero with '
        'no samples recorded', () {
      final metrics = CacheMetrics();

      expect(metrics.averageLatency, equals(Duration.zero));
      expect(metrics.getLatencyPercentile(50), equals(Duration.zero));
      expect(metrics.getLatencyPercentile(95), equals(Duration.zero));
      expect(metrics.getLatencyPercentile(99), equals(Duration.zero));
    });

    test('getLatencyPercentile()/averageLatency with exactly one sample '
        'return that sample for every percentile', () {
      final metrics = CacheMetrics();
      metrics.recordHit(const Duration(milliseconds: 7));

      expect(metrics.averageLatency, equals(const Duration(milliseconds: 7)));
      expect(
        metrics.getLatencyPercentile(50),
        equals(const Duration(milliseconds: 7)),
      );
      expect(
        metrics.getLatencyPercentile(99),
        equals(const Duration(milliseconds: 7)),
      );
    });

    // Regression coverage: the even-length median branch used to truncate
    // each of the two middle samples to whole milliseconds via
    // `.inMilliseconds` before averaging, discarding all sub-millisecond
    // precision — realistic for an in-memory cache, whose actual latencies
    // are far below 1ms. `averageLatency` never had this truncation, so the
    // two could (and did) disagree for the same data.
    test('getLatencyPercentile(50) preserves sub-millisecond precision for '
        'an even sample count', () {
      final metrics = CacheMetrics();
      metrics.recordHit(const Duration(microseconds: 400));
      metrics.recordHit(const Duration(microseconds: 800));

      expect(
        metrics.getLatencyPercentile(50),
        equals(const Duration(microseconds: 600)),
      );
      expect(metrics.averageLatency, equals(const Duration(microseconds: 600)));
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
    test('snapshot() returns typed metric values', () {
      final metrics = CacheMetrics(clock: clock)
        ..recordHit(const Duration(milliseconds: 10))
        ..recordHit(const Duration(milliseconds: 20))
        ..recordMiss(const Duration(milliseconds: 30))
        ..recordEviction();

      final snapshot = metrics.snapshot(const Duration(minutes: 1));

      expect(snapshot.hitRate, closeTo(2 / 3, 0.001));
      expect(snapshot.missRate, closeTo(1 / 3, 0.001));
      expect(snapshot.averageLatency, const Duration(milliseconds: 20));
      expect(snapshot.p50Latency, const Duration(milliseconds: 20));
      expect(snapshot.p95Latency, const Duration(milliseconds: 20));
      expect(snapshot.p99Latency, const Duration(milliseconds: 20));
      expect(snapshot.evictionsPerMinute, equals(1));
      expect(snapshot.totalRequests, equals(3));
      expect(snapshot.capturedAt, equals(now));
    });

    test('getRecentStats() is backed by snapshot values', () {
      final metrics = CacheMetrics()
        ..recordHit(const Duration(milliseconds: 10))
        ..recordMiss(const Duration(milliseconds: 30));

      final stats = metrics.getRecentStats(const Duration(minutes: 1));

      expect(stats['hit_rate'], equals(0.5));
      expect(stats['miss_rate'], equals(0.5));
      expect(stats['average_latency'], equals(20));
      expect(stats['p50_latency'], equals(20));
      expect(stats['p95_latency'], equals(10));
      expect(stats['p99_latency'], equals(10));
    });

    test(
      'getRecentStats() filters eviction events based on the injected clock',
      () {
        final metrics = CacheMetrics(clock: clock);

        metrics.recordHit(const Duration(milliseconds: 15));
        metrics.recordMiss(Duration.zero);
        metrics.recordEviction();

        now = now.add(const Duration(seconds: 2));

        metrics.recordHit(const Duration(milliseconds: 25));
        metrics.recordMiss(Duration.zero);
        metrics.recordEviction();

        final recentStats = metrics.getRecentStats(const Duration(seconds: 1));

        expect(recentStats['hit_rate'], equals(0.5));
        expect(recentStats['miss_rate'], equals(0.5));
        expect(recentStats['evictions_per_minute'], equals(60));
      },
    );

    // Regression/spec coverage: unlike evictionsPerMinute (computed from a
    // filtered, timestamped event log), hitRate/missRate are plain
    // cumulative counters (_hits / _totalRequests) — snapshot()'s `window`
    // parameter never filters them. A long-past bad stretch therefore stays
    // baked into hitRate forever, diluting only as *more* traffic
    // accumulates, never expiring out of a recent window the way eviction
    // stats do. The test above happens to use a 1:1 hit/miss ratio in both
    // halves, so it can't tell a windowed rate from a cumulative one apart
    // — this pins down the distinction directly.
    test('hitRate/missRate are cumulative for the instance\'s lifetime, not '
        'filtered by snapshot()\'s window — unlike evictionsPerMinute', () {
      final metrics = CacheMetrics(clock: clock);

      // An old, all-miss stretch.
      for (var i = 0; i < 8; i++) {
        metrics.recordMiss(Duration.zero);
      }

      now = now.add(const Duration(minutes: 10));

      // A recent, all-hit stretch — if hitRate were window-filtered, a
      // short window here would report hitRate == 1.0.
      for (var i = 0; i < 2; i++) {
        metrics.recordHit(Duration.zero);
      }

      final shortWindow = metrics.snapshot(const Duration(seconds: 1));
      final longWindow = metrics.snapshot(const Duration(minutes: 30));

      // Both windows see the exact same cumulative rate: 2 hits / 10
      // total, regardless of how narrow the window is.
      expect(shortWindow.hitRate, equals(0.2));
      expect(longWindow.hitRate, equals(0.2));
      expect(shortWindow.hitRate, equals(longWindow.hitRate));
      expect(shortWindow.totalRequests, equals(longWindow.totalRequests));
    });
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

    test(
      'getRecentStats() with positive sub-millisecond Duration succeeds',
      () {
        final metrics = CacheMetrics();
        expect(
          () => metrics.getRecentStats(const Duration(microseconds: 1)),
          returnsNormally,
        );
      },
    );

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

    test('snapshot() stays fast even at the full maxEvictionSamples retention '
        'cap — a coarse smoke test against an accidental O(n²) regression '
        'in the per-snapshot window scan, not a precise benchmark', () {
      final metrics = CacheMetrics();
      for (var i = 0; i < CacheMetrics.maxEvictionSamples; i++) {
        metrics.recordEviction();
      }
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        metrics.snapshot(const Duration(minutes: 1));
      }
      stopwatch.stop();
      // 200 snapshot() calls, each doing an O(n) scan of 10,000 retained
      // samples, is comfortably sub-second on any CI machine; a regression
      // to something quadratic (or worse) in the retained-sample count
      // would blow well past this bound.
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });

    test(
      'a sustained eviction storm well past maxEvictionSamples still reports '
      'a correct rate for only the requested recent window, not the full '
      'retained history',
      () {
        final metrics = CacheMetrics(clock: clock);

        // 15,000 evictions, one simulated second apart — 50% more than
        // maxEvictionSamples (10,000), so the oldest 5,000 are already
        // rolled off the retained queue by the time this finishes.
        // Alternates reason so both buckets get exercised.
        for (var i = 0; i < 15000; i++) {
          metrics.recordEvictionReason(
            i.isEven ? EvictionReason.capacity : EvictionReason.weight,
          );
          now = now.add(const Duration(seconds: 1));
        }

        // Only the last 60 simulated seconds of activity should count
        // toward a 1-minute window — not the 10,000 retained samples, and
        // definitely not all 15,000 that ever happened.
        final snapshot = metrics.snapshot(const Duration(minutes: 1));
        final total = snapshot.evictionsPerMinuteByReason.values.fold(
          0,
          (a, b) => a + b,
        );
        expect(total, inInclusiveRange(55, 60));
        expect(
          snapshot.evictionsPerMinuteByReason[EvictionReason.capacity],
          isNotNull,
        );
        expect(
          snapshot.evictionsPerMinuteByReason[EvictionReason.weight],
          isNotNull,
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

  group('CacheMetricsSnapshot - Immutability', () {
    test('evictionsPerMinuteByReason cannot be mutated by callers', () {
      final metrics = CacheMetrics();
      metrics.recordEvictionReason(EvictionReason.capacity);
      final snapshot = metrics.snapshot(const Duration(minutes: 1));

      expect(
        () => snapshot.evictionsPerMinuteByReason[EvictionReason.weight] = 1,
        throwsUnsupportedError,
      );
    });
  });
}
