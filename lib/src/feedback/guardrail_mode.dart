import 'package:neurofeed/src/reve/models.dart';

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

/// CBraMod-backed heads (Spur A encoder forward linked).
const Set<String> guardFeatureCbramodIds = {
  guardFeatureAiAVig,
  guardFeatureAiWakeLight,
  guardFeatureAiDrowsiness,
};

/// REVE-backed experimental heads (selectable when REVE base is installed).
const Set<String> guardFeatureReveIds = {
  guardFeatureAiAVigReve,
  guardFeatureAiWakeLightReve,
};

bool guardFeatureIsAi(String feature) => guardFeatureAiIds.contains(feature);

bool guardFeatureIsCbramod(String feature) =>
    guardFeatureCbramodIds.contains(feature);

bool guardFeatureIsReve(String feature) => guardFeatureReveIds.contains(feature);

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
      // Legacy LUNA mode names → Spur A A-vig. Keep CBraMod feature ids.
      'drowsinessLunaLarge' || 'drowsinessLunaBase' => guardFeatureAiAVig,
      'drowsinessCbramodAVig' || 'ai.drowsiness' => guardFeatureAiAVig,
      'ai.a_vig' => guardFeatureAiAVig,
      'ai.wake_light' => guardFeatureAiWakeLight,
      // Legacy REVE *mode* name → band.delta (do not auto-promote to REVE
      // heads). Explicit ai.*_reve ids are kept; UI/settings drop them when
      // REVE base is not installed.
      'drowsinessReveBase' => guardFeatureBandDelta,
      'ai.a_vig_reve' => guardFeatureAiAVigReve,
      'ai.wake_light_reve' => guardFeatureAiWakeLightReve,
      'none' => guardFeatureNone,
      _ => null,
    };
  }
  if (value is Map) {
    final feature = value['feature'];
    if (feature == guardFeatureBandDelta || feature == guardFeatureNone) {
      return feature as String;
    }
    if (feature is String && guardFeatureIsCbramod(feature)) {
      return feature;
    }
    if (feature is String && guardFeatureIsReve(feature)) {
      // Keep stored REVE head ids; callers must fall back to band.delta when
      // REVE base is not installed (settings load + scorer Done).
      return feature;
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
