import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  group('Disposable lifecycle', () {
    final factories = <String, ThreadSafeCache<String, String> Function()>{
      'MonitoredFIFOCache': () => MonitoredFIFOCache(maxSize: 2),
      'MonitoredEphemeralFIFOCache': () =>
          MonitoredEphemeralFIFOCache(maxSize: 2),
      'MonitoredLRUCache': () => MonitoredLRUCache(maxSize: 2),
      'MonitoredMRUCache': () => MonitoredMRUCache(maxSize: 2),
      'MonitoredLFUCache': () => MonitoredLFUCache(maxSize: 2),
      'TTLCache': () => TTLCache(ttl: const Duration(seconds: 30)),
      'MonitoredTTLCache': () =>
          MonitoredTTLCache(ttl: const Duration(seconds: 30)),
    };

    for (final entry in factories.entries) {
      test(
        '${entry.key} dispose is idempotent and cache operations still work',
        () async {
          final cache = entry.value();
          final disposable = cache as Disposable;

          expect(() {
            disposable.dispose();
            disposable.dispose();
          }, returnsNormally);

          await cache.set('key', 'value');

          expect(await cache.get('key'), equals('value'));
          await cache.remove('key');
          expect(await cache.containsKey('key'), isFalse);

          await cache.set('a', 'A');
          await cache.clear();
          expect(await cache.getKeys(), isEmpty);
        },
      );
    }
  });
}
