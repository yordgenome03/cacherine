import 'dart:async';
import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  group('CacheAlertConfig', () {
    test('default notify callback is a no-op', () {
      final config = CacheAlertConfig();

      expect(() => config.notifyCallback('ignored'), returnsNormally);
    });

    test('throws ArgumentError for zero alertCheckInterval', () {
      expect(
        () => CacheAlertConfig(alertCheckInterval: Duration.zero),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError for negative alertCheckInterval', () {
      expect(
        () => CacheAlertConfig(alertCheckInterval: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });
  });

  group('CacheAlertManager - Alert Triggering', () {
    late CacheMetrics metrics;
    late List<String> receivedAlerts;
    late CacheAlertManager alertManager;

    setUp(() {
      metrics = CacheMetrics();
      receivedAlerts = [];

      final config = CacheAlertConfig(
        notifyCallback: (alert) => receivedAlerts.add(alert),
        hitRateThreshold: 0.5,
        missRateThreshold: 0.5,
        p95LatencyThreshold: 200,
        p99LatencyThreshold: 300,
        evictionsPerMinuteThreshold: 1000,
        averageLatencyThreshold: 100,
        alertCheckInterval: const Duration(
          milliseconds: 100,
        ), // Fast check for test
      );

      alertManager = CacheAlertManager(metrics, config);
    });

    tearDown(() => alertManager.dispose());

    test('Triggers alert when hit rate is too low', () async {
      // 90% of requests are misses
      for (int i = 0; i < 10; i++) {
        metrics.recordMiss(Duration.zero);
      }
      metrics.recordHit(const Duration(milliseconds: 10));

      // Run the monitor and wait a bit to check the alerts
      alertManager.monitor();

      // Wait for 200ms to allow the alert manager to check the stats
      await Future.delayed(const Duration(milliseconds: 200));

      // Check if the alert for low hit rate was triggered, allowing the 'Actual' part
      expect(
        receivedAlerts.any(
          (alert) => alert.contains('Warning: Low hit rate detected'),
        ),
        isTrue,
      );
    });

    // Regression test: hitRate/missRate both default to 0 when
    // totalRequests is 0 (CacheMetrics' documented zero-traffic behavior),
    // and 0 is below almost any positive hitRateThreshold — a cache that
    // simply hasn't served any get()/getOrCompute() yet must not be
    // mistaken for one with a 0% hit rate.
    test('does not trigger a low hit rate alert on a freshly-constructed '
        'cache with zero traffic', () async {
      alertManager.monitor();

      await Future.delayed(const Duration(milliseconds: 200));

      expect(receivedAlerts, isEmpty);
    });

    // Regression coverage: every threshold in _checkAlerts uses a strict
    // inequality (`<`/`>`), so a metric exactly equal to its threshold must
    // NOT alert. Every existing test above only exercises "well past" the
    // threshold, which would not catch an accidental `<=`/`>=` flip. hitRate
    // is a pure ratio with no time-window dependency, so this is safe from
    // the real-clock timing jitter that would make a window-based metric
    // (e.g. evictionsPerMinute) flaky to pin to an exact boundary.
    test('does not alert when hitRate is exactly at the threshold — only '
        'strictly below alerts', () async {
      // 5 hits, 5 misses -> hitRate exactly 0.5, equal to the configured
      // threshold.
      for (var i = 0; i < 5; i++) {
        metrics.recordHit(Duration.zero);
      }
      for (var i = 0; i < 5; i++) {
        metrics.recordMiss(Duration.zero);
      }
      alertManager.monitor();
      await Future.delayed(const Duration(milliseconds: 200));
      expect(
        receivedAlerts.any(
          (alert) => alert.contains('Warning: Low hit rate detected'),
        ),
        isFalse,
      );

      // One more miss tips the rate just below the threshold.
      metrics.recordMiss(Duration.zero);
      await Future.delayed(const Duration(milliseconds: 200));
      expect(
        receivedAlerts.any(
          (alert) => alert.contains('Warning: Low hit rate detected'),
        ),
        isTrue,
      );
    });

    test('Triggers alert when miss rate is too high', () async {
      // 80% of requests are misses
      for (int i = 0; i < 8; i++) {
        metrics.recordMiss(Duration.zero);
      }
      for (int i = 0; i < 2; i++) {
        metrics.recordHit(const Duration(milliseconds: 10));
      }

      // Run the monitor and wait a bit to check the alerts
      alertManager.monitor();

      // Wait for 200ms to allow the alert manager to check the stats
      await Future.delayed(const Duration(milliseconds: 200));

      // Check if the alert for high miss rate was triggered
      expect(
        receivedAlerts.any(
          (alert) => alert.contains('Warning: High miss rate detected'),
        ),
        isTrue,
      );
    });
    test('Triggers alert when p95 latency exceeds threshold', () async {
      for (int i = 0; i < 20; i++) {
        metrics.recordHit(Duration(milliseconds: i * 40)); // Maximum of 760ms
      }

      // Run the monitor
      alertManager.monitor();

      // Wait for 500ms to ensure alert is triggered
      await Future.delayed(const Duration(milliseconds: 500));

      // Check if the alert for high p95 latency was triggered
      expect(
        receivedAlerts.any(
          (alert) => alert.contains('Warning: High p95 latency detected'),
        ),
        isTrue,
      );
    });

    test('Triggers alert when p99 latency exceeds threshold', () async {
      // Increase latencies to ensure p99 latency exceeds threshold (300ms)
      for (int i = 0; i < 15; i++) {
        metrics.recordHit(
          Duration(milliseconds: i * 40),
        ); // Latencies: 0, 40, ..., 560
      }

      // Run the monitor
      alertManager.monitor();

      // Wait for 500ms to ensure alert is triggered
      await Future.delayed(const Duration(milliseconds: 500));

      // Check if the alert for high p99 latency was triggered
      expect(
        receivedAlerts.any(
          (alert) => alert.contains('Warning: High p99 latency detected'),
        ),
        isTrue,
      );
    });

    test('Triggers alert when average latency exceeds threshold', () async {
      // Increase latencies to ensure average latency exceeds threshold (100ms)
      for (int i = 0; i < 10; i++) {
        metrics.recordHit(
          const Duration(milliseconds: 200),
        ); // Constant high latency (200ms)
      }

      // Run the monitor
      alertManager.monitor();

      // Wait for 500ms to ensure alert is triggered
      await Future.delayed(const Duration(milliseconds: 500));

      // Check if the alert for high average latency was triggered
      expect(
        receivedAlerts.any(
          (alert) => alert.contains('Warning: High average latency detected'),
        ),
        isTrue,
      );
    });

    test('Triggers alert when eviction rate exceeds threshold', () async {
      alertManager.dispose();
      final config = CacheAlertConfig(
        notifyCallback: (alert) => receivedAlerts.add(alert),
        evictionsPerMinuteThreshold: 1000,
        alertCheckInterval: const Duration(seconds: 1),
      );
      alertManager = CacheAlertManager(metrics, config);

      // Run the monitor
      alertManager.monitor();

      // Record evictions after the monitor starts so they are inside the first
      // one-second snapshot window even on slower SDK/runtime combinations.
      await Future.delayed(const Duration(milliseconds: 100));

      // Record evictions in bulk to reduce the loop overhead
      for (int i = 0; i < 500; i++) {
        metrics.recordEviction();
      }

      // Wait to ensure the monitoring catches the evictions
      await Future.delayed(const Duration(milliseconds: 1200));

      // Check if the alert for high eviction rate was triggered
      expect(
        receivedAlerts.any(
          (alert) => alert.contains('Warning: High eviction rate detected'),
        ),
        isTrue,
      );
    });

    test('Triggers a per-reason alert when evictionsPerReasonThreshold is '
        'exceeded for that reason', () async {
      alertManager.dispose();
      final config = CacheAlertConfig(
        notifyCallback: (alert) => receivedAlerts.add(alert),
        evictionsPerMinuteThreshold: 100000, // keep the aggregate alert off
        evictionsPerReasonThreshold: {EvictionReason.weight: 5},
        alertCheckInterval: const Duration(seconds: 1),
      );
      alertManager = CacheAlertManager(metrics, config);

      alertManager.monitor();
      await Future.delayed(const Duration(milliseconds: 100));

      for (int i = 0; i < 10; i++) {
        metrics.recordEvictionReason(EvictionReason.weight);
      }
      // A reason with no configured threshold must never alert, even with
      // more evictions than the reason that does have one.
      for (int i = 0; i < 50; i++) {
        metrics.recordEvictionReason(EvictionReason.expired);
      }

      await Future.delayed(const Duration(milliseconds: 1200));

      expect(
        receivedAlerts.any(
          (alert) => alert.contains('Warning: High weight eviction rate'),
        ),
        isTrue,
      );
      expect(
        receivedAlerts.any((alert) => alert.contains('expired eviction')),
        isFalse,
      );
    });

    // Regression coverage: same strict-inequality boundary concern as the
    // hitRate test above, but for a window-based metric. Real-clock timing
    // jitter would make an exact-boundary assertion flaky if the eviction
    // count within the "last N ms" depended on wall-clock elapsed time, so
    // this freezes CacheMetrics' clock — evictionsPerMinute then depends
    // only on how many recordEvictionReason() calls have happened, not on
    // how much real time passed between them and the timer tick.
    test('does not fire a per-reason alert when that reason is exactly at '
        'its threshold — only strictly above alerts', () async {
      alertManager.dispose();
      final frozenAt = DateTime(2024);
      final frozenMetrics = CacheMetrics(clock: () => frozenAt);
      final config = CacheAlertConfig(
        notifyCallback: (alert) => receivedAlerts.add(alert),
        evictionsPerMinuteThreshold: 1000000, // keep the aggregate alert off
        evictionsPerReasonThreshold: {EvictionReason.weight: 600},
        alertCheckInterval: const Duration(milliseconds: 100),
      );
      alertManager = CacheAlertManager(frozenMetrics, config);
      alertManager.monitor();

      // With a frozen clock, every recorded eviction is "at" the same
      // instant, so it always falls inside the window — 1 eviction over a
      // 100ms window scales to exactly 600/min (1 * 60000ms/min / 100ms),
      // precisely at the configured threshold.
      frozenMetrics.recordEvictionReason(EvictionReason.weight);
      await Future.delayed(const Duration(milliseconds: 250));
      expect(
        receivedAlerts.any(
          (alert) => alert.contains('Warning: High weight eviction rate'),
        ),
        isFalse,
      );

      // A second eviction doubles the rate to 1200/min, over the threshold.
      frozenMetrics.recordEvictionReason(EvictionReason.weight);
      await Future.delayed(const Duration(milliseconds: 250));
      expect(
        receivedAlerts.any(
          (alert) => alert.contains('Warning: High weight eviction rate'),
        ),
        isTrue,
      );
    });

    test(
      'evictionsPerReasonThreshold defaults to null and never alerts',
      () async {
        alertManager.dispose();
        final config = CacheAlertConfig(
          notifyCallback: (alert) => receivedAlerts.add(alert),
          hitRateThreshold: 0,
          missRateThreshold: 1,
          evictionsPerMinuteThreshold: 100000,
          alertCheckInterval: const Duration(seconds: 1),
        );
        expect(config.evictionsPerReasonThreshold, isNull);
        alertManager = CacheAlertManager(metrics, config);

        alertManager.monitor();
        await Future.delayed(const Duration(milliseconds: 100));
        for (int i = 0; i < 10; i++) {
          metrics.recordEvictionReason(EvictionReason.capacity);
        }
        await Future.delayed(const Duration(milliseconds: 1200));

        expect(receivedAlerts, isEmpty);
      },
    );
  });

  group('CacheAlertManager - Monitor Timing', () {
    test('Monitor checks at the correct interval', () async {
      final metrics = CacheMetrics();
      final receivedAlerts = [];

      // A persistently low (but genuine — totalRequests > 0) hit rate, so
      // every periodic check re-evaluates and re-fires the same alert.
      // Zero-traffic would no longer do this on its own now that
      // CacheAlertManager skips the hit/miss-rate checks when
      // totalRequests == 0 (see "does not trigger ... zero traffic" above).
      metrics.recordMiss(Duration.zero);

      final config = CacheAlertConfig(
        notifyCallback: receivedAlerts.add,
        hitRateThreshold: 0.5,
        alertCheckInterval: const Duration(
          milliseconds: 100,
        ), // Fast for testing
      );

      final alertManager = CacheAlertManager(metrics, config);
      alertManager.monitor();

      await Future.delayed(
        const Duration(milliseconds: 350),
      ); // Wait for multiple checks
      expect(
        receivedAlerts.length,
        greaterThanOrEqualTo(2),
      ); // At least two alerts triggered
      alertManager.dispose();
    });
  });

  group('CacheAlertManager - Lifecycle', () {
    late CacheMetrics metrics;
    late List<String> receivedAlerts;
    late CacheAlertManager alertManager;

    setUp(() {
      metrics = CacheMetrics();
      receivedAlerts = [];
      final config = CacheAlertConfig(
        notifyCallback: (alert) => receivedAlerts.add(alert),
        hitRateThreshold: 0.5,
        alertCheckInterval: const Duration(milliseconds: 50),
      );
      alertManager = CacheAlertManager(metrics, config);
    });

    tearDown(() => alertManager.dispose());

    test('dispose stops the timer', () async {
      // Record misses so alerts would fire if timer is active
      for (int i = 0; i < 10; i++) {
        metrics.recordMiss(Duration.zero);
      }
      alertManager.monitor();
      await Future.delayed(const Duration(milliseconds: 100));
      final countBeforeDispose = receivedAlerts.length;
      expect(countBeforeDispose, greaterThan(0));

      alertManager.dispose();
      receivedAlerts.clear();

      // Wait past several check intervals — no new alerts should fire
      await Future.delayed(const Duration(milliseconds: 200));
      expect(receivedAlerts, isEmpty);
    });

    test('dispose is idempotent', () {
      alertManager.monitor();
      expect(() {
        alertManager.dispose();
        alertManager.dispose();
      }, returnsNormally);
    });

    test('monitor called twice does not double-fire', () async {
      for (int i = 0; i < 10; i++) {
        metrics.recordMiss(Duration.zero);
      }
      alertManager.monitor();
      alertManager.monitor(); // second call cancels the first timer

      await Future.delayed(const Duration(milliseconds: 200));

      // With a single timer firing every 50ms over 200ms we expect ~4 firings.
      // If timers were doubled we would see significantly more.
      expect(receivedAlerts.length, lessThan(10));
      alertManager.dispose();
    });

    test('monitor after dispose is a no-op', () async {
      alertManager.monitor();
      alertManager.dispose();
      receivedAlerts.clear();

      alertManager.monitor(); // should be a no-op
      await Future.delayed(const Duration(milliseconds: 200));
      expect(receivedAlerts, isEmpty);
    });
  });

  group('Disposable type check', () {
    test('MonitoredLRUCache implements Disposable', () {
      final cache = MonitoredLRUCache<String, String>(
        maxSize: 10,
        alertConfig: CacheAlertConfig(
          notifyCallback: (_) {},
          alertCheckInterval: const Duration(seconds: 60),
        ),
      );
      expect(cache, isA<Disposable>());
      cache.dispose();
    });
  });
}
