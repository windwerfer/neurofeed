import 'package:muse_ml/src/feedback/trust/trust_trace.dart';

const bool kTrustHeldBackFill = true;

enum TrustStrokeKind { inZone, below, heldBack, dirty }

class TrustRun<T> {
  TrustRun({required this.kind, required this.samples});

  final TrustStrokeKind kind;
  final List<T> samples;

  double get tStart {
    final s = samples.first;
    if (s is TrustRewardSample) return s.t;
    if (s is TrustGuardSample) return s.t;
    throw ArgumentError('unknown sample');
  }

  double get tEnd {
    final s = samples.last;
    if (s is TrustRewardSample) return s.t;
    if (s is TrustGuardSample) return s.t;
    throw ArgumentError('unknown sample');
  }
}

TrustStrokeKind rewardStrokeKind(TrustRewardSample s) {
  if (!s.clean) return TrustStrokeKind.dirty;
  if (s.heldBack) return TrustStrokeKind.heldBack;
  if (s.inTarget) return TrustStrokeKind.inZone;
  return TrustStrokeKind.below;
}

List<TrustRun<TrustRewardSample>> rewardRuns(List<TrustRewardSample> samples) {
  if (samples.isEmpty) return const [];
  final out = <TrustRun<TrustRewardSample>>[];
  var kind = rewardStrokeKind(samples.first);
  var buf = <TrustRewardSample>[samples.first];
  for (var i = 1; i < samples.length; i++) {
    final k = rewardStrokeKind(samples[i]);
    if (k == kind) {
      buf.add(samples[i]);
    } else {
      out.add(TrustRun(kind: kind, samples: buf));
      kind = k;
      buf = [samples[i]];
    }
  }
  out.add(TrustRun(kind: kind, samples: buf));
  return out;
}

String? heldBackLabel(List<String> tags) {
  final beta = tags.contains('beta');
  final delta = tags.contains('delta');
  if (beta && delta) return 'beta · delta';
  if (beta) return 'beta high';
  if (delta) return 'delta high';
  return null;
}

String? dirtyRunLabel({
  required TrustDirtyReason reason,
  required double durationSeconds,
}) {
  switch (reason) {
    case TrustDirtyReason.pads:
      return 'pads';
    case TrustDirtyReason.movement:
      return 'movement';
    case TrustDirtyReason.jaw:
      if (durationSeconds >= 2) return 'jaw';
      return null;
    case TrustDirtyReason.blink:
      if (durationSeconds >= 2) return 'blink';
      return null;
  }
}

String? rewardRunLabel(TrustRun<TrustRewardSample> run) {
  if (run.kind == TrustStrokeKind.heldBack) {
    final tags = <String>{};
    for (final s in run.samples) {
      tags.addAll(s.inhibitTags);
    }
    return heldBackLabel(tags.toList());
  }
  if (run.kind == TrustStrokeKind.dirty) {
    final reasons = run.samples
        .map((s) => s.dirtyReason)
        .whereType<TrustDirtyReason>();
    final reason = dominantDirtyReason(reasons);
    if (reason == null) return null;
    return dirtyRunLabel(
      reason: reason,
      durationSeconds: run.tEnd - run.tStart + 1,
    );
  }
  return null;
}

bool shouldPaintHeldBackFill({
  required bool gate,
  required TrustStrokeKind kind,
}) => gate && kind == TrustStrokeKind.heldBack;

/// Occupancy of a run: [tStart, next sample t). Last run extends to [visEnd].
double heldBackFillEnd({
  required double tEnd,
  required double? nextT,
  required double visEnd,
}) {
  if (nextT != null) return nextT > tEnd ? nextT : tEnd;
  return visEnd > tEnd ? visEnd : tEnd;
}

/// Include the next run's first sample so a 1-point run still draws a segment.
List<T> runStrokeSamples<T>(List<T> samples, T? nextStart) {
  if (samples.isEmpty || nextStart == null) return samples;
  return [...samples, nextStart];
}

TrustRewardVerdict rewardVerdict(TrustRewardSample? now) {
  if (now == null) return TrustRewardVerdict.below;
  if (!now.clean) return TrustRewardVerdict.noisy;
  if (now.heldBack) return TrustRewardVerdict.heldBack;
  if (!now.inTarget) return TrustRewardVerdict.below;
  return TrustRewardVerdict.inZone;
}

String rewardVerdictCopy(TrustRewardVerdict v) => switch (v) {
  TrustRewardVerdict.inZone => 'In zone',
  TrustRewardVerdict.below => 'Below the line',
  TrustRewardVerdict.noisy => 'Noisy — not counting',
  TrustRewardVerdict.heldBack => 'Held back',
};

String rewardNowCopy(TrustRewardSample? now) {
  if (now == null) return 'below';
  if (!now.clean) return 'noisy';
  if (now.heldBack) return 'held back';
  if (!now.inTarget) return 'below';
  return 'above';
}

bool chimeEligible(TrustRewardSample? now) =>
    now != null && now.clean && now.inTarget && !now.heldBack;

String rewardStripGlyph(TrustRewardSample s) {
  if (!s.clean) return '·';
  if (s.heldBack) return '▒';
  if (s.inTarget) return '█';
  return '░';
}

String rewardStripText(List<TrustRewardSample> window) =>
    window.map(rewardStripGlyph).join();

double? inZonePercent(List<TrustRewardSample> window) {
  final counted = window.where((s) => s.clean).length;
  if (counted == 0) return null;
  final hits = window.where((s) => s.clean && s.inTarget).length;
  return 100.0 * hits / counted;
}

int rewardHoldSeconds(List<TrustRewardSample> samples) {
  var n = 0;
  for (var i = samples.length - 1; i >= 0; i--) {
    final s = samples[i];
    if (!s.clean || s.heldBack || !s.inTarget) break;
    n++;
  }
  return n;
}

TrustGuardVerdict guardVerdict(TrustGuardSample? now) {
  if (now == null) return TrustGuardVerdict.quiet;
  if (!now.clean) return TrustGuardVerdict.noisy;
  if (now.warningActive) return TrustGuardVerdict.warning;
  return TrustGuardVerdict.quiet;
}

String guardVerdictCopy(TrustGuardVerdict v) => switch (v) {
  TrustGuardVerdict.warning => 'Warning',
  TrustGuardVerdict.quiet => 'Quiet',
  TrustGuardVerdict.noisy => 'Noisy',
};

String guardNowCopy(TrustGuardSample? now) {
  if (now == null) return 'quiet';
  if (!now.clean) return 'noisy';
  if (!now.warningActive) return 'quiet';
  return 'warning';
}

String guardTripwireCopy(TrustGuardSample? now) {
  if (now == null || !now.warningActive) return '';
  if (now.warnOver && now.ceilingOver) return 'both';
  if (now.warnOver) return 'warn';
  if (now.ceilingOver) return 'ceiling';
  return '';
}

String guardStripGlyph(TrustGuardSample s) {
  if (!s.clean) return '·';
  if (s.warningActive) return '█';
  return '░';
}

String guardStripText(List<TrustGuardSample> window) =>
    window.map(guardStripGlyph).join();

double? warningPercent(List<TrustGuardSample> window) {
  final counted = window.where((s) => s.clean).length;
  if (counted == 0) return null;
  final hits = window.where((s) => s.clean && s.warningActive).length;
  return 100.0 * hits / counted;
}

int guardHoldSeconds(List<TrustGuardSample> samples) {
  var n = 0;
  for (var i = samples.length - 1; i >= 0; i--) {
    final s = samples[i];
    if (!s.clean || !s.warningActive) break;
    n++;
  }
  return n;
}

List<TrustRewardSample> lastWindow(
  List<TrustRewardSample> samples, {
  double seconds = 75,
}) {
  if (samples.isEmpty) return const [];
  final cut = samples.last.t - seconds + 1e-9;
  return [
    for (final s in samples)
      if (s.t >= cut) s,
  ];
}

List<TrustGuardSample> lastGuardWindow(
  List<TrustGuardSample> samples, {
  double seconds = 75,
}) {
  if (samples.isEmpty) return const [];
  final cut = samples.last.t - seconds + 1e-9;
  return [
    for (final s in samples)
      if (s.t >= cut) s,
  ];
}
