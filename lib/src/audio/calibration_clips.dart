import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One playable clip inside a calibration recipe: an intro variant for a
/// `single` calibration or a fixed stage for a `staged` one.
class CalibrationStep {
  const CalibrationStep({
    required this.id,
    required this.file,
    this.text = '',
    this.seconds = 0,
    this.eyes,
    this.challengeText = const [],
    this.challengeTextHint,
  });

  final String id;
  final String file;

  /// Spoken transcript of the clip (placeholder until real recordings exist).
  final String text;

  /// Collection seconds associated with this step. 0 for intro variants (the
  /// single calibration's silent window lives on the recipe); the fixed length
  /// of each silent window for staged steps.
  final int seconds;

  /// `open`, `closed`, or null when the step does not instruct an eye state.
  final String? eyes;

  /// Mentally-active challenge prompts shown on screen during the stage (e.g.
  /// "name capital cities"); one is picked at random per calibration run.
  final List<String> challengeText;

  /// Fixed help line shown above [challengeText] (identical regardless of the
  /// chosen prompt).
  final String? challengeTextHint;

  /// Picks a random [challengeText] entry, or null when the step has none.
  String? randomChallenge([Random? random]) {
    if (challengeText.isEmpty) {
      return null;
    }
    return challengeText[(random ?? Random()).nextInt(challengeText.length)];
  }

  factory CalibrationStep.fromJson(Map<String, Object?> json) =>
      CalibrationStep(
        id: json['id'] as String? ?? '',
        file: json['file'] as String? ?? '',
        text: json['text'] as String? ?? '',
        seconds: (json['seconds'] as num?)?.toInt() ?? 0,
        eyes: json['eyes'] as String?,
        challengeText:
            (json['challengeText'] as List<Object?>?)
                ?.whereType<String>()
                .toList() ??
            const [],
        challengeTextHint: json['challengeTextHint'] as String?,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'file': file,
    if (text.isNotEmpty) 'text': text,
    if (seconds > 0) 'seconds': seconds,
    if (eyes != null) 'eyes': eyes,
    if (challengeText.isNotEmpty) 'challengeText': challengeText,
    if (challengeTextHint != null) 'challengeTextHint': challengeTextHint,
  };
}

/// One calibration variant inside a [Calibration]: either the `single`
/// baseline (a random intro variant, then one silent window of [seconds] with
/// [eyes] in that state) or the `staged` guardrail sequence (a fixed ordered
/// list of [stages]; each stage plays a clip then collects silently for that
/// stage's `seconds`).
class CalibrationRecipe {
  const CalibrationRecipe._({
    required this.kind,
    this.seconds = 0,
    this.eyes,
    this.intros = const [],
    this.stages = const [],
  });

  /// `single` or `staged` (see [isSingle]/[isStaged]).
  final String kind;

  /// Silent-baseline length (seconds) for a `single` calibration.
  final int seconds;

  /// Eye state during the `single` baseline window.
  final String? eyes;

  /// Randomizable intro variants (only `single`).
  final List<CalibrationStep> intros;

  /// Fixed ordered steps (only `staged`).
  final List<CalibrationStep> stages;

  factory CalibrationRecipe.single({
    int seconds = 0,
    String? eyes,
    List<CalibrationStep> intros = const [],
  }) =>
      CalibrationRecipe._(kind: 'single', seconds: seconds, eyes: eyes, intros: intros);

  factory CalibrationRecipe.staged({
    List<CalibrationStep> stages = const [],
  }) =>
      CalibrationRecipe._(kind: 'staged', stages: stages);

  bool get isSingle => kind == 'single';

  bool get isStaged => kind == 'staged';

  /// A random intro variant for this recipe, or null when there are none.
  CalibrationStep? randomIntro([Random? random]) {
    if (intros.isEmpty) {
      return null;
    }
    return intros[(random ?? Random()).nextInt(intros.length)];
  }

  /// Parses the `single` or `staged` variant JSON from `assets/calibrations.json`.
  factory CalibrationRecipe.fromJson(String kind, Map<String, Object?> json) {
    final listKey = kind == 'staged' ? 'stages' : 'intros';
    final steps = (json[listKey] as List<Object?>?)
        ?.whereType<Map<String, Object?>>()
        .map(CalibrationStep.fromJson)
        .toList() ??
        const [];
    return kind == 'staged'
        ? CalibrationRecipe.staged(stages: steps)
        : CalibrationRecipe.single(
            seconds: (json['seconds'] as num?)?.toInt() ?? 0,
            eyes: json['eyes'] as String?,
            intros: steps,
          );
  }

  Map<String, Object?> toJson() => isSingle
      ? {
          'seconds': seconds,
          if (eyes != null) 'eyes': eyes,
          if (intros.isNotEmpty) 'intros': [for (final s in intros) s.toJson()],
        }
      : {'stages': [for (final s in stages) s.toJson()]};
}

/// One calibration in `assets/calibrations.json`, keyed by id. A calibration
/// is an eye-state (eyes open / eyes closed) with both playable variants —
/// the `single` baseline and the `staged` guardrail sequence. The protocol
/// decides which variant runs (AI model → staged, band math / no guardrail →
/// single).
class Calibration {
  const Calibration({
    required this.id,
    required this.name,
    required this.single,
    required this.staged,
  });

  /// Id referenced by `assets/protocols.json` protocol entries, e.g.
  /// `eyes-closed-01`.
  final String id;
  final String name;
  final CalibrationRecipe single;
  final CalibrationRecipe staged;

  /// The recipe that runs for this calibration given the guardrail intent.
  CalibrationRecipe variant(bool useStaged) => useStaged ? staged : single;

  factory Calibration.fromJson(String id, Map<String, Object?> json) =>
      Calibration(
        id: id,
        name: json['name'] as String? ?? id,
        single: CalibrationRecipe.fromJson(
          'single',
          json['single'] as Map<String, Object?>? ?? const {},
        ),
        staged: CalibrationRecipe.fromJson(
          'staged',
          json['staged'] as Map<String, Object?>? ?? const {},
        ),
      );

  /// Full round-trip of this calibration's definition, used as the immutable
  /// snapshot recorded in session metadata.
  Map<String, Object?> toJson() => {
    'name': name,
    'single': single.toJson(),
    'staged': staged.toJson(),
  };
}

/// Joins `calibrations.json` (the calibration definitions, keyed by id) with
/// `protocols.json` (the one-to-one protocol → calibration mapping) into one
/// lookup surface.
class CalibrationManifest {
  const CalibrationManifest({
    required this.version,
    required this.calibrations,
    required this.protocolCalibration,
  });

  /// Manifest schema version; persisted in session metadata.
  final int version;

  /// Calibration definitions by id.
  final Map<String, Calibration> calibrations;

  /// The calibration id each protocol uses (protocols.json order is a
  /// one-to-one mapping; every protocol has exactly one calibration).
  final Map<String, String> protocolCalibration;

  static const String asset = 'assets/calibrations.json';
  static const String protocolsAsset = 'assets/protocols.json';
  static const int currentVersion = 2;

  /// The calibration id [protocolName] uses, or null when unknown.
  String? calibrationIdFor(String protocolName) =>
      protocolCalibration[protocolName];

  /// The calibration definition for [protocolName], or null when the protocol
  /// or its calibration id is unknown.
  Calibration? calibrationFor(String protocolName) {
    final id = protocolCalibration[protocolName];
    return id == null ? null : calibrations[id];
  }

  /// Recipe for [protocolName]: the `staged` variant when [useStaged] (AI
  /// sleep guardrail), else the `single` baseline. Null when the protocol or
  /// its calibration is unknown.
  CalibrationRecipe? recipeFor(String protocolName, {required bool useStaged}) =>
      calibrationFor(protocolName)?.variant(useStaged);

  /// Full definition snapshot of [protocolName]'s calibration (id + name +
  /// both variants), as persisted in session metadata.
  Map<String, Object?>? calibrationJsonFor(String protocolName) =>
      calibrationFor(protocolName)?.toJson();

  static CalibrationManifest? fromJson(
    Object? calibrationJson, {
    Object? protocolsJson,
  }) {
    if (calibrationJson is! Map<String, Object?>) {
      return null;
    }
    final rawCalibrations =
        calibrationJson['calibrations'] as Map<String, Object?>? ?? const {};
    final calibrations = <String, Calibration>{
      for (final entry in rawCalibrations.entries)
        if (entry.value is Map<String, Object?>)
          entry.key: Calibration.fromJson(
            entry.key,
            entry.value as Map<String, Object?>,
          ),
    };
    final rawProtocols = protocolsJson is Map<String, Object?>
        ? (protocolsJson['protocols'] as Map<String, Object?>?) ?? const {}
        : const <String, Object?>{};
    final protocolCalibration = <String, String>{
      for (final entry in rawProtocols.entries)
        if (entry.value is Map<String, Object?> &&
            (entry.value as Map<String, Object?>)['calibration'] is String)
          entry.key:
              (entry.value as Map<String, Object?>)['calibration'] as String,
    };
    return CalibrationManifest(
      version: (calibrationJson['version'] as num?)?.toInt() ?? currentVersion,
      calibrations: calibrations,
      protocolCalibration: protocolCalibration,
    );
  }

  static Future<CalibrationManifest> load() async {
    final calibrationRaw = await rootBundle.loadString(asset);
    final protocolsRaw = await rootBundle.loadString(protocolsAsset);
    final parsed = fromJson(
      jsonDecode(calibrationRaw),
      protocolsJson: jsonDecode(protocolsRaw),
    );
    if (parsed == null) {
      throw FormatException('calibrations.json is not a valid manifest');
    }
    return parsed;
  }
}

final calibrationManifestProvider = FutureProvider<CalibrationManifest>(
  (ref) => CalibrationManifest.load(),
);