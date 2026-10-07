import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/audio/guard_output.dart';
import 'package:neurofeed/src/audio/reward_output.dart';
import 'package:neurofeed/src/feedback/feature_catalog.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/feedback/guard_lane.dart';
import 'package:neurofeed/src/feedback/protocol.dart';
import 'package:neurofeed/src/feedback/protocol_catalog.dart';
import 'package:neurofeed/src/rust/api/muse.dart';

class _Reward implements RewardOutput {
  bool? muffle;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  void onSample({required double percentile, required bool inTarget}) {}
  @override
  void setMuffle(bool on) => muffle = on;
}

class _Guard implements GuardOutput {
  bool? lastActive;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  void onGuard({required bool active, required double intensity}) =>
      lastActive = active;
}

class _Frame {
  bool? warning;
  bool? warnOver;
  bool? ceilingOver;
}

int _warningWrites = 0;

GuardTick _tick({_Frame? frame, bool muffleReward = true}) => GuardTick(
  phase: FeedbackPhase.playing,
  collectionEyes: null,
  muffleReward: muffleReward,
  sessionStartAt: DateTime.now(),
  writeWarningMetadata:
      ({
        required sleepDir,
        required delta,
        required threshold,
        required bandMath,
      }) => _warningWrites++,
  updateComputed:
      ({
        required sleepDir,
        required clarity,
        required delta,
        required warning,
        threshold,
        featurePercentile,
        warnOver,
        ceilingOver,
        clean,
        dirtyReason,
      }) {
        frame?.warning = warning;
        frame?.warnOver = warnOver;
        frame?.ceilingOver = ceilingOver;
      },
);

void main() {
  group('percentileWarnOver deltaRail', () {
    test('rail on (default): absolute delta over 0.25 warns in both modes', () {
      for (final bandMath in [true, false]) {
        expect(
          percentileWarnOver(
            bandMath: bandMath,
            lastDelta: 0.30,
            lastSleepDir: 0.0,
            threshold: 0.50,
          ),
          isTrue,
          reason: 'bandMath=$bandMath',
        );
      }
    });

    test('rail off: absolute delta over 0.25 never warns', () {
      for (final bandMath in [true, false]) {
        expect(
          percentileWarnOver(
            bandMath: bandMath,
            lastDelta: 0.30,
            lastSleepDir: 0.0,
            threshold: 0.50,
            deltaRail: false,
          ),
          isFalse,
          reason: 'bandMath=$bandMath',
        );
      }
    });

    test('rail off: the percentile rule still warns', () {
      // AI: score above threshold.
      expect(
        percentileWarnOver(
          bandMath: false,
          lastDelta: 0.10,
          lastSleepDir: 0.60,
          threshold: 0.50,
          deltaRail: false,
        ),
        isTrue,
      );
      // Band: delta above its percentile threshold (below the ceiling).
      expect(
        percentileWarnOver(
          bandMath: true,
          lastDelta: 0.20,
          lastSleepDir: 0.0,
          threshold: 0.10,
          deltaRail: false,
        ),
        isTrue,
      );
    });
  });

  group('GuardLane deltaRail', () {
    setUp(() => _warningWrites = 0);

    GuardLane lane({required bool deltaRail, required bool bandMath}) {
      final l = GuardLane(guardOutput: _Guard(), rewardOutput: _Reward());
      l.configure(
        enabled: true,
        bandMath: bandMath,
        featureId: bandMath ? 'band.delta' : 'ai.a_vig',
        deltaElectrodes: const [],
        deltaRail: deltaRail,
      );
      return l
        ..threshold = 0.5
        ..lastSleepDir = 0.1
        ..lastDelta = 0.9; // far over the 0.25 ceiling, under nothing else
    }

    test('configure defaults deltaRail to true', () {
      final l = GuardLane(guardOutput: _Guard(), rewardOutput: _Reward())
        ..configure(
          enabled: true,
          bandMath: false,
          featureId: 'ai.a_vig',
          deltaElectrodes: const [],
        );
      expect(l.deltaRail, isTrue);
    });

    test('rail on: ceiling warns, chimes and muffles (AI)', () {
      final reward = _Reward();
      final guard = _Guard();
      final l = GuardLane(guardOutput: guard, rewardOutput: reward)
        ..configure(
          enabled: true,
          bandMath: false,
          featureId: 'ai.a_vig',
          deltaElectrodes: const [],
        )
        ..threshold = 0.5
        ..lastSleepDir = 0.1
        ..lastDelta = 0.9;
      l.evaluateWarning(_tick());
      expect(l.warningActive, isTrue);
      expect(guard.lastActive, isTrue);
      expect(reward.muffle, isTrue);
      expect(_warningWrites, 1);
    });

    for (final bandMath in [false, true]) {
      test('rail off (bandMath=$bandMath): no warning / chime / muffle, '
          'ceilingOver still recorded', () {
        final reward = _Reward();
        final guard = _Guard();
        final l = GuardLane(guardOutput: guard, rewardOutput: reward)
          ..configure(
            enabled: true,
            bandMath: bandMath,
            featureId: bandMath ? 'band.delta' : 'ai.a_vig',
            deltaElectrodes: const [],
            deltaRail: false,
          )
          // Band math scores lastDelta itself, so give it a threshold above
          // the ceiling value; AI scores lastSleepDir.
          ..threshold = bandMath ? 2.0 : 0.5
          ..lastSleepDir = 0.1
          ..lastDelta = 0.9;
        l.evaluateWarning(_tick());
        expect(l.warningActive, isFalse);
        expect(guard.lastActive, isFalse);
        expect(reward.muffle, isFalse);
        expect(_warningWrites, 0);
        expect(l.ceilingOver, isTrue);

        final frame = _Frame();
        l.onReveExtras(
          const ReveDto(
            timestamp: 0,
            kind: 'cbramod',
            clarity: 1,
            sleepDir: 0.1,
            delta: 0.9,
            dim: 0,
          ),
          _tick(frame: frame),
        );
        expect(frame.ceilingOver, isTrue, reason: 'signal-dirty flag');
        expect(frame.warning, isFalse);
        expect(frame.warnOver, isFalse);
      });
    }

    test('rail off: the feature over threshold still warns', () {
      final l = lane(deltaRail: false, bandMath: false)..lastSleepDir = 0.8;
      l.evaluateWarning(_tick());
      expect(l.warningActive, isTrue);
      expect(_warningWrites, 1);
    });
  });

  group('protocol guard flags', () {
    test('deltaRail / requiresModel default and round-trip', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final features = FeatureCatalog.fromJson(
        jsonDecode(await rootBundle.loadString(FeatureCatalog.asset)) as Map,
      );
      final g = ProtocolGuard.fromJson(features: features, const {
        'feature': 'band.delta',
        'output': 'softBowl',
        'policy': 'percentileWarn',
      });
      expect(g.deltaRail, isTrue);
      expect(g.requiresModel, isFalse);
      expect(g.toJson().containsKey('deltaRail'), isFalse);
      expect(g.toJson().containsKey('requiresModel'), isFalse);

      final off = ProtocolGuard.fromJson(features: features, const {
        'feature': 'ai.a_vig',
        'output': 'softBowl',
        'policy': 'percentileWarn',
        'deltaRail': false,
        'requiresModel': true,
      });
      expect(off.deltaRail, isFalse);
      expect(off.requiresModel, isTrue);
      final back = ProtocolGuard.fromJson(off.toJson(), features: features);
      expect(back.deltaRail, isFalse);
      expect(back.requiresModel, isTrue);
    });

    test('catalog: AI-guarded rows turn the rail off; only sleepGuard '
        'requires the model', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final catalog = await ProtocolCatalog.load();
      for (final id in [
        'sleepGuard',
        'restAwake',
        'openMonitor',
        'alertClosed',
        'concentrate',
      ]) {
        final guard = catalog.forName(id)!.guard!;
        expect(guard.deltaRail, isFalse, reason: id);
        expect(guard.requiresModel, id == 'sleepGuard', reason: id);
      }
      // recordOnly: retired id, resolves to calibrateRecord.
      for (final id in ['alertOpen', 'calibrateRecord', 'recordOnly']) {
        expect(catalog.forName(id)!.guard, isNull, reason: id);
      }
    });
  });
}
