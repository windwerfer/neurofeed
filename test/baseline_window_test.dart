import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/audio/calibration_clips.dart';
import 'package:neurofeed/src/feedback/baseline_window.dart';
import 'package:neurofeed/src/feedback/calibration_runner.dart';

void main() {
  group('BaselineWindow', () {
    test('stops at 45 accepted frames', () {
      final start = DateTime.utc(2026);
      var window = const BaselineWindow().start(start);
      for (var i = 0; i < 44; i++) {
        window = window.recordAccepted();
        expect(window.finishedAt(start.add(Duration(seconds: i))), isFalse);
      }
      window = window.recordAccepted();
      expect(window.validSeconds, 45);
      expect(window.secondsLeft, 0);
      expect(window.finishedAt(start.add(const Duration(seconds: 44))), isTrue);
    });

    test('stops at 60 wall seconds while the count is short', () {
      final start = DateTime.utc(2026);
      final window = const BaselineWindow().start(start).recordAccepted();
      expect(
        window.finishedAt(start.add(const Duration(seconds: 59))),
        isFalse,
      );
      expect(window.finishedAt(start.add(const Duration(seconds: 60))), isTrue);
      expect(window.wallSecondsAt(start.add(const Duration(seconds: 60))), 60);
    });
  });

  group('BaselineFrameClock', () {
    test('one reward sample and one guard sample share a source second', () {
      final clock = BaselineFrameClock();
      final reward = clock.take(
        sourceSecond: 100,
        featureId: 'band.atr',
        accept: true,
      );
      final guard = clock.take(
        sourceSecond: 100,
        featureId: 'ai.drowsiness',
        accept: false,
      );
      final again = clock.take(
        sourceSecond: 100,
        featureId: 'band.atr',
        accept: true,
      );
      expect(reward.opened, isTrue);
      expect(reward.store, isTrue);
      expect(guard.opened, isFalse);
      expect(guard.store, isTrue);
      expect(again.store, isFalse);
    });

    test('a rejected second stores nothing and the next second can accept', () {
      final clock = BaselineFrameClock();
      final rejected = clock.take(
        sourceSecond: 100,
        featureId: 'band.atr',
        accept: false,
      );
      final later = clock.take(
        sourceSecond: 101,
        featureId: 'band.atr',
        accept: true,
      );
      expect(rejected.store, isFalse);
      expect(later.opened, isTrue);
      expect(later.store, isTrue);
    });
  });

  group('CalibrationRunner baseline window', () {
    CalibrationManifest manifest() {
      return CalibrationManifest(
        version: 2,
        calibrations: {
          'eyes-closed-01': Calibration(
            id: 'eyes-closed-01',
            name: 'Eyes Closed',
            single: CalibrationRecipe.single(
              seconds: 50,
              eyes: 'closed',
              intros: const [
                CalibrationStep(id: 'intro', file: 'clip.opus', text: 'rest'),
              ],
            ),
            staged: CalibrationRecipe.staged(
              stages: const [
                CalibrationStep(
                  id: 'reve-artifacts',
                  file: 'a.opus',
                  seconds: 15,
                ),
                CalibrationStep(
                  id: 'reve-eyes-open-counting',
                  file: 'o.opus',
                  seconds: 30,
                  eyes: 'open',
                  challengeText: ['Count'],
                ),
                CalibrationStep(
                  id: 'reve-eyes-closed-drifting',
                  file: 'c.opus',
                  seconds: 45,
                  eyes: 'closed',
                ),
              ],
            ),
          ),
        },
        protocolCalibration: const {'drowsiness': 'eyes-closed-01'},
      );
    }

    test('45 valid frames end the simple baseline before 60s', () async {
      var now = DateTime.utc(2026, 1, 1, 12);
      var accept = true;
      var finished = false;
      final left = <int>[];
      final runner = CalibrationRunner(
        loadManifest: () async => manifest(),
        playClip: (_) async {},
        writeMetadata: (_) {},
        updateUi: (ui) {
          if (ui.baselineSecondsLeft != null) {
            left.add(ui.baselineSecondsLeft!);
          }
        },
        isActive: () => true,
        protocolOf: () => 'drowsiness',
        sessionStartAt: () => now,
        onCollectionEyes: (_) {},
        onFinished: () => finished = true,
        baselineFrameValid: () => accept,
        clock: () => now,
      );
      final future = runner.playAndBaseline(plan: CalibrationPlan.baselineOnly);
      for (var i = 0; i < 10 && !runner.collectingBaselineWindow; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(runner.collectingBaselineWindow, isTrue);
      expect(left, contains(45));

      bool feed(String id) {
        final store = runner.noteBaselineFrame(featureId: id);
        runner.finishBaselineFrame();
        return store;
      }

      accept = false;
      now = now.add(const Duration(seconds: 1));
      expect(feed('band.atr'), isFalse);
      expect(runner.collectingBaselineWindow, isTrue);

      accept = true;
      final start = now.add(const Duration(seconds: 1));
      for (var i = 0; i < 45; i++) {
        now = start.add(Duration(seconds: i));
        expect(feed('band.atr'), isTrue, reason: 'frame $i');
      }
      await future;
      expect(finished, isTrue);
      expect(runner.baselineValidSeconds, 45);
      expect(runner.baselineWallSeconds, lessThan(60));
      expect(runner.collectingBaselineWindow, isFalse);
    });

    test('the window stops at 60s when frames stay invalid', () async {
      var now = DateTime.utc(2026, 1, 1, 12);
      var finished = false;
      final runner = CalibrationRunner(
        loadManifest: () async => manifest(),
        playClip: (_) async {},
        writeMetadata: (_) {},
        updateUi: (_) {},
        isActive: () => true,
        protocolOf: () => 'drowsiness',
        sessionStartAt: () => now,
        onCollectionEyes: (_) {},
        onFinished: () => finished = true,
        baselineFrameValid: () => false,
        clock: () => now,
      );
      final future = runner.playAndBaseline(plan: CalibrationPlan.baselineOnly);
      for (var i = 0; i < 10 && !runner.collectingBaselineWindow; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final start = now;
      for (var second = 0; second < 60; second++) {
        now = start.add(Duration(seconds: second));
        expect(runner.noteBaselineFrame(featureId: 'band.atr'), isFalse);
        runner.finishBaselineFrame();
        expect(runner.collectingBaselineWindow, isTrue);
      }
      now = start.add(const Duration(seconds: 60));
      expect(runner.noteBaselineFrame(featureId: 'band.atr'), isFalse);
      runner.finishBaselineFrame();
      await future;
      expect(finished, isTrue);
      expect(runner.baselineValidSeconds, 0);
      expect(runner.baselineWallSeconds, 60);
    });

    test('a late feature keeps its source second', () async {
      var now = DateTime.utc(2026, 1, 1, 12);
      final left = <int>[];
      final runner = CalibrationRunner(
        loadManifest: () async => manifest(),
        playClip: (_) async {},
        writeMetadata: (_) {},
        updateUi: (ui) {
          if (ui.baselineSecondsLeft != null) {
            left.add(ui.baselineSecondsLeft!);
          }
        },
        isActive: () => true,
        protocolOf: () => 'drowsiness',
        sessionStartAt: () => now,
        onCollectionEyes: (_) {},
        onFinished: () {},
        baselineFrameValid: () => true,
        clock: () => now,
      );
      final future = runner.playAndBaseline(plan: CalibrationPlan.baselineOnly);
      for (var i = 0; i < 10 && !runner.collectingBaselineWindow; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final startSecond = now.millisecondsSinceEpoch ~/ 1000;
      expect(
        runner.noteBaselineFrame(
          featureId: 'band.atr',
          sourceSecond: startSecond - 3,
        ),
        isFalse,
      );
      expect(
        runner.noteBaselineFrame(
          featureId: 'band.atr',
          sourceSecond: startSecond,
        ),
        isTrue,
      );
      expect(
        runner.noteBaselineFrame(
          featureId: 'ai.drowsiness',
          sourceSecond: startSecond,
        ),
        isTrue,
      );
      now = now.add(const Duration(seconds: 2));
      expect(
        runner.noteBaselineFrame(
          featureId: 'ai.drowsiness',
          sourceSecond: startSecond,
        ),
        isFalse,
      );
      expect(left.where((seconds) => seconds == 44), [44]);
      runner.cancelTimers();
      await future;
    });

    test('staged rest is the only baseline window', () async {
      var active = true;
      final gate = Completer<void>();
      final runner = CalibrationRunner(
        loadManifest: () async => manifest(),
        playClip: (_) => gate.future,
        writeMetadata: (_) {},
        updateUi: (_) {},
        isActive: () => active,
        protocolOf: () => 'drowsiness',
        sessionStartAt: () => DateTime.utc(2026),
        onCollectionEyes: (_) {},
        onFinished: () {},
      );
      final future = runner.playAndBaseline(plan: CalibrationPlan.stagedAi);
      await Future<void>.delayed(Duration.zero);
      expect(runner.steps.map((step) => step.baselineWindow).toList(), [
        false,
        false,
        true,
      ]);
      active = false;
      gate.complete();
      runner.cancelTimers();
      await future;
    });
  });
}
