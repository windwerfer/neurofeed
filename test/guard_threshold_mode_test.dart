import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/audio/guard_output.dart';
import 'package:neurofeed/src/audio/reward_output.dart';
import 'package:neurofeed/src/feedback/feature_catalog.dart';
import 'package:neurofeed/src/feedback/guard_lane.dart';
import 'package:neurofeed/src/feedback/guardrail_mode.dart';
import 'package:neurofeed/src/feedback/protocol.dart';
import 'package:neurofeed/src/feedback/protocol_catalog.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Reward implements RewardOutput {
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  void onSample({required double percentile, required bool inTarget}) {}
  @override
  void setMuffle(bool on) {}
}

class _Guard implements GuardOutput {
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  void onGuard({required bool active, required double intensity}) {}
}

/// AI guards (probabilities 0–1) default to a fixed cut (P > 0.50, gym
/// sweep 2026-10); band guards keep the percentile-of-calibration rule.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FeatureCatalog features;
  setUpAll(() async {
    features = FeatureCatalog.fromJson(
      jsonDecode(await rootBundle.loadString(FeatureCatalog.asset)) as Map,
    );
  });

  test('defaults: fixed for ai.*, percentile for band.*', () {
    expect(defaultAiGuardFixedThreshold, 0.50);
    expect(
      resolveGuardThresholdMode(feature: 'ai.a_vig'),
      guardThresholdModeFixed,
    );
    expect(
      resolveGuardThresholdMode(feature: 'ai.wake_light'),
      guardThresholdModeFixed,
    );
    expect(
      resolveGuardThresholdMode(feature: 'band.delta'),
      guardThresholdModePercentile,
    );
    // band.* can never be fixed.
    expect(
      resolveGuardThresholdMode(
        feature: 'band.delta',
        declared: guardThresholdModeFixed,
      ),
      guardThresholdModePercentile,
    );
    expect(
      resolveGuardThresholdMode(
        feature: 'ai.a_vig',
        declared: guardThresholdModePercentile,
      ),
      guardThresholdModePercentile,
    );
    expect(
      resolveGuardThresholdMode(feature: 'ai.a_vig', declared: 'bogus'),
      guardThresholdModeFixed,
    );
    expect(clampAiGuardFixedThreshold(0.999), maxAiGuardFixedThreshold);
    expect(clampAiGuardFixedThreshold(0.537), 0.54);
  });

  group('protocol JSON', () {
    ProtocolDocument doc(Map<String, Object?> guard) =>
        ProtocolDocument.fromJson(
          {'calibration': 'eyes-closed-01', 'guard': guard},
          id: 'user.t',
          features: features,
        );

    test('old documents (no thresholdMode) parse and keep defaults', () {
      final g = doc({'feature': 'ai.a_vig'}).guard!;
      expect(g.thresholdMode, isNull);
      expect(g.fixedThreshold, isNull);
      expect(g.thresholdModeFor(), guardThresholdModeFixed);
      expect(g.thresholdModeFor('band.delta'), guardThresholdModePercentile);
      expect(g.toJson().containsKey('thresholdMode'), isFalse);
    });

    test('unknown / impossible values are ignored, not fatal', () {
      final bogus = doc({
        'feature': 'ai.a_vig',
        'thresholdMode': 'zscore',
        'fixedThreshold': 7,
      }).guard!;
      expect(bogus.thresholdMode, isNull);
      expect(bogus.fixedThreshold, isNull);
      final band = doc({
        'feature': 'band.delta',
        'thresholdMode': 'fixed',
      }).guard!;
      expect(band.thresholdModeFor(), guardThresholdModePercentile);
    });

    test('round-trips mode and value', () {
      final g = doc({
        'feature': 'ai.a_vig',
        'thresholdMode': 'percentile',
        'fixedThreshold': 0.6,
      }).guard!;
      expect(g.thresholdMode, guardThresholdModePercentile);
      expect(g.toJson()['thresholdMode'], 'percentile');
      expect(g.toJson()['fixedThreshold'], 0.6);
    });

    test('session snapshot records the mode and value that ran', () async {
      final catalog = await ProtocolCatalog.load();
      final rest = catalog.byName['restAwake']!;
      final ai = rest.resolved(
        guardFeature: 'ai.a_vig',
        guardFixedThreshold: 0.55,
      );
      expect(ai.guard!.thresholdMode, guardThresholdModeFixed);
      expect(ai.guard!.fixedThreshold, 0.55);
      final pct = rest.resolved(
        guardFeature: 'ai.a_vig',
        guardThresholdMode: guardThresholdModePercentile,
        guardFixedThreshold: 0.55,
      );
      expect(pct.guard!.thresholdMode, guardThresholdModePercentile);
      expect(pct.guard!.fixedThreshold, isNull);
      final band = rest.resolved(guardFeature: 'band.delta');
      expect(band.guard!.thresholdMode, guardThresholdModePercentile);
      expect(band.guard!.fixedThreshold, isNull);
    });
  });

  group('GuardLane', () {
    GuardLane lane({String mode = guardThresholdModeFixed, bool band = false}) {
      final l = GuardLane(guardOutput: _Guard(), rewardOutput: _Reward());
      l.configure(
        enabled: true,
        bandMath: band,
        featureId: band ? 'band.delta' : 'ai.a_vig',
        deltaElectrodes: const [],
        thresholdMode: mode,
        fixedThreshold: 0.5,
      );
      l.baselineSleepDir.addAll([
        for (var i = 0; i < 100; i++) i / 1000, // 0.000 … 0.099
      ]);
      return l;
    }

    test('fixed: threshold is the probability, not a calibration pick', () {
      final l = lane()
        ..finalizeBaseline(
          warningThresholdPercentile: 90,
          captureAnchor: false,
        );
      expect(l.fixedMode, isTrue);
      expect(l.threshold, 0.5);
      l.recomputeThreshold(50); // percentile slider has no effect
      expect(l.threshold, 0.5);
      l.lastSleepDir = 0.2;
      expect(l.warnOver, isFalse); // p90 of cal (0.089) would warn here
      l.lastSleepDir = 0.51;
      expect(l.warnOver, isTrue);
      l.setFixedThreshold(0.6);
      expect(l.threshold, 0.6);
      expect(l.warnOver, isFalse);
    });

    test('percentile: unchanged behavior; switch modes mid-session', () {
      final l = lane(
        mode: guardThresholdModePercentile,
      )..finalizeBaseline(warningThresholdPercentile: 90, captureAnchor: false);
      expect(l.fixedMode, isFalse);
      expect(l.threshold, closeTo(0.089, 1e-9));
      l.setThresholdMode(
        guardThresholdModeFixed,
        warningThresholdPercentile: 90,
      );
      expect(l.threshold, 0.5);
      l.setThresholdMode(
        guardThresholdModePercentile,
        warningThresholdPercentile: 75,
      );
      expect(l.threshold, closeTo(0.074, 1e-9));
    });

    test('band math never runs fixed', () {
      final l = lane(
        band: true,
      )..finalizeBaseline(warningThresholdPercentile: 90, captureAnchor: false);
      expect(l.fixedMode, isFalse);
      expect(l.thresholdMode, guardThresholdModePercentile);
      expect(l.threshold, closeTo(0.089, 1e-9));
    });
  });

  group('Settings', () {
    test('prefs persist; band guards stay percentile', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await Settings.load();
      expect(s.aiGuardThresholdModePref, isNull);
      expect(
        s.guardThresholdModeFor(null, 'ai.a_vig'),
        guardThresholdModeFixed,
      );
      expect(s.aiGuardFixedThresholdFor(null), 0.5);
      await s.setAiGuardThresholdMode(guardThresholdModePercentile);
      await s.setAiGuardFixedThreshold(0.65);
      final again = await Settings.load();
      expect(again.aiGuardThresholdModePref, guardThresholdModePercentile);
      expect(
        again.guardThresholdModeFor(null, 'ai.a_vig'),
        guardThresholdModePercentile,
      );
      expect(
        again.guardThresholdModeFor(null, 'band.delta'),
        guardThresholdModePercentile,
      );
      expect(again.aiGuardFixedThresholdFor(null), 0.65);
      await again.setAiGuardThresholdMode(guardThresholdModeFixed);
      expect(
        again.guardThresholdModeFor(null, 'band.delta'),
        guardThresholdModePercentile,
      );
    });
  });

  group('SessionSettings metadata', () {
    Map<String, Object?> base() => {
      'guardrailEnabled': true,
      'guardFeature': 'ai.a_vig',
      'warningThresholdPercentile': 75,
    };

    test('records mode and value', () {
      final s = SessionSettings.fromJson({
        ...base(),
        'guardThresholdMode': 'fixed',
        'guardFixedThreshold': 0.5,
      })!;
      expect(s.guardThresholdMode, 'fixed');
      expect(s.guardFixedThreshold, 0.5);
      final json = s.toJson();
      expect(json['guardThresholdMode'], 'fixed');
      expect(json['guardFixedThreshold'], 0.5);
    });

    test('old sessions (no fields) read as null = percentile', () {
      final s = SessionSettings.fromJson(base())!;
      expect(s.guardThresholdMode, isNull);
      expect(s.guardFixedThreshold, isNull);
      expect(s.toJson().containsKey('guardThresholdMode'), isFalse);
      expect(
        SessionSettings.fromJson({
          ...base(),
          'guardThresholdMode': 'weird',
        })!.guardThresholdMode,
        isNull,
      );
    });
  });
}
