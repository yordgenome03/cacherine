# Monitored Cache with Performance Alerts

The `MonitoredCache` feature provides an advanced **performance monitoring and alerting** system that helps track key cache metrics, ensuring optimal cache behavior during development and production. This system monitors cache performance, triggers alerts when performance thresholds are exceeded, and allows you to adjust and optimize your cache strategy in real-time.

## Overview of the Monitored Cache Alert System

The **alert system** in `MonitoredCache` is powered by the `CacheAlertManager` class, which monitors cache metrics using the data from the `CacheMetrics` class. If any metric exceeds the predefined threshold values, it triggers an alert and notifies you via a callback function. This helps you detect performance issues early, making `MonitoredCache` a great tool for **debugging** and **optimization**.

### **Key Components of the Alert System**

1. **`CacheAlertManager`**:

   - Periodically checks cache statistics provided by the `CacheMetrics` class.
   - Compares these statistics against thresholds set in the `CacheAlertConfig` class.
   - If the thresholds are exceeded, an alert is triggered, and a notification is sent via the `notifyCallback`.

2. **`CacheAlertConfig`**:

   - Configures the alert thresholds for various cache metrics.
   - Includes thresholds for:
     - **Hit rate**: Low hit rate detection.
     - **Miss rate**: High miss rate detection.
     - **Request latency**: High latency detection for 95th and 99th percentiles.
     - **Evictions**: High eviction rate detection.
     - **Average latency**: High average latency detection.
   - You can also set the **interval** for checking the alerts (default: every minute).

3. **Thresholds**:

   - **Hit Rate Threshold**: Low hit rate alert (default: 50%).
   - **Miss Rate Threshold**: High miss rate alert (default: 50%).
   - **Latency Thresholds (p95 & p99)**: High latency alert for 95th and 99th percentiles (default: 200ms for p95, 300ms for p99).
   - **Evictions per Minute Threshold**: High eviction rate alert (default: 1000 evictions/minute).
   - **Average Latency Threshold**: High average latency alert (default: 100ms).

4. **Alert Notification**:
   - The `notifyCallback` function is called whenever an alert is triggered.
   - This callback allows you to log, display, or send notifications based on performance issues.

### **How the Alert System Works**

1. **Periodic Monitoring**:

   - The `CacheAlertManager` periodically checks the cache's performance against the defined thresholds.
   - This monitoring happens at intervals specified by the `alertCheckInterval` parameter in `CacheAlertConfig`.

2. **Triggering Alerts**:
   - If the performance metrics exceed their respective thresholds, an alert is triggered.
   - The `notifyCallback` function is invoked with a message detailing the problem (e.g., high miss rate, latency, etc.).

### **Example Usage of the Alert System**

```dart
import 'package:cacherine/cacherine.dart';

void main() async {
  // Define the alert configuration
  final alertConfig = CacheAlertConfig(
    notifyCallback: (message) {
      print('ALERT: $message'); // You can replace this with a more advanced notification system.
    },
    hitRateThreshold: 0.4,  // Trigger alert if hit rate falls below 40%
    missRateThreshold: 0.6, // Trigger alert if miss rate exceeds 60%
    p95LatencyThreshold: 150, // Trigger alert if 95th percentile latency exceeds 150ms
    p99LatencyThreshold: 200, // Trigger alert if 99th percentile latency exceeds 200ms
    evictionsPerMinuteThreshold: 500, // Trigger alert if evictions exceed 500/min
    averageLatencyThreshold: 50, // Trigger alert if average latency exceeds 50ms
    alertCheckInterval: Duration(seconds: 30), // Check every 30 seconds
  );

  // Create a monitored FIFO cache with performance tracking
  final cache = MonitoredFIFOCache<String, String>(
    maxSize: 3,
    alertConfig: alertConfig,
  );

  // Simulate cache operations
  await cache.set('key1', 'value1');
  await cache.set('key2', 'value2');
  await cache.get('key1'); // Cache hit
  await cache.get('key3'); // Cache miss

  // Check the performance metrics and monitor alerts
  final metrics = cache.metrics;
  print('Hit Rate: ${metrics.hitRate}');
  print('Miss Rate: ${metrics.missRate}');
  print('Average Latency: ${metrics.averageLatency}');
  print('P95 Latency: ${metrics.getLatencyPercentile(95)}');
}
```

## Metrics Monitored by the Alert System

The alert system in MonitoredCache tracks the following key metrics:

- Hit Rate: The percentage of cache accesses that result in a hit (i.e., the requested item was found in the cache).
- Miss Rate: The percentage of cache accesses that result in a miss (i.e., the requested item was not found in the cache).
- Request Latency: The time it takes to complete a cache operation.
  - The system tracks the 95th and 99th percentiles of latency to catch outliers.
  - Average latency is also monitored.
- Evictions: The number of items removed from the cache due to size limitations (e.g., when the cache exceeds the maximum size).
  - Evictions are tracked as events and can be monitored over time.

## Why Use MonitoredCache?

- Real-time Monitoring: Continuously monitor your cache's health, even in production environments.
- Early Detection: Quickly detect performance issues (e.g., high miss rates or high latency).
- Customization: Configure your own thresholds and notification system to suit your needs.
- Development & Debugging: Fine-tune cache strategies by watching real-time performance metrics.
