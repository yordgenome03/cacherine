import 'package:cacherine/cacherine.dart';

const _defaultMaxSize = 10000;
const _defaultWrites = 2000;

Future<Duration> _time(Future<void> Function() body) async {
  final stopwatch = Stopwatch()..start();
  await body();
  stopwatch.stop();
  return stopwatch.elapsed;
}

String _formatRate(int operations, Duration elapsed) {
  final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  final rate = operations / seconds;
  return rate.toStringAsFixed(0);
}

Future<void> main(List<String> args) async {
  final maxSize = args.isNotEmpty ? int.parse(args[0]) : _defaultMaxSize;
  final writes = args.length > 1 ? int.parse(args[1]) : _defaultWrites;

  if (maxSize <= 0) {
    throw ArgumentError.value(maxSize, 'maxSize', 'must be positive');
  }
  if (writes <= 0) {
    throw ArgumentError.value(writes, 'writes', 'must be positive');
  }

  var now = DateTime(2024);
  DateTime clock() => now;

  final belowCapacity = TTLCache<int, int>(
    ttl: const Duration(hours: 1),
    maxSize: maxSize,
    clock: clock,
  );
  final belowCapacityElapsed = await _time(() async {
    for (var i = 0; i < writes; i++) {
      await belowCapacity.set(i, i);
    }
  });

  final atCapacityLive = TTLCache<int, int>(
    ttl: const Duration(hours: 1),
    maxSize: maxSize,
    clock: clock,
  );
  for (var i = 0; i < maxSize; i++) {
    await atCapacityLive.set(i, i);
  }
  final atCapacityLiveElapsed = await _time(() async {
    for (var i = 0; i < writes; i++) {
      await atCapacityLive.set(maxSize + i, i);
    }
  });

  final atCapacityExpired = TTLCache<int, int>(
    ttl: const Duration(seconds: 1),
    maxSize: maxSize,
    clock: clock,
  );
  for (var i = 0; i < maxSize; i++) {
    await atCapacityExpired.set(i, i);
  }
  now = now.add(const Duration(seconds: 2));
  final atCapacityExpiredElapsed = await _time(() async {
    for (var i = 0; i < writes; i++) {
      await atCapacityExpired.set(maxSize + i, i);
    }
  });

  belowCapacity.dispose();
  atCapacityLive.dispose();
  atCapacityExpired.dispose();

  print('TTLCache capacity benchmark');
  print('maxSize: $maxSize');
  print('writes: $writes');
  print('');
  print('scenario,total_us,ops_per_sec');
  print(
    'below_capacity,'
    '${belowCapacityElapsed.inMicroseconds},'
    '${_formatRate(writes, belowCapacityElapsed)}',
  );
  print(
    'at_capacity_live,'
    '${atCapacityLiveElapsed.inMicroseconds},'
    '${_formatRate(writes, atCapacityLiveElapsed)}',
  );
  print(
    'at_capacity_with_expired_entries,'
    '${atCapacityExpiredElapsed.inMicroseconds},'
    '${_formatRate(writes, atCapacityExpiredElapsed)}',
  );
}
