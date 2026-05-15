import 'dart:async';
import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
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
      // Run the monitor
      alertManager.monitor();

      // Wait enough time for evictions to accumulate (2 seconds in this case)
      await Future.delayed(const Duration(milliseconds: 2000));

      // Record evictions in bulk to reduce the loop overhead
      for (int i = 0; i < 500; i++) {
        metrics.recordEviction();
      }

      // Wait to ensure the monitoring catches the evictions
      await Future.delayed(const Duration(milliseconds: 500));

      // Check if the alert for high eviction rate was triggered
      expect(
        receivedAlerts.any(
          (alert) => alert.contains('Warning: High eviction rate detected'),
        ),
        isTrue,
      );
    });
  });

  group('CacheAlertManager - Monitor Timing', () {
    test('Monitor checks at the correct interval', () async {
      final metrics = CacheMetrics();
      final receivedAlerts = [];

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
