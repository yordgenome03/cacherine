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

    test('toString() returns current entries for monitored caches', () async {
      final fifo = MonitoredFIFOCache<String, String>(maxSize: 2);
      final ephemeral = MonitoredEphemeralFIFOCache<String, String>(maxSize: 2);
      final lru = MonitoredLRUCache<String, String>(maxSize: 2);
      final mru = MonitoredMRUCache<String, String>(maxSize: 2);
      final lfu = MonitoredLFUCache<String, String>(maxSize: 2);
      final caches = <Disposable>[fifo, ephemeral, lru, mru, lfu];

      addTearDown(() {
        for (final cache in caches) {
          cache.dispose();
        }
      });

      await fifo.set('key', 'fifo');
      await ephemeral.set('key', 'ephemeral');
      await lru.set('key', 'lru');
      await mru.set('key', 'mru');
      await lfu.set('key', 'lfu');

      expect(fifo.toString(), contains('fifo'));
      expect(ephemeral.toString(), contains('ephemeral'));
      expect(lru.toString(), contains('lru'));
      expect(mru.toString(), contains('mru'));
      expect(lfu.toString(), contains('lfu'));
    });
  });
}
