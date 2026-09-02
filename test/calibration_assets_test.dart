import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:muse_ml/src/audio/calibration_clips.dart';
import 'package:muse_ml/src/audio/guardrail_sound.dart';
import 'package:muse_ml/src/audio/output_ids.dart';
import 'package:muse_ml/src/feedback/feature_catalog.dart';
import 'package:muse_ml/src/feedback/protocol_catalog.dart';

/// Validates the two hand-edited asset files against each other and against
/// the Dart protocol definitions:
/// * `assets/calibrations.json` — every calibration has both a `single` and a
///   `staged` variant, and every referenced audio clip exists.
/// * `assets/protocols.json` — every protocol has full copy, a non-empty
///   `metadataDescription`, and a `calibration` id that exists in
///   `calibrations.json`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('calibrations.json is a valid v2 manifest', () async {
    final raw = await rootBundle.loadString(CalibrationManifest.asset);
    final manifest = CalibrationManifest.fromJson(jsonDecode(raw));
    expect(manifest, isNotNull);
    expect(manifest!.version, CalibrationManifest.currentVersion);
    expect(
      manifest.calibrations.keys,
      containsAll(['eyes-open-01', 'eyes-closed-01']),
    );
    for (final calibration in manifest.calibrations.values) {
      expect(
        calibration.single.isSingle,
        isTrue,
        reason: '${calibration.id}.single must be a single variant',
      );
      expect(
        calibration.staged.isStaged,
        isTrue,
        reason: '${calibration.id}.staged must be a staged variant',
      );
      expect(calibration.single.seconds, greaterThan(0));
      expect(calibration.single.intros, isNotEmpty);
      expect(calibration.staged.stages, isNotEmpty);
      for (final step in [
        ...calibration.single.intros,
        ...calibration.staged.stages,
      ]) {
        expect(
          File(step.file).existsSync(),
          isTrue,
          reason: 'calibration ${calibration.id} references missing $step.file',
        );
      }
    }
  });

  test(
    'protocols.json: every protocol has copy, calibration and description',
    () async {
      final raw = await rootBundle.loadString(ProtocolCatalog.asset);
      final json = jsonDecode(raw) as Map;
      expect(json['version'], 4);
      final featuresRaw = await rootBundle.loadString(FeatureCatalog.asset);
      final features = FeatureCatalog.fromJson(jsonDecode(featuresRaw) as Map);
      expect(features.byId.length, 8);
      final catalog = ProtocolCatalog.fromJson(json, features: features);
      expect(catalog.version, 4);
      final manifestRaw = await rootBundle.loadString(
        CalibrationManifest.asset,
      );
      final manifest = CalibrationManifest.fromJson(
        jsonDecode(manifestRaw),
        protocolsJson: jsonDecode(raw),
      )!;
      for (final info in catalog.all) {
        final copy = catalog.forName(info.id);
        expect(
          copy,
          isNotNull,
          reason: 'assets/protocols.json missing entry for ${info.id}',
        );
        expect(copy!.catchPhrase, isNotEmpty);
        expect(copy.title, isNotEmpty);
        expect(copy.subtitle, isNotEmpty);
        expect(copy.guideText, isNotEmpty);
        expect(copy.algorithmDescription, isNotEmpty);
        expect(
          copy.metadataDescription,
          isNotEmpty,
          reason: '${info.id} needs a metadataDescription',
        );
        expect(
          manifest.calibrationFor(info.id),
          isNotNull,
          reason:
              '${info.id} references an unknown calibration id '
              '(got ${manifest.calibrationIdFor(info.id)})',
        );
        if (info.reward != null) {
          final feature = features[info.reward!.feature];
          expect(
            feature,
            isNotNull,
            reason:
                'reward.feature ${info.reward!.feature} missing from features.json',
          );
          expect(
            feature!.usableAsReward(),
            isTrue,
            reason: '${info.reward!.feature} must be usableFor reward',
          );
          expect(
            RewardOutputId.values.map((e) => e.name),
            contains(info.reward!.output),
            reason:
                '${info.id} reward.output ${info.reward!.output} is not a RewardOutputId',
          );
        }
        if (info.guard != null) {
          final feature = features[info.guard!.feature];
          expect(
            feature,
            isNotNull,
            reason:
                'guard.feature ${info.guard!.feature} missing from features.json',
          );
          expect(
            feature!.usableAsGuard(),
            isTrue,
            reason: '${info.guard!.feature} must be usableFor guard',
          );
          expect(
            GuardrailSound.values.map((e) => e.name),
            contains(info.guard!.output),
            reason:
                '${info.id} guard.output ${info.guard!.output} is not a GuardrailSound',
          );
        }
      }
    },
  );

  test('recipe selection follows the compose table from S', () async {
    final manifestRaw = await rootBundle.loadString(CalibrationManifest.asset);
    final protocolsRaw = await rootBundle.loadString(ProtocolCatalog.asset);
    final manifest = CalibrationManifest.fromJson(
      jsonDecode(manifestRaw),
      protocolsJson: jsonDecode(protocolsRaw),
    )!;
    expect(manifest.calibrationIdFor('drowsiness'), 'eyes-closed-01');
    expect(manifest.calibrationIdFor('alertnessOpen'), 'eyes-open-01');
    expect(manifest.calibrationIdFor('recordOnly'), 'eyes-closed-01');
    expect(manifest.calibrationIdFor('guardrailOnly'), 'eyes-closed-01');

    final closedSingle = manifest.recipeFor(
      'eyes-closed-01',
      plan: CalibrationPlan.baselineOnly,
    )!;
    expect(closedSingle.isSingle, isTrue);
    expect(closedSingle.eyes, 'closed');
    expect(closedSingle.seconds, 50);

    final openSingle = manifest.recipeFor(
      'eyes-open-01',
      plan: CalibrationPlan.baselineOnly,
    )!;
    expect(openSingle.isSingle, isTrue);
    expect(openSingle.eyes, 'open');
    expect(openSingle.seconds, 50);

    final staged = manifest.recipeFor(
      'eyes-closed-01',
      plan: CalibrationPlan.stagedAi,
    )!;
    expect(staged.isStaged, isTrue);
    expect(staged.stages, hasLength(3));
    expect(staged.stages[0].id, 'reve-artifacts');
    expect(staged.stages[0].seconds, 15);
    expect(staged.stages[1].id, 'reve-eyes-open-counting');
    expect(staged.stages[1].seconds, 30);
    expect(staged.stages[2].id, 'reve-eyes-closed-drifting');
    expect(staged.stages[2].seconds, 45);

    expect(
      manifest
          .recipeFor(
            'eyes-closed-01',
            plan: CalibrationPlan.fromEnabledFeatures([]),
          )!
          .isSingle,
      isTrue,
      reason: 'recordOnly / empty S → single baseline',
    );
    expect(
      manifest
          .recipeFor(
            'eyes-closed-01',
            plan: CalibrationPlan.fromEnabledFeatures([
              'band.atr',
              'band.delta',
            ]),
          )!
          .isSingle,
      isTrue,
      reason: 'band reward + band.delta guard → single baseline',
    );
    expect(
      manifest
          .recipeFor(
            'eyes-closed-01',
            plan: CalibrationPlan.fromEnabledFeatures(['band.delta']),
          )!
          .isSingle,
      isTrue,
      reason: 'guardrailOnly + band-math → single baseline',
    );

    final guardrailOnlyAi = manifest.recipeFor(
      'eyes-closed-01',
      plan: CalibrationPlan.fromEnabledFeatures(['ai.drowsiness']),
    )!;
    expect(
      guardrailOnlyAi.isStaged,
      isTrue,
      reason: 'guardrailOnly + AI → artifact + challenge + baseline',
    );
    expect(guardrailOnlyAi.stages, hasLength(3));
    expect(guardrailOnlyAi.stages.last.seconds, 45);

    final rewardPlusAi = manifest.recipeFor(
      'eyes-closed-01',
      plan: CalibrationPlan.fromEnabledFeatures(['band.atr', 'ai.drowsiness']),
    )!;
    expect(rewardPlusAi.isStaged, isTrue);
    expect(
      rewardPlusAi.stages.last.seconds,
      calibrationAdaptiveBaselineSeconds,
    );

    final subset = manifest.recipeFor(
      'eyes-closed-01',
      plan: const CalibrationPlan(
        artifact: true,
        challenge: false,
        baseline: true,
      ),
    )!;
    expect(subset.isStaged, isTrue);
    expect(subset.stages.map((s) => s.id), [
      'reve-artifacts',
      'reve-eyes-closed-drifting',
    ]);
  });

  test('every audio file is covered by a pubspec asset entry', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assetsMatch = RegExp(
      r'^\s+-\s+(\S+)\s*$',
      multiLine: true,
    ).allMatches(pubspec).map((m) => m.group(1)!).toList();
    expect(
      assetsMatch,
      isNotEmpty,
      reason: 'pubspec.yaml must declare flutter.assets entries',
    );
    final dirEntries = assetsMatch.where((e) => e.endsWith('/')).toList();
    final fileEntries = assetsMatch.where((e) => !e.endsWith('/')).toSet();
    final uncovered = <String>[];
    for (final entity in Directory(
      'assets/audio',
    ).listSync(recursive: true).whereType<File>()) {
      final path = entity.path;
      if (fileEntries.contains(path)) {
        continue;
      }
      final coveredByDir = dirEntries.any((entry) {
        final dir = entry.substring(0, entry.length - 1);
        return path.startsWith('$dir/');
      });
      if (!coveredByDir) {
        uncovered.add(path);
      }
    }
    expect(
      uncovered,
      isEmpty,
      reason:
          'audio files not bundled: Flutter directory assets only '
          'include files directly in the directory — every subdirectory '
          'needs its own pubspec entry (regression of 469c031):\n'
          '${uncovered.join('\n')}',
    );
  });
}
