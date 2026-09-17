import 'package:muse_ml/src/reve/models.dart';

const String guardFeatureBandDelta = 'band.delta';
const String guardFeatureAiDrowsiness = 'ai.drowsiness'; // deprecated alias → ai.a_vig
const String guardFeatureAiAVig = 'ai.a_vig';
const String guardFeatureAiWakeLight = 'ai.wake_light';
const String guardFeatureAiAVigReve = 'ai.a_vig_reve';
const String guardFeatureAiWakeLightReve = 'ai.wake_light_reve';
const String guardFeatureNone = 'none';

const Set<String> guardFeatureAiIds = {
  guardFeatureAiAVig,
  guardFeatureAiWakeLight,
  guardFeatureAiAVigReve,
  guardFeatureAiWakeLightReve,
  guardFeatureAiDrowsiness,
};

bool guardFeatureIsAi(String feature) => guardFeatureAiIds.contains(feature);

bool guardFeatureIsBandMath(String feature) => feature == guardFeatureBandDelta;

/// Writes today's historical `GuardrailMode.name` into session metadata
/// (`drowsinessMath`, `drowsinessCbramodAVig`, …). Do not write `bandMath` /
/// raw ffIds here.
String guardrailEngineName({
  required String feature,
  String? model,
}) {
  if (feature == guardFeatureNone) return 'none';
  if (feature == guardFeatureBandDelta) return 'drowsinessMath';
  return switch (model) {
    'cbramod_a_vig' => 'drowsinessCbramodAVig',
    'reve_base' => 'drowsinessReveBase',
    // Legacy LUNA ids → report as Spur A (LUNA removed).
    'luna_large' || 'luna_base' => 'drowsinessCbramodAVig',
    _ => 'drowsinessCbramodAVig',
  };
}

String? ffIdFromOldGuardrailModeName(String name) => switch (name) {
  'drowsinessCbramodAVig' => 'cbramod_a_vig',
  'drowsinessReveBase' => 'reve_base',
  // Migrate historical LUNA session prefs to Spur A.
  'drowsinessLunaLarge' || 'drowsinessLunaBase' => 'cbramod_a_vig',
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
      'drowsinessCbramodAVig' ||
      'drowsinessLunaLarge' ||
      'drowsinessLunaBase' ||
      'drowsinessReveBase' ||
      'ai.drowsiness' =>
        guardFeatureAiDrowsiness,
      'ai.a_vig' => guardFeatureAiAVig,
      'ai.wake_light' => guardFeatureAiWakeLight,
      'ai.a_vig_reve' => guardFeatureAiAVigReve,
      'ai.wake_light_reve' => guardFeatureAiWakeLightReve,
      'none' => guardFeatureNone,
      _ => null,
    };
  }
  if (value is Map) {
    final feature = value['feature'];
    if (feature == guardFeatureBandDelta ||
        feature == guardFeatureNone ||
        (feature is String && guardFeatureIsAi(feature))) {
      return feature as String;
    }
  }
  return null;
}

ModelKind? modelKindFromFfId(String? ffId) {
  if (ffId == null) return null;
  // Historical LUNA prefs → Spur A.
  if (ffId == 'luna_large' || ffId == 'luna_base') {
    return ModelKind.cbramodAVig;
  }
  for (final kind in ModelKind.values) {
    if (kind.ffId == ffId) return kind;
  }
  return null;
}

String guardFeatureLabel(String feature) => switch (feature) {
  guardFeatureNone => 'Off',
  guardFeatureBandDelta => 'Band math (delta)',
  guardFeatureAiAVig => 'CBraMod A-vig',
  guardFeatureAiWakeLight => 'CBraMod wake/light',
  guardFeatureAiAVigReve => 'REVE A-vig (exp.)',
  guardFeatureAiWakeLightReve => 'REVE wake/light (exp.)',
  guardFeatureAiDrowsiness => 'AI drowsiness (legacy)',
  _ => feature,
};
