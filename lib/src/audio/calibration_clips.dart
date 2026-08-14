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

  factory CalibrationStep.fromJson(Map<String, Object?> json) =>
      CalibrationStep(
        id: json['id'] as String? ?? '',
        file: json['file'] as String? ?? '',
        text: json['text'] as String? ?? '',
        seconds: (json['seconds'] as num?)?.toInt() ?? 0,
        eyes: json['eyes'] as String?,
      );
}

/// How a feedback protocol calibrates. Two kinds today:
///
/// * `single` — one random intro variant, then one silent baseline window of
///   [seconds] with [eyes] in that state.
/// * `staged` — a fixed ordered list of [stages]; each stage plays a clip then
///   collects silently for that stage's `seconds`.
class CalibrationRecipe {
  const CalibrationRecipe({
    required this.protocol,
    required this.kind,
    this.seconds = 0,
    this.eyes,
    this.intros = const [],
    this.stages = const [],
  });

  final String protocol;

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
        protocol: json['protocol'] as String? ?? '',
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

/// Parsed `assets/audio/calibration/calibration.json` (v2): a version tag plus
/// one calibration recipe per feedback protocol.
class CalibrationManifest {
  const CalibrationManifest({required this.version, required this.recipes});

  /// Manifest schema version; persisted in session metadata.
  final int version;
  final List<CalibrationRecipe> recipes;

  static const String asset = 'assets/audio/calibration/calibration.json';
  static const int currentVersion = 2;

  CalibrationRecipe? recipeFor(String protocolName) {
    for (final recipe in recipes) {
      if (recipe.protocol == protocolName) {
        return recipe;
      }
    }
    return null;
  }

  static CalibrationManifest? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final raw = json['calibrations'] as List<Object?>? ?? const [];
    final recipes = raw
        .whereType<Map<String, Object?>>()
        .map(CalibrationRecipe.fromJson)
        .toList();
    return CalibrationManifest(
      version: (json['version'] as num?)?.toInt() ?? currentVersion,
      recipes: recipes,
    );
  }

  static Future<CalibrationManifest> load() async {
    final raw = await rootBundle.loadString(asset);
    final parsed = fromJson(jsonDecode(raw));
    if (parsed == null) {
      throw FormatException('calibration.json is not a valid manifest');
    }
    return parsed;
  }
}

final calibrationManifestProvider = FutureProvider<CalibrationManifest>(
  (ref) => CalibrationManifest.load(),
);