import 'package:neurofeed/src/feedback/guardrail_mode.dart';

enum TrustGuardPaneId { warn, ceiling }

/// One pane per distinct warn signal. Band-math scores native `band.delta`
/// against both the personal percentile and the 0.25 ceiling — one signal,
/// one pane. AI scores `sleep_dir` and still rails on always-on frontal δ —
/// two signals, two panes — but only when the protocol actually rails
/// ([deltaRail], protocol `guard.deltaRail`). With the rail off (every
/// catalog AI guard) the δ ceiling is not a warn signal, so no ceiling pane
/// and no "over ceiling" summary. Guard enabled with `none` is empty (no
/// lane). Pass the session's saved protocol snapshot for old sessions.
List<TrustGuardPaneId> trustGuardPaneSpecs(
  String guardFeature, {
  bool deltaRail = true,
}) {
  if (guardFeature == guardFeatureNone) return const [];
  return [
    TrustGuardPaneId.warn,
    if (!guardFeatureIsBandMath(guardFeature) && deltaRail)
      TrustGuardPaneId.ceiling,
  ];
}
