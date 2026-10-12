import 'package:neurofeed/src/feedback/guardrail_mode.dart';

enum TrustGuardPaneId { warn, ceiling }

/// One pane per distinct warn signal. Live sessions have one: the guard's
/// threshold rule (the frontal-δ rail was removed 2026-10). [legacyCeiling]
/// is for history only: an old AI-guard session that railed on δ
/// (`guard.deltaRail` in its saved snapshot) AND recorded `ceilingOver`
/// frames gets its second pane back. Band-math scored native δ against both
/// rules — one signal, one pane. Guard enabled with `none` is empty.
List<TrustGuardPaneId> trustGuardPaneSpecs(
  String guardFeature, {
  bool legacyCeiling = false,
}) {
  if (guardFeature == guardFeatureNone) return const [];
  return [
    TrustGuardPaneId.warn,
    if (!guardFeatureIsBandMath(guardFeature) && legacyCeiling)
      TrustGuardPaneId.ceiling,
  ];
}
