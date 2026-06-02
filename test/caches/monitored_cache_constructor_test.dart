import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

void main() {
  group('Monitored cache constructors', () {
    test('use a no-op alert configuration by default', () {
      final caches = <Disposable>[
        MonitoredFIFOCache<String, String>(maxSize: 2),
        MonitoredEphemeralFIFOCache<String, String>(maxSize: 2),
        MonitoredLRUCache<String, String>(maxSize: 2),
        MonitoredMRUCache<String, String>(maxSize: 2),
        MonitoredLFUCache<String, String>(maxSize: 2),
      ];

      addTearDown(() {
        for (final cache in caches) {
          cache.dispose();
        }
      });

      expect(caches, everyElement(isA<Disposable>()));
    });
  });
}
