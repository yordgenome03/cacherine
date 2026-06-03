import 'package:cacherine/cacherine.dart';

Future<void> main() async {
  synchronousTTLExample();
  await asyncTTLExample();
  await monitoredCacheExample();
}

void synchronousTTLExample() {
  final cache = SimpleTTLCache<String, String>(
    ttl: const Duration(minutes: 5),
    maxSize: 100,
  );

  cache.set('token', 'abc123');
  cache.set('rate', '42', ttl: const Duration(seconds: 30));

  print('SimpleTTLCache token: ${cache.get('token')}');
  print('SimpleTTLCache has token: ${cache.containsKey('token')}');
}

Future<void> asyncTTLExample() async {
  final cache = TTLCache<String, String>(
    ttl: const Duration(minutes: 5),
    maxSize: 100,
  );

  await cache.set('user:1', 'Ada');
  await cache.set('session:1', 'active', ttl: const Duration(minutes: 1));

  print('TTLCache user: ${await cache.get('user:1')}');

  cache.dispose();
}

Future<void> monitoredCacheExample() async {
  final cache = MonitoredLRUCache<String, String>(maxSize: 2);

  await cache.set('a', 'first');
  await cache.set('b', 'second');
  await cache.get('a');
  await cache.get('missing');

  final dashboard = CacheStatsDashboard(cache.metrics);
  final snapshot = dashboard.snapshot(const Duration(minutes: 1));

  print(formatDashboard(snapshot));
  cache.dispose();
}
