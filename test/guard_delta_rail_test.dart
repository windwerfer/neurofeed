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
        clean,
        dirtyReason,
      }) {
        frame?.warning = warning;
        frame?.warnOver = warnOver;
      },
);

void main() {
  // The frontal-δ rail was removed 2026-10 (feedback_gym/DELTA_RAIL_SWEEP.md):
  // the guard warns on its threshold rule only.
  group('no δ rail', () {
    setUp(() => _warningWrites = 0);

    test('percentileWarnOver: high δ never warns an AI guard', () {
      expect(
        percentileWarnOver(
          bandMath: false,
          lastDelta: 50,
          lastSleepDir: 0.10,
          threshold: 0.50,
        ),
        isFalse,
      );
      expect(
        percentileWarnOver(
          bandMath: false,
          lastDelta: 0,
          lastSleepDir: 0.60,
          threshold: 0.50,
        ),
        isTrue,
      );
    });

    test('band math still scores native δ against its threshold', () {
      expect(
        percentileWarnOver(
          bandMath: true,
          lastDelta: 0.20,
          lastSleepDir: 0,
          threshold: 0.10,
        ),
        isTrue,
      );
      expect(
        percentileWarnOver(
          bandMath: true,
          lastDelta: 0.05,
          lastSleepDir: 0.99,
          threshold: 0.10,
        ),
        isFalse,
      );
    });

    test('GuardLane: AI score under threshold + high δ → no warn, chime '
        'or muffle', () {
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
        ..lastDelta = 50;
      l.evaluateWarning(_tick());
      expect(l.warningActive, isFalse);
      expect(guard.lastActive, isFalse);
      expect(reward.muffle, isFalse);
      expect(_warningWrites, 0);

      final frame = _Frame();
      l.onReveExtras(
        const ReveDto(
          timestamp: 0,
          kind: 'cbramod',
          clarity: 1,
          sleepDir: 0.1,
          delta: 50,
          dim: 0,
        ),
        _tick(frame: frame),
      );
      expect(frame.warning, isFalse);
      expect(frame.warnOver, isFalse);
    });

    test('GuardLane: AI score over threshold warns', () {
      final l = GuardLane(guardOutput: _Guard(), rewardOutput: _Reward())
        ..configure(
          enabled: true,
          bandMath: false,
          featureId: 'ai.a_vig',
          deltaElectrodes: const [],
        )
        ..threshold = 0.5
        ..lastSleepDir = 0.8;
      l.evaluateWarning(_tick());
      expect(l.warningActive, isTrue);
      expect(_warningWrites, 1);
    });
  });

  group('protocol guard flags', () {
    test('legacy deltaRail / requiresModel default and round-trip', () async {
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

    test('catalog: no row carries the removed deltaRail key; only '
        'sleepGuard requires the model', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final catalog = await ProtocolCatalog.load();
      for (final id in [
        'sleepGuard',
        'restAwake',
        'openMonitor',
        'alertClosed',
      ]) {
        final guard = catalog.forName(id)!.guard!;
        expect(guard.toJson().containsKey('deltaRail'), isFalse, reason: id);
        expect(guard.requiresModel, id == 'sleepGuard', reason: id);
      }
      // recordOnly: retired id, resolves to calibrateRecord.
      for (final id in ['alertOpen', 'calibrateRecord', 'recordOnly']) {
        expect(catalog.forName(id)!.guard, isNull, reason: id);
      }
    });
  });
}
