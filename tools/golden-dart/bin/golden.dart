// Golden-fixture generator: drives the vendored (verbatim) legacy RatioEngine,
// RelativeBandAggregator, BaselineWindow/BaselineFrameClock and stability math
// with scripted per-second inputs. The lane/notifier glue (RewardLane.onFeature,
// GuardLane band-math warn, calibration accept rule, 1 Hz ticker) depends on
// Riverpod/FRB/audio, so it is transcribed below line-for-line (see README.md).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../.vendor/baseline_window.dart';
import '../.vendor/feedback_phase.dart';
import '../.vendor/shim.dart';
import '../.vendor/stability_pct.dart';
import '../.vendor/target_state.dart';

// ---------- deterministic inputs ----------
class Lcg {
  Lcg(this.s);
  int s;
  double next() {
    s = (s * 6364136223846793005 + 1442695040888963407) & 0x7fffffffffffffff;
    return (s >> 11) / (1 << 52);
  }
  double noise() => next() * 2 - 1; // [-1,1)
}

Map<String, Object?> sec({
  required double t,
  double? w,
  required double atr,
  double beta = 0.5,
  double delta = 0.8,
  List<double> q = const [95, 95, 95, 95],
  String? art,
  List<int>? fpads,
  List<List<double>>? padsOverride,
}) {
  // Absolute powers: theta=1, alpha=atr, so every pad's ATR == atr.
  final pad = [delta, 1.0, atr, beta, 0.3];
  return {
    't': t,
    'w': w ?? t,
    'pads': padsOverride ?? List.generate(q.length, (_) => pad),
    'q': q,
    'art': art,
    'fpads': fpads,
  };
}

// ---------- legacy feature (Rust aggregate_band_feature, mean-of-relative) ----------
double? feature(String id, Map<String, Object?> s) {
  final pads = (s['pads'] as List).cast<List>();
  final q = (s['q'] as List).cast<num>();
  final fp = (s['fpads'] as List?)?.cast<int>() ??
      [for (var i = 0; i < pads.length; i++) if (q[i] >= 80) i];
  if (fp.isEmpty) return null;
  if (id == 'band.delta') {
    return fp.map((i) => (pads[i][0] as num).toDouble()).reduce((a, b) => a + b) / fp.length;
  }
  var t = 0.0, a = 0.0, b = 0.0;
  for (final i in fp) {
    final p = pads[i].cast<num>().map((e) => e.toDouble()).toList();
    final tot = p.reduce((x, y) => x + y);
    t += p[1] / tot; a += p[2] / tot; b += p[3] / tot;
  }
  t /= fp.length; a /= fp.length; b /= fp.length;
  switch (id) {
    case 'band.atr': return t <= 0 ? null : a / t;
    case 'band.tar': return a <= 0 ? null : t / a;
    case 'band.btr': return t <= 0 ? null : b / t;
    case 'band.alpha': return a;
    case 'band.theta': return t;
    case 'band.beta': return b;
  }
  throw 'feature $id';
}

DateTime wall(Map<String, Object?> s) =>
    DateTime.fromMillisecondsSinceEpoch(((s['w'] as num) * 1000).round());

// ---------- scenario runner (transcribed glue) ----------
Map<String, Object?> run(String name, Map<String, Object?> cfg, List<Map<String, Object?>> calib,
    List<Map<String, Object?>> play, {Map<String, Object?>? divergence}) {
  final featureId = cfg['feature'] as String;
  final stabilityCfg = cfg['stability'] as Map?;
  final engine = RatioEngine(percentile: cfg['percentile'] as int, featureId: featureId);
  engine.setResponsiveness((cfg['responsiveness'] as num).toDouble());
  engine.setDynamicAdapt(cfg['dynamic_adapt'] as bool);
  if (stabilityCfg != null) {
    engine.setStability(StabilityConfig(
        windowSeconds: stabilityCfg['window'] as int,
        difficulty: (stabilityCfg['difficulty'] as num).toDouble()));
  }
  final inhibit = [
    for (final c in (cfg['inhibit'] as List).cast<Map>())
      (c['type'] as String, (c['max'] as num).toDouble())
  ];
  final guardCfg = cfg['guard'] as Map?;
  final guardBaseline = <double>[];
  double? guardThr;
  var warningActive = false;
  var lastChime = DateTime.fromMillisecondsSinceEpoch(-1000000000);
  final npads = ((calib.isNotEmpty ? calib : play).first['q'] as List).length;
  final names = [for (var i = 0; i < npads; i++) 'P$i'];
  final agg = RelativeBandAggregator(names, montageNames: names);
  void feedBands(Map<String, Object?> s) {
    final pads = (s['pads'] as List).cast<List>();
    for (var i = 0; i < pads.length; i++) {
      final p = pads[i].cast<num>().map((e) => e.toDouble()).toList();
      agg.update(BandsDto(electrode: i, timestamp: 0, delta: p[0], theta: p[1], alpha: p[2], beta: p[3], gamma: p[4]));
    }
  }
  List<double> qOf(Map<String, Object?> s) => (s['q'] as List).cast<num>().map((e) => e.toDouble()).toList();

  // ---- calibration: timed stages (no collection) then one baseline window ----
  final kind = cfg['calibration'] as String; // single | staged | skip
  final timedSeconds = kind == 'staged' ? 15 + 30 : 0; // artifacts + eyes-open counting
  Map<String, Object?>? calibOut;
  if (kind != 'skip') {
    var i = 0;
    for (; i < timedSeconds && i < calib.length; i++) {
      feedBands(calib[i]);
    }
    shimClock = wall(calib[i]);
    var window = const BaselineWindow().start(shimClock);
    final frames = BaselineFrameClock();
    final startSecond = shimClock.millisecondsSinceEpoch ~/ 1000;
    for (; i < calib.length; i++) {
      final s = calib[i];
      shimClock = wall(s);
      if (window.finishedAt(shimClock)) break;
      feedBands(s);
      final q = qOf(s);
      final clean = s['art'] == null;
      final allGreen = q.every((v) => v >= signalGoodThreshold);
      final bucket = startSecond + (s['t'] as num).floor() - (calib[timedSeconds]['t'] as num).floor();
      // reward feature, then guard feature (same source second → frame clock).
      final v = feature(featureId, s);
      if (v != null && v.isFinite) {
        final tk = frames.take(sourceSecond: bucket, featureId: featureId, accept: clean && allGreen);
        if (tk.opened && tk.accepted) window = window.recordAccepted();
        if (tk.store) engine.addBaselineSample(v);
      }
      if (guardCfg != null) {
        final g = feature('band.delta', s);
        if (g != null && g.isFinite) {
          final tk = frames.take(sourceSecond: bucket, featureId: 'band.delta', accept: clean && allGreen);
          if (tk.opened && tk.accepted) window = window.recordAccepted();
          if (tk.store) guardBaseline.add(g); // eyes == closed in every baseline window here
        }
      }
      if (window.finishedAt(shimClock)) { i++; break; }
    }
    engine.computeThreshold();
    if (guardCfg != null && guardBaseline.isNotEmpty) {
      final l = [...guardBaseline]..sort();
      guardThr = l[(((guardCfg['percentile'] as int) / 100) * (l.length - 1)).round()];
    }
    calibOut = {
      'consumed': i,
      'valid_seconds': window.validSeconds,
      'wall_seconds': window.wallSecondsAt(shimClock),
      'baseline_n': engine.baselineCount,
      'threshold': engine.threshold,
      'baseline_mean': engine.baselineMean,
      'baseline_sd': engine.baselineStddev,
      'baseline_cv': engine.baselineCv,
      'guard_n': guardBaseline.length,
      'guard_threshold': guardThr,
    };
  }

  // ---- play ----
  final out = <Map<String, Object?>>[];
  var elapsed = 0;
  var adaptTick = 0;
  double? lastNative, lastPct;
  double lastThrPct = 0;
  for (final s in play) {
    shimClock = wall(s);
    feedBands(s);
    final q = qOf(s);
    final clean = s['art'] == null;
    final v = feature(featureId, s);
    final rec = <String, Object?>{'t': s['t']};
    final guardBlocks = guardCfg != null && warningActive && stabilityCfg != null;
    var produced = false;
    if (v != null && v.isFinite) {
      final rel = agg.evaluate(q);
      final padsDown = rel == null;
      final dirty = !clean || padsDown;
      final dirtyReason = padsDown ? 'pads' : (clean ? null : s['art']);
      if (stabilityCfg != null) {
        engine.recordSessionSample(v, clean: !dirty);
        if (dirty) {
          if (lastNative != null) {
            produced = true;
            rec.addAll({'native': lastNative, 'pct': lastPct, 'thr': engine.threshold, 'thr_pct': lastThrPct,
              'in_target': false, 'held_back': <String>[], 'dirty': dirtyReason});
          }
        } else {
          final r = engine.pushStabilitySample(v);
          if (r != null) {
            produced = true;
            final thr = engine.threshold;
            final steady = engine.isInTarget(r);
            final inT = steady && !guardBlocks;
            lastNative = r;
            lastPct = stabilityOutputPercentile(r, thr);
            lastThrPct = thr == null ? 0 : stabilityOutputPercentile(thr, thr);
            engine.recordEpoch(inT);
            rec.addAll({'native': r, 'pct': lastPct, 'thr': thr, 'thr_pct': lastThrPct, 'in_target': inT,
              'held_back': steady && guardBlocks ? ['guard'] : <String>[], 'dirty': null});
          }
        }
      } else {
        produced = true;
        final pct = engine.percentileOf(v) ?? 50.0;
        final thr = engine.threshold;
        lastThrPct = thr == null ? 0 : engine.percentileOf(thr) ?? 0;
        if (dirty) {
          engine.recordSessionSample(v, clean: false);
          rec.addAll({'native': v, 'pct': pct, 'thr': thr, 'thr_pct': lastThrPct, 'in_target': false,
            'held_back': <String>[], 'dirty': dirtyReason});
        } else {
          final above = engine.isInTarget(v);
          final failed = <String>[];
          for (final (type, max) in inhibit) {
            if (type == 'betaCeiling' && !(rel.betaRel <= max)) failed.add('beta');
            if (type == 'deltaCeiling' && !(rel.deltaRel <= max)) failed.add('delta');
          }
          final inT = above && failed.isEmpty;
          engine.recordEpoch(inT);
          engine.recordSessionSample(v, clean: true);
          rec.addAll({'native': v, 'pct': pct, 'thr': thr, 'thr_pct': lastThrPct, 'in_target': inT,
            'held_back': above ? failed : <String>[], 'dirty': null});
        }
      }
    }
    // guard lane (band math, processed after reward in _onFeature)
    var chime = false;
    if (guardCfg != null) {
      final g = feature('band.delta', s);
      if (g != null && guardThr != null && clean) {
        warningActive = g > guardThr;
        if (warningActive && shimClock.difference(lastChime) >= const Duration(seconds: 20)) {
          lastChime = shimClock;
          chime = true;
        }
      }
      rec['warn'] = warningActive;
      rec['chime'] = chime;
      rec['muted'] = warningActive && (guardCfg['muffle'] as bool);
    }
    rec['produced'] = produced;
    rec['success_rate'] = engine.successRate;
    // 1 Hz ticker
    elapsed++;
    adaptTick++;
    if (adaptTick >= adaptIntervalSeconds) {
      adaptTick = 0;
      final before = engine.threshold;
      engine.adapt();
      rec['adapt'] = {'from': before, 'to': engine.threshold};
    }
    out.add(rec);
  }
  return {
    'name': name,
    'source': 'legacy Dart engine via tools/golden-dart (do not edit by hand)',
    'config': cfg,
    if (divergence != null) 'divergence': divergence,
    'calibration_inputs': calib,
    'play_inputs': play,
    'calibration': calibOut,
    'records': out,
  };
}

Map<String, Object?> cfg({
  String feature = 'band.atr',
  String calibration = 'single',
  List<Map<String, Object?>> inhibit = const [],
  Map<String, Object?>? guard,
  Map<String, Object?>? stability,
}) => {
  'feature': feature,
  'policy': stability == null ? 'percentileUptrain' : 'stabilityDowntrain',
  'percentile': defaultBaselinePercentile,
  'responsiveness': 0.5,
  'dynamic_adapt': true,
  'calibration': calibration,
  'inhibit': inhibit,
  'guard': guard,
  'stability': stability,
};

List<Map<String, Object?>> series(Lcg r, double t0, int n, double Function(int i, Lcg r) atr,
        {double Function(int i)? beta, double Function(int i)? delta, String? Function(int i)? art,
        List<double> Function(int i)? q, double wallOffset = 0}) =>
    [
      for (var i = 0; i < n; i++)
        sec(t: t0 + i, w: t0 + i + wallOffset, atr: atr(i, r), beta: beta?.call(i) ?? 0.5,
            delta: delta?.call(i) ?? 0.8, art: art?.call(i), q: q?.call(i) ?? const [95, 95, 95, 95])
    ];

void main(List<String> args) {
  final dir = Directory(args.first)..createSync(recursive: true);
  void write(Map<String, Object?> f) {
    File('${dir.path}/${f['name']}.json').writeAsStringSync(jsonEncode(f));
    stdout.writeln('wrote ${f['name']} (${(f['records'] as List).length} records)');
  }
  double base(int i, Lcg r) => 1.2 + 0.15 * r.noise();
  final r = Lcg(42);

  write(run('calib_single_clean', cfg(), series(r, 0, 50, base), series(r, 50, 40, base)));
  write(run('calib_single_dropouts', cfg(),
      series(r, 0, 70, base,
          art: (i) => i % 3 == 0 ? 'movement' : null,
          q: (i) => i % 7 == 0 ? const [95, 60, 95, 95] : const [95, 95, 95, 95]),
      series(r, 70, 20, base)));
  write(run('calib_staged', cfg(calibration: 'staged'),
      [...series(r, 0, 45, (i, r) => 3.0 + r.noise()), ...series(r, 45, 50, base)], series(r, 95, 40, base)));
  write(run('adapt_up_cap', cfg(), series(r, 0, 50, base), series(r, 50, 420, (i, r) => 2.5 + 0.1 * r.noise())));
  write(run('adapt_down', cfg(), series(r, 0, 50, base),
      series(r, 50, 480, (i, r) => i < 200 ? 2.5 + 0.1 * r.noise() : 1.3 + 0.12 * r.noise())));
  write(run('adapt_reset', cfg(), series(r, 0, 50, base),
      series(r, 50, 330, (i, r) => i < 150 ? 2.5 + 0.1 * r.noise() : 0.6 + 0.05 * r.noise())));
  write(run('inhibit_beta_delta',
      cfg(inhibit: [{'type': 'betaCeiling', 'max': 0.2}, {'type': 'deltaCeiling', 'max': 0.25}]),
      series(r, 0, 50, base),
      series(r, 50, 120, (i, r) => 1.4 + 0.1 * r.noise(),
          beta: (i) => i % 4 == 1 ? 1.5 : 0.5, delta: (i) => i % 4 == 2 ? 1.5 : 0.8)));
  write(run('reject_movement_pads', cfg(), series(r, 0, 50, base),
      series(r, 50, 120, (i, r) => 1.4 + 0.15 * r.noise(),
          art: (i) => const [null, 'movement', 'blink', 'jaw', null, null][i % 6],
          q: (i) => i % 10 == 5 ? const [40, 50, 60, 70] : (i % 10 == 7 ? const [95, 30, 95, 95] : const [95, 95, 95, 95]))));
  final stab = {'window': 10, 'difficulty': 0.1};
  write(run('stability', cfg(feature: 'band.alpha', stability: stab),
      series(r, 0, 50, (i, r) => 1.2 + 0.3 * r.noise()),
      series(r, 50, 300, (i, r) => i < 150 ? 1.2 + 0.05 * r.noise() : 1.2 + 0.6 * r.noise(),
          art: (i) => i % 25 == 3 ? 'movement' : null)));
  write(run('guard_band_delta', cfg(calibration: 'staged', guard: {'percentile': 75, 'muffle': false}),
      series(r, 0, 95, base, delta: (i) => 0.8 + 0.1 * sin(i.toDouble())),
      series(r, 95, 150, (i, r) => 1.3 + 0.15 * r.noise(),
          delta: (i) => (i ~/ 15).isOdd ? 1.6 : 0.8, art: (i) => i % 40 == 20 ? 'blink' : null)));

  // ---- intentional divergences (Rust differs on purpose; see docs/decisions.md) ----
  write(run('div_wall_clock', cfg(), series(r, 0, 50, base),
      [...series(r, 50, 100, (i, r) => i.isEven ? 2.5 : 0.9),
       ...series(r, 150, 200, (i, r) => i < 40 ? 2.5 : (i.isEven ? 2.5 : 0.9), wallOffset: 120)],
      divergence: {'fix': 'sample_time', 'note': 'wall clock jumps 120 s (pause) at play second 100; Rust windows use sample time t'}));
  write(run('div_no_threshold', cfg(calibration: 'skip'), const [],
      series(r, 0, 40, (i, r) => 1.0 + 0.5 * r.noise()),
      divergence: {'fix': 'no_fallback', 'note': 'no baseline: Dart rewards value > 1.0; Rust never rewards and reports no_threshold'}));
  write(run('div_same_pads', cfg(inhibit: [{'type': 'betaCeiling', 'max': 0.2}]), series(r, 0, 50, base),
      [for (var i = 0; i < 60; i++)
        sec(t: 50.0 + i, atr: 1.4, q: const [95, 95, 95, 50], fpads: const [0, 1, 2, 3],
            padsOverride: [[0.8, 1, 1.4, 0.5, 0.3], [0.8, 1, 1.4, 0.5, 0.3], [0.8, 1, 1.4, 0.5, 0.3],
              [0.8, 1, i.isEven ? 0.4 : 3.0, 2.5, 0.3]])],
      divergence: {'fix': 'same_pads', 'note': 'legacy feature used all pads (fpads) while limits used q>=80 pads; Rust uses q>=80 pads for both'}));
  write(run('div_mute_uptrain', cfg(calibration: 'staged', guard: {'percentile': 75, 'muffle': true}),
      series(r, 0, 95, base),
      series(r, 95, 90, (i, r) => 1.5 + 0.1 * r.noise(), delta: (i) => (i ~/ 15).isOdd ? 1.6 : 0.8),
      divergence: {'fix': 'mute_both_modes', 'note': 'Dart uptrain reports in_target while the guard mutes audio; Rust: muffle => in_target=false, held_back=[guard] in both policies'}));
  write(run('div_mute_stability', cfg(feature: 'band.alpha', calibration: 'staged', stability: stab, guard: {'percentile': 75, 'muffle': false}),
      series(r, 0, 95, (i, r) => 1.2 + 0.3 * r.noise()),
      series(r, 95, 90, (i, r) => 1.2 + 0.03 * r.noise(), delta: (i) => (i ~/ 15).isOdd ? 1.6 : 0.8),
      divergence: {'fix': 'mute_both_modes', 'note': 'Dart stability blocks reward on guard warning even with muffle=false; Rust blocks only when muffle=true'}));
}
