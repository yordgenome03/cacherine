import 'dart:async';
import 'package:cacherine/src/monitorings/cache_alert_manager.dart';
import 'package:cacherine/src/monitorings/cache_metrics.dart';
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

    test('Triggers alert when hit rate is too low', () async {
      // 90% of requests are misses
      for (int i = 0; i < 10; i++) {
        metrics.recordMiss();
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
        metrics.recordMiss();
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
    });
  });
}
