import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:muse_ml/src/audio/calibration_clips.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
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
      expect(calibration.single.isSingle, isTrue,
          reason: '${calibration.id}.single must be a single variant');
      expect(calibration.staged.isStaged, isTrue,
          reason: '${calibration.id}.staged must be a staged variant');
      expect(calibration.single.seconds, greaterThan(0));
      expect(calibration.single.intros, isNotEmpty);
      expect(calibration.staged.stages, isNotEmpty);
      for (final step in [
        ...calibration.single.intros,
        ...calibration.staged.stages,
      ]) {
        expect(File(step.file).existsSync(), isTrue,
            reason: 'calibration ${calibration.id} references missing $step.file');
      }
    }
  });

  test('protocols.json: every protocol has copy, calibration and description',
      () async {
    final raw = await rootBundle.loadString(ProtocolCatalog.asset);
    final json = jsonDecode(raw) as Map<String, Object?>;
    expect(json['version'], ProtocolCatalog.fromJson(json).version);
    final catalog = ProtocolCatalog.fromJson(json);
    final manifestRaw = await rootBundle.loadString(CalibrationManifest.asset);
    final manifest = CalibrationManifest.fromJson(
      jsonDecode(manifestRaw),
      protocolsJson: jsonDecode(raw),
    )!;
    for (final info in ProtocolInfo.all) {
      final copy = catalog.forName(info.type.name);
      expect(copy, isNotNull,
          reason: 'assets/protocols.json missing entry for ${info.type.name}');
      expect(copy!.catchPhrase, isNotEmpty);
      expect(copy.title, isNotEmpty);
      expect(copy.subtitle, isNotEmpty);
      expect(copy.guideText, isNotEmpty);
      expect(copy.algorithmDescription, isNotEmpty);
      expect(copy.metadataDescription, isNotEmpty,
          reason: '${info.type.name} needs a metadataDescription');
      expect(manifest.calibrationFor(info.type.name), isNotNull,
          reason:
              '${info.type.name} references an unknown calibration id '
              '(got ${manifest.calibrationIdFor(info.type.name)})');
    }
  });

  test('recipe selection: AI guardrail → staged, otherwise single', () async {
    final manifestRaw = await rootBundle.loadString(CalibrationManifest.asset);
    final protocolsRaw = await rootBundle.loadString(ProtocolCatalog.asset);
    final manifest = CalibrationManifest.fromJson(
      jsonDecode(manifestRaw),
      protocolsJson: jsonDecode(protocolsRaw),
    )!;
    expect(manifest.calibrationIdFor('drowsiness'), 'eyes-closed-01');
    expect(manifest.calibrationIdFor('alertnessOpen'), 'eyes-open-01');
    expect(manifest.calibrationIdFor('recordOnly'), 'eyes-closed-01');
    expect(manifest.recipeFor('drowsiness', useStaged: true)!.isStaged, isTrue);
    expect(manifest.recipeFor('drowsiness', useStaged: false)!.isSingle, isTrue);
    expect(
      manifest.recipeFor('alertnessOpen', useStaged: true)!.isStaged,
      isTrue,
    );
    expect(manifest.recipeFor('alertnessOpen', useStaged: false)!.isSingle,
        isTrue);
    expect(
      manifest.recipeFor('recordOnly', useStaged: true)!.isStaged,
      isTrue,
    );
  });

  test('every audio file is covered by a pubspec asset entry', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assetsMatch = RegExp(r'^\s+-\s+(\S+)\s*$', multiLine: true)
        .allMatches(pubspec)
        .map((m) => m.group(1)!)
        .toList();
    expect(assetsMatch, isNotEmpty,
        reason: 'pubspec.yaml must declare flutter.assets entries');
    final dirEntries = assetsMatch.where((e) => e.endsWith('/')).toList();
    final fileEntries = assetsMatch.where((e) => !e.endsWith('/')).toSet();
    final uncovered = <String>[];
    for (final entity in Directory('assets/audio')
        .listSync(recursive: true)
        .whereType<File>()) {
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
    expect(uncovered, isEmpty,
        reason: 'audio files not bundled: Flutter directory assets only '
            'include files directly in the directory — every subdirectory '
            'needs its own pubspec entry (regression of 469c031):\n'
            '${uncovered.join('\n')}');
  });
}
