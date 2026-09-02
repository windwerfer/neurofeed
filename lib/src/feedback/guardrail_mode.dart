import 'package:muse_ml/src/reve/models.dart';

const String guardFeatureBandDelta = 'band.delta';
const String guardFeatureAiDrowsiness = 'ai.drowsiness';
const String guardFeatureNone = 'none';

bool guardFeatureIsAi(String feature) => feature == guardFeatureAiDrowsiness;

bool guardFeatureIsBandMath(String feature) => feature == guardFeatureBandDelta;

/// Writes today's historical `GuardrailMode.name` into session metadata
/// (`drowsinessMath`, `drowsinessLunaLarge`, …). Do not write `bandMath` /
/// `luna_base` here.
String guardrailEngineName({
  required String feature,
  String? model,
}) {
  if (feature == guardFeatureNone) return 'none';
  if (feature == guardFeatureBandDelta) return 'drowsinessMath';
  return switch (model) {
    'luna_large' => 'drowsinessLunaLarge',
    'luna_base' => 'drowsinessLunaBase',
    'reve_base' => 'drowsinessReveBase',
    _ => 'drowsinessLunaLarge',
  };
}

String? ffIdFromOldGuardrailModeName(String name) => switch (name) {
  'drowsinessLunaLarge' => 'luna_large',
  'drowsinessLunaBase' => 'luna_base',
  'drowsinessReveBase' => 'reve_base',
  _ => null,
};

bool oldGuardrailModeNameIsAi(String name) =>
    ffIdFromOldGuardrailModeName(name) != null;

/// Parse a stored per-protocol value: old `GuardrailMode.name` string or new
/// `{feature: ...}` object. Unknown values return null (caller applies
/// document defaults).
String? parseGuardFeatureValue(Object? value) {
  if (value is String) {
    return switch (value) {
      'drowsinessMath' || 'band.delta' => guardFeatureBandDelta,
      'drowsinessLunaLarge' ||
      'drowsinessLunaBase' ||
      'drowsinessReveBase' ||
      'ai.drowsiness' =>
        guardFeatureAiDrowsiness,
      'none' => guardFeatureNone,
      _ => null,
    };
  }
  if (value is Map) {
    final feature = value['feature'];
    if (feature == guardFeatureBandDelta ||
        feature == guardFeatureAiDrowsiness ||
        feature == guardFeatureNone) {
      return feature as String;
    }
  }
  return null;
}

ModelKind? modelKindFromFfId(String? ffId) {
  if (ffId == null) return null;
  for (final kind in ModelKind.values) {
    if (kind.ffId == ffId) return kind;
  }
  return null;
}

String guardFeatureLabel(String feature) => switch (feature) {
  guardFeatureNone => 'Off',
  guardFeatureBandDelta => 'Band math (delta)',
  guardFeatureAiDrowsiness => 'AI drowsiness',
  _ => feature,
};
