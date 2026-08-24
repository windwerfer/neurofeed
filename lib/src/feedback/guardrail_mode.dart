import 'package:muse_ml/src/reve/models.dart';

enum GuardrailMode {
  drowsinessMath,
  drowsinessLunaLarge,
  drowsinessLunaBase,
  drowsinessReveBase,
  none;

  bool get isAi => this != drowsinessMath && this != none;
  bool get isBandMath => this == drowsinessMath;

  String get ffId => switch (this) {
    GuardrailMode.drowsinessMath => 'bandMath',
    GuardrailMode.drowsinessLunaLarge => 'luna_large',
    GuardrailMode.drowsinessLunaBase => 'luna_base',
    GuardrailMode.drowsinessReveBase => 'reve_base',
    GuardrailMode.none => 'none',
  };

  String get label => switch (this) {
    GuardrailMode.drowsinessMath => 'Band math',
    GuardrailMode.drowsinessLunaLarge => 'LUNA Large',
    GuardrailMode.drowsinessLunaBase => 'LUNA Base',
    GuardrailMode.drowsinessReveBase => 'REVE Base',
    GuardrailMode.none => 'Disabled',
  };

  ModelKind? get modelKind => switch (this) {
    GuardrailMode.drowsinessLunaLarge => ModelKind.lunaLarge,
    GuardrailMode.drowsinessLunaBase => ModelKind.lunaBase,
    GuardrailMode.drowsinessReveBase => ModelKind.reveBase,
    _ => null,
  };

  static GuardrailMode fromName(String name) =>
      GuardrailMode.values.byName(name);
}