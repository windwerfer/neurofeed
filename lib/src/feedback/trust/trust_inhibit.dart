import 'dart:ui';

import 'package:neurofeed/src/charts/band_style.dart';
import 'package:neurofeed/src/feedback/protocol.dart';
import 'package:neurofeed/src/feedback/trust/trust_trace.dart';

/// Inhibit is a ceiling on relative band power. Pass zone is [0, ceiling].
enum TrustInhibitId { beta, delta }

class TrustInhibitSpec {
  const TrustInhibitSpec({required this.id, required this.ceiling});

  final TrustInhibitId id;
  final double ceiling;

  String get tag => switch (id) {
    TrustInhibitId.beta => 'beta',
    TrustInhibitId.delta => 'delta',
  };

  String get shortLabel => switch (id) {
    TrustInhibitId.beta => 'β',
    TrustInhibitId.delta => 'δ',
  };

  String get overshootLabel => switch (id) {
    TrustInhibitId.beta => 'beta high',
    TrustInhibitId.delta => 'delta high',
  };

  @override
  bool operator ==(Object other) =>
      other is TrustInhibitSpec && other.id == id && other.ceiling == ceiling;

  @override
  int get hashCode => Object.hash(id, ceiling);
}

List<TrustInhibitSpec> trustInhibitSpecs(List<TargetCondition> inhibit) {
  final out = <TrustInhibitSpec>[];
  for (final c in inhibit) {
    switch (c) {
      case BetaCeiling(:final maxBetaRel):
        out.add(TrustInhibitSpec(id: TrustInhibitId.beta, ceiling: maxBetaRel));
      case DeltaCeiling(:final maxDeltaRel):
        out.add(
          TrustInhibitSpec(id: TrustInhibitId.delta, ceiling: maxDeltaRel),
        );
    }
  }
  return out;
}

/// Band catalog colors so β / δ match Bands and the nerd stack.
Color inhibitSeriesColor(TrustInhibitId id) => switch (id) {
  TrustInhibitId.beta => bandColors[3],
  TrustInhibitId.delta => bandColors[0],
};

/// Overshoot leans toward [error] so a zone-exit is obvious, but keeps the
/// series hue so two inhibitors cannot collapse into the same stroke.
Color inhibitOvershootColor(TrustInhibitId id, Color error) {
  return Color.lerp(inhibitSeriesColor(id), error, 0.58)!;
}

enum TrustInhibitKind { inside, overshoot, dirty }

class TrustInhibitRun {
  TrustInhibitRun({required this.kind, required this.samples});

  final TrustInhibitKind kind;
  final List<TrustRewardSample> samples;

  double get tStart => samples.first.t;
  double get tEnd => samples.last.t;
}

double? inhibitPlotY(TrustRewardSample s, TrustInhibitSpec spec) =>
    switch (spec.id) {
      TrustInhibitId.beta => s.plotBetaRel ?? s.betaRel,
      TrustInhibitId.delta => s.plotDeltaRel ?? s.deltaRel,
    };

TrustInhibitKind inhibitStrokeKind(TrustRewardSample s, TrustInhibitSpec spec) {
  if (!s.clean) return TrustInhibitKind.dirty;
  final y = inhibitPlotY(s, spec);
  if (y != null && y > spec.ceiling) return TrustInhibitKind.overshoot;
  return TrustInhibitKind.inside;
}

List<TrustInhibitRun> inhibitRuns(
  List<TrustRewardSample> samples,
  TrustInhibitSpec spec,
) {
  if (samples.isEmpty) return const [];
  final out = <TrustInhibitRun>[];
  var kind = inhibitStrokeKind(samples.first, spec);
  var buf = <TrustRewardSample>[samples.first];
  for (var i = 1; i < samples.length; i++) {
    final k = inhibitStrokeKind(samples[i], spec);
    if (k == kind) {
      buf.add(samples[i]);
    } else {
      out.add(TrustInhibitRun(kind: kind, samples: buf));
      kind = k;
      buf = [samples[i]];
    }
  }
  out.add(TrustInhibitRun(kind: kind, samples: buf));
  return out;
}

/// Y domain: relative power 0–1, but zoom the top so a 0.25 ceiling is not
/// squashed into the bottom quarter. Always leaves room above the highest
/// ceiling so overshoot is visible.
double inhibitAxisMax(List<TrustInhibitSpec> specs) {
  var maxC = 0.0;
  for (final s in specs) {
    if (s.ceiling > maxC) maxC = s.ceiling;
  }
  if (maxC <= 0) return 1.0;
  final padded = maxC * 1.4;
  if (padded < 0.5) return 0.5;
  if (padded > 1.0) return 1.0;
  return padded;
}

String inhibitPaneLabel(List<TrustInhibitSpec> specs) {
  if (specs.isEmpty) return 'inhibit';
  return specs.map((s) => s.shortLabel).join(' · ');
}

Color inhibitRunColor(
  TrustInhibitKind kind, {
  required Color series,
  required Color overshoot,
}) => switch (kind) {
  TrustInhibitKind.inside => series,
  TrustInhibitKind.overshoot => overshoot,
  TrustInhibitKind.dirty => series,
};
