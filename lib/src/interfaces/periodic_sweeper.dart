import 'dart:async';

import 'disposable.dart';

/// **Shared "owns a periodic timer" lifecycle helper.**
///
/// Centralizes the `Timer?` field + cancel-on-dispose boilerplate that was
/// previously hand-rolled in every TTL/Monitored cache class. A mixing-in
/// class becomes [Disposable] automatically; call [startSweep] to begin (or
/// replace) the periodic callback, and [dispose] to stop it.
///
/// **Cancellation only prevents *future* ticks.** If [dispose] is called
/// while a sweep callback is already executing (e.g. awaiting a lock), that
/// in-flight sweep still runs to completion — `Timer.cancel()` cannot abort
/// work already in progress. This matches the behavior of every hand-rolled
/// sweep timer this mixin replaces.
mixin PeriodicSweeper implements Disposable {
  Timer? _sweepTimer;
  bool _sweeperDisposed = false;

  /// Starts (or restarts) a periodic sweep, invoking [onSweep] every
  /// [interval]. A previously-running sweep timer, if any, is cancelled
  /// first. Does nothing if [dispose] has already been called.
  void startSweep(Duration interval, FutureOr<void> Function() onSweep) {
    if (_sweeperDisposed) return;
    _sweepTimer?.cancel();
    _sweepTimer = Timer.periodic(interval, (_) {
      unawaited(Future.sync(onSweep));
    });
  }

  /// Cancels the sweep timer. Idempotent — safe to call more than once.
  @override
  void dispose() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _sweeperDisposed = true;
  }
}
