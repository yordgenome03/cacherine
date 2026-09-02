import 'dart:async';

import 'package:cacherine/cacherine.dart';
import 'package:test/test.dart';

class _TestSweeper with PeriodicSweeper {}

void main() {
  group('PeriodicSweeper', () {
    test(
      'startSweep() invokes onSweep repeatedly at the given interval',
      () async {
        final sweeper = _TestSweeper();
        var calls = 0;
        sweeper.startSweep(const Duration(milliseconds: 20), () => calls++);

        await Future<void>.delayed(const Duration(milliseconds: 90));
        sweeper.dispose();

        expect(calls, greaterThanOrEqualTo(3));
      },
    );

    test('startSweep() cancels a previously-running timer before starting '
        'the new one', () async {
      final sweeper = _TestSweeper();
      var firstCalls = 0;
      var secondCalls = 0;
      sweeper.startSweep(const Duration(milliseconds: 20), () => firstCalls++);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      sweeper.startSweep(const Duration(milliseconds: 20), () => secondCalls++);
      final firstCallsAtSwitch = firstCalls;
      await Future<void>.delayed(const Duration(milliseconds: 90));
      sweeper.dispose();

      // The first callback must not fire again after being replaced.
      expect(firstCalls, equals(firstCallsAtSwitch));
      expect(secondCalls, greaterThan(0));
    });

    test('dispose() prevents future ticks from firing', () async {
      final sweeper = _TestSweeper();
      var calls = 0;
      sweeper.startSweep(const Duration(milliseconds: 20), () => calls++);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      sweeper.dispose();
      final callsAtDispose = calls;
      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(calls, equals(callsAtDispose));
    });

    test('dispose() is idempotent', () {
      final sweeper = _TestSweeper();
      sweeper.startSweep(const Duration(milliseconds: 20), () {});
      expect(() {
        sweeper.dispose();
        sweeper.dispose();
      }, returnsNormally);
    });

    // Regression coverage for the class doc comment's explicit promise:
    // "Cancellation only prevents *future* ticks. If dispose is called while
    // a sweep callback is already executing ... that in-flight sweep still
    // runs to completion." Timer.cancel() cannot abort work already in
    // progress — this pins that down rather than leaving it as an untested
    // claim.
    test('dispose() does not abort a sweep callback that is already in '
        'flight — only future ticks are cancelled', () async {
      final sweeper = _TestSweeper();
      final sweepStarted = Completer<void>();
      final releaseSweep = Completer<void>();
      var sweepCompleted = false;

      sweeper.startSweep(const Duration(milliseconds: 10), () async {
        if (!sweepStarted.isCompleted) sweepStarted.complete();
        await releaseSweep.future;
        sweepCompleted = true;
      });

      await sweepStarted.future; // the first tick is now in flight, awaiting
      sweeper.dispose(); // cancels future ticks — must not abort this one
      expect(sweepCompleted, isFalse);

      releaseSweep.complete();
      await Future<void>.delayed(Duration.zero); // let it run to completion
      expect(sweepCompleted, isTrue);
    });

    test('startSweep() after dispose() does nothing — the sweep never '
        'starts, matching the documented "does nothing if dispose has '
        'already been called" contract', () async {
      final sweeper = _TestSweeper();
      sweeper.dispose();

      var calls = 0;
      sweeper.startSweep(const Duration(milliseconds: 10), () => calls++);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(calls, equals(0));
    });

    // Regression coverage: startSweep() wraps onSweep as
    // `unawaited(Future.sync(onSweep))`. unawaited() is purely a lint marker
    // — it attaches no error handler — so an exception thrown by onSweep
    // becomes an unhandled asynchronous error rather than being silently
    // swallowed, and (since the Timer.periodic callback itself never
    // throws) the timer keeps firing on subsequent ticks regardless.
    test('an exception thrown by onSweep surfaces as an unhandled zone error '
        'and does not stop the timer from firing again', () async {
      final sweeper = _TestSweeper();
      var calls = 0;
      final caughtErrors = <Object>[];

      await runZonedGuarded(() async {
        sweeper.startSweep(const Duration(milliseconds: 20), () {
          calls++;
          if (calls == 1) throw StateError('boom');
        });
        await Future<void>.delayed(const Duration(milliseconds: 90));
        sweeper.dispose();
      }, (error, stack) => caughtErrors.add(error));

      expect(caughtErrors, hasLength(1));
      expect(caughtErrors.single, isA<StateError>());
      expect(calls, greaterThanOrEqualTo(3));
    });
  });
}
