import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/history/session_trust.dart';
import 'package:neurofeed/src/settings.dart';

/// Feedback-session totals for [HistoryDashboardSummary].
///
/// Recordings pass null, which omits in-zone and chime cells. A null percent
/// is `—` (the lane did not run, or its clean weight is 0). Chime counts are
/// the whole list, including 0.
class HistoryDashboardTotals {
  const HistoryDashboardTotals({
    this.pctInZone,
    this.pctInhibited,
    this.pctWarning,
    this.rewardChimes = 0,
    this.guardChimes = 0,
  });

  factory HistoryDashboardTotals.fromSessionTrust(SessionTrust trust) {
    return HistoryDashboardTotals(
      pctInZone: trust.pctInZone,
      pctInhibited: trust.pctInhibited,
      pctWarning: trust.pctWarning,
      rewardChimes: trust.rewardChimes,
      guardChimes: trust.guardChimes,
    );
  }

  /// 0–100, or null when that lane did not run or the clean weight is 0.
  final double? pctInZone;
  final double? pctInhibited;
  final double? pctWarning;
  final int rewardChimes;
  final int guardChimes;
}

/// Short block of History Dashboard numbers, then a `More` fold.
///
/// [stats] is the nested metadata `stats` object (not the old flat card).
/// [durationS] wins over [elapsedSeconds]; `0` falls through to elapsed.
/// A missing stat is omitted, not shown as `0`. A one-sided min/max or
/// battery bookend uses `—` for the missing side.
class HistoryDashboardSummary extends ConsumerWidget {
  const HistoryDashboardSummary({
    super.key,
    this.stats = const <String, Object?>{},
    this.durationS,
    this.elapsedSeconds,
    this.feedback,
  });

  final Map<String, Object?> stats;
  final num? durationS;
  final num? elapsedSeconds;
  final HistoryDashboardTotals? feedback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final expanded = settings.historyDashboardMoreExpanded;
    final style = Theme.of(context).textTheme.bodyLarge;
    final top = _topCells(
      stats,
      durationS: durationS,
      elapsedSeconds: elapsedSeconds,
      feedback: feedback,
    );
    final more = _moreCells(stats, feedback);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (top.isNotEmpty)
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [for (final cell in top) Text(cell, style: style)],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              settings.setHistoryDashboardMoreExpanded(!expanded);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.centerLeft,
            ),
            icon: Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              size: 18,
            ),
            label: const Text('More'),
          ),
        ),
        if (expanded && more.isNotEmpty)
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [for (final cell in more) Text(cell, style: style)],
          ),
      ],
    );
  }
}

List<String> _topCells(
  Map<String, Object?> stats, {
  num? durationS,
  num? elapsedSeconds,
  HistoryDashboardTotals? feedback,
}) {
  final duration = _clock(_resolvedDuration(durationS, elapsedSeconds));
  return [
    ?duration,
    if (feedback != null) _percentCell(feedback.pctInZone, 'in zone'),
    ?_percentStat(stats['quality'], 'pctGood', 'good'),
    ?_percentStat(stats['movement'], 'stillnessPct', 'still'),
    ?_peakAlpha(stats['peakAlpha']),
    ?_hrMean(stats['hr']),
    ?_spo2Mean(stats['spo2']),
    if (feedback != null) '${feedback.rewardChimes} chimes',
  ];
}

List<String> _moreCells(
  Map<String, Object?> stats,
  HistoryDashboardTotals? feedback,
) {
  return [
    if (feedback != null) ...[
      _percentCell(feedback.pctInhibited, 'inhibited'),
      _percentCell(feedback.pctWarning, 'guard warning'),
      '${feedback.guardChimes} guard chimes',
    ],
    ?_hrRange(stats['hr']),
    ?_spo2Range(stats['spo2']),
    ?_battery(stats['battery']),
    ..._annotationCells(stats['annotationSeconds']),
    ..._channelCells(stats['quality']),
    ..._experimentalCells(stats['experimental']),
  ];
}

/// `durationS` when it is a non-zero finite number; otherwise elapsed.
num? _resolvedDuration(num? durationS, num? elapsedSeconds) {
  if (durationS != null && durationS.isFinite && durationS != 0) {
    return durationS;
  }
  if (elapsedSeconds != null && elapsedSeconds.isFinite) return elapsedSeconds;
  if (durationS != null && durationS.isFinite) return durationS;
  return null;
}

String? _clock(num? seconds) {
  if (seconds == null || !seconds.isFinite || seconds < 0) return null;
  final total = seconds.floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final r = total % 60;
  final ss = r.toString().padLeft(2, '0');
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:$ss';
  }
  return '$m:$ss';
}

String _percentCell(double? value, String tail) {
  if (value == null || !value.isFinite) return '— $tail';
  return '${value.round()}% $tail';
}

String? _percentStat(Object? raw, String key, String tail) {
  final value = _finite(_asMap(raw)?[key]);
  if (value == null) return null;
  return '${value.round()}% $tail';
}

String? _peakAlpha(Object? raw) {
  final hz = _finite(_asMap(raw)?['maxPowerHz']);
  if (hz == null) return null;
  return 'Peak α ${hz.toStringAsFixed(1)} Hz';
}

String? _hrMean(Object? raw) {
  final mean = _finite(_asMap(raw)?['mean']);
  if (mean == null) return null;
  return '${mean.round()} bpm';
}

String? _spo2Mean(Object? raw) {
  final mean = _finite(_asMap(raw)?['mean']);
  if (mean == null) return null;
  return 'SpO₂ ${mean.round()}%';
}

String? _hrRange(Object? raw) {
  final span = _minMax(raw);
  if (span == null) return null;
  return 'Heart rate $span bpm';
}

String? _spo2Range(Object? raw) {
  final span = _minMax(raw);
  if (span == null) return null;
  return 'SpO₂ $span%';
}

String? _minMax(Object? raw) {
  final map = _asMap(raw);
  if (map == null) return null;
  final min = _finite(map['min']);
  final max = _finite(map['max']);
  if (min == null && max == null) return null;
  final a = min == null ? '—' : '${min.round()}';
  final b = max == null ? '—' : '${max.round()}';
  return '$a–$b';
}

String? _battery(Object? raw) {
  final map = _asMap(raw);
  if (map == null) return null;
  final start = _finite(map['startPct']);
  final end = _finite(map['endPct']);
  if (start == null && end == null) return null;
  final a = start == null ? '—' : '${start.round()}%';
  final b = end == null ? '—' : '${end.round()}%';
  return 'Battery $a → $b';
}

List<String> _annotationCells(Object? raw) {
  final map = _asMap(raw);
  if (map == null) return const [];
  const labeled = <(String, String)>[
    ('pause', 'Pause'),
    ('bad_quality', 'Bad contact'),
    ('disconnect', 'Disconnect'),
  ];
  final out = <String>[];
  for (final (key, label) in labeled) {
    final seconds = _finite(map[key]);
    if (seconds == null || seconds < 0) continue;
    final clock = _clock(seconds);
    if (clock == null) continue;
    out.add('$label $clock');
  }
  return out;
}

List<String> _channelCells(Object? quality) {
  final usable = _asMap(_asMap(quality)?['channelUsable']);
  if (usable == null || usable.isEmpty) return const [];
  final out = <String>[];
  for (final entry in usable.entries) {
    final value = _finite(entry.value);
    if (value == null) continue;
    out.add('${entry.key} ${(value * 100).round()}%');
  }
  return out;
}

const List<String> _experimentalKeyOrder = [
  'meanAlphaAbs',
  'meanAlphaTheta',
  'frontalAlphaAsym',
  'crossChannelAlphaVar',
  'meanAlphaRel',
  'frontalTemporalAlphaAsym',
  'meanBetaTheta',
  'meanThetaAbs',
  'meanBetaAbs',
  'temporalAlphaAsym',
];

String _experimentalLabel(String key) => switch (key) {
  'meanAlphaAbs' => 'Mean α',
  'meanAlphaTheta' => 'α/θ',
  'frontalAlphaAsym' => 'Frontal α asym',
  'crossChannelAlphaVar' => 'α variance',
  'meanAlphaRel' => 'Mean α rel',
  'frontalTemporalAlphaAsym' => 'Frontal–temporal α',
  'meanBetaTheta' => 'β/θ',
  'meanThetaAbs' => 'Mean θ',
  'meanBetaAbs' => 'Mean β',
  'temporalAlphaAsym' => 'Temporal α asym',
  _ => key,
};

List<String> _experimentalCells(Object? raw) {
  final experimental = _asMap(raw);
  if (experimental == null) return const [];
  final bands = _asMap(experimental['bands']) ?? experimental;
  if (bands.isEmpty) return const [];
  final out = <String>[];
  final seen = <String>{};
  for (final key in _experimentalKeyOrder) {
    final value = _finite(bands[key]);
    if (value == null) continue;
    seen.add(key);
    out.add('${_experimentalLabel(key)} ${_compact(value)}');
  }
  for (final entry in bands.entries) {
    if (seen.contains(entry.key) || entry.key == 'bands') continue;
    final value = _finite(entry.value);
    if (value == null) continue;
    out.add('${_experimentalLabel(entry.key)} ${_compact(value)}');
  }
  return out;
}

String _compact(num value) {
  final text = value.toStringAsFixed(2);
  if (!text.contains('.')) return text;
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, Object?>.from(
    value.map((key, entry) => MapEntry(key.toString(), entry)),
  );
}

num? _finite(Object? value) {
  if (value is! num || !value.isFinite) return null;
  return value;
}
