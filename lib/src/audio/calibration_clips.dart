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
}

/// A shared calibration template referenced by `protocols.json` (by id).
/// Two kinds today:
///
/// * `single` — one random intro variant, then one silent baseline window of
///   [seconds] with [eyes] in that state.
/// * `staged` — the guardrail calibration: a fixed ordered list of [stages];
///   each stage plays a clip then collects silently for that stage's
///   `seconds` (the eyes-open challenge stage builds the guardrail's clear
///   anchor).
class CalibrationRecipe {
  const CalibrationRecipe({
    required this.id,
    required this.kind,
    this.seconds = 0,
    this.eyes,
    this.intros = const [],
    this.stages = const [],
  });

  /// Id referenced by `protocols.json` protocol entries, e.g.
  /// `single-closed-90`.
  final String id;

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

  bool get isSingle => kind == 'single';

  bool get isStaged => kind == 'staged';

  /// A random intro variant for this recipe, or null when there are none.
  CalibrationStep? randomIntro([Random? random]) {
    if (intros.isEmpty) {
      return null;
    }
    return intros[(random ?? Random()).nextInt(intros.length)];
  }

  factory CalibrationRecipe.fromJson(Map<String, Object?> json) =>
      CalibrationRecipe(
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? 'single',
        seconds: (json['seconds'] as num?)?.toInt() ?? 0,
        eyes: json['eyes'] as String?,
        intros: _steps(json['intros']),
        stages: _steps(json['stages']),
      );

  static List<CalibrationStep> _steps(Object? raw) =>
      (raw as List<Object?>?)
          ?.whereType<Map<String, Object?>>()
          .map(CalibrationStep.fromJson)
          .toList() ??
      const [];
}

/// Joins `calibration.json` (the shared calibration templates) with
/// `protocols.json` (which protocol may use which template, in preference
/// order) into one lookup surface.
class CalibrationManifest {
  const CalibrationManifest({
    required this.version,
    required this.calibrations,
    required this.protocolCalibrations,
  });

  /// Manifest schema version; persisted in session metadata.
  final int version;

  /// Calibration templates by id.
  final Map<String, CalibrationRecipe> calibrations;

  /// Preferred calibration ids per protocol name (protocols.json order).
  final Map<String, List<String>> protocolCalibrations;

  static const String asset = 'assets/audio/calibration/calibration.json';
  static const String protocolsAsset =
      'assets/audio/calibration/protocols.json';
  static const int currentVersion = 1;

  /// Recipe for [protocolName]: the protocol's preferred entry matching the
  /// requested [guardrail] state — the staged (guardrail) calibration when the
  /// guardrail runs, the single baseline else — falling back to the
  /// protocol's first listed calibration when [guardrail] is null or no
  /// preference matches.
  CalibrationRecipe? recipeFor(String protocolName, {bool? guardrail}) {
    final ids = protocolCalibrations[protocolName];
    if (ids == null || ids.isEmpty) {
      return null;
    }
    CalibrationRecipe? first;
    for (final id in ids) {
      final recipe = calibrations[id];
      if (recipe == null) {
        continue;
      }
      first ??= recipe;
      if (guardrail == null) {
        return first;
      }
      if (guardrail && recipe.isStaged) {
        return recipe;
      }
      if (!guardrail && recipe.isSingle) {
        return recipe;
      }
    }
    return first;
  }

  static CalibrationManifest? fromJson(
    Object? calibrationJson, {
    Object? protocolsJson,
  }) {
    if (calibrationJson is! Map<String, Object?>) {
      return null;
    }
    final calibrations = {
      for (final raw in (calibrationJson['calibrations'] as List<Object?>?)
              ?.whereType<Map<String, Object?>>() ??
          const <Map<String, Object?>>[])
        if (raw['id'] is String) raw['id'] as String: CalibrationRecipe.fromJson(raw),
    };
    final rawProtocols = protocolsJson is Map<String, Object?>
        ? (protocolsJson['protocols'] as List<Object?>?) ?? const []
        : const <Object?>[];
    final protocolCalibrations = <String, List<String>>{};
    for (final raw in rawProtocols.whereType<Map<String, Object?>>()) {
      final name = raw['name'] as String?;
      if (name == null) {
        continue;
      }
      protocolCalibrations[name] = (raw['calibrations'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const [];
    }
    return CalibrationManifest(
      version:
          (calibrationJson['version'] as num?)?.toInt() ?? currentVersion,
      calibrations: calibrations,
      protocolCalibrations: protocolCalibrations,
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
      throw FormatException('calibration.json is not a valid manifest');
    }
    return parsed;
  }
}

final calibrationManifestProvider = FutureProvider<CalibrationManifest>(
  (ref) => CalibrationManifest.load(),
);
