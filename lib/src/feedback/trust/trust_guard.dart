import 'package:muse_ml/src/feedback/guardrail_mode.dart';

enum TrustGuardPaneId { warn, ceiling }

/// One pane per distinct warn signal. Band-math scores native `band.delta`
/// against both the personal percentile and the 0.25 ceiling — one signal,
/// one pane. AI scores `sleep_dir` and still rails on always-on frontal δ —
/// two signals, two panes. Guard enabled with `none` is empty (no lane).
List<TrustGuardPaneId> trustGuardPaneSpecs(String guardFeature) {
  if (guardFeature == guardFeatureNone) return const [];
  return [
    TrustGuardPaneId.warn,
    if (!guardFeatureIsBandMath(guardFeature)) TrustGuardPaneId.ceiling,
  ];
}
