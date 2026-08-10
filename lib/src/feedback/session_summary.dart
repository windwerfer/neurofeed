import 'dart:math';

import 'package:muse_ml/src/charts/session_reader.dart';

/// Decimated per-second view of a session, stored in the metadata JSON so the
/// history detail can render bands / heart rate / movement / peak alpha
/// without reading the (potentially large) `.muse` body or replaying every raw
/// frame. The frame body stays the authoritative source for export/full analysis.
class SessionOverview {
  const SessionOverview({
    required this.bucketCount,
    required this.bucketWidthSecs,
    required this.startSecs,
    required this.endSecs,
    required this.bands,
    required this.pulse,
    required this.movement,
    required this.peakAlphaFreq,
    required this.peakAlphaPower,
    this.trainingStartSecs,
  });

  /// Fixed number of buckets regardless of session duration.
  static const int defaultBucketCount = 400;

  final int bucketCount;
  final double bucketWidthSecs;
  final double startSecs;
  final double endSecs;

  /// Seconds from the recording (calibration) start to the training boundary.
  /// Null on full-window overviews, including all files recorded before
  /// calibration recording existed — those render as they always did.
  final double? trainingStartSecs;

  /// Per-electrode band series keyed by electrode index.
  final Map<int, BandPowerSeries> bands;

  /// One bpm per bucket (null when no pulse data in that bucket).
  final List<double?> pulse;

  /// Movement score per bucket.
  final List<double?> movement;

  /// Peak-alpha frequency per bucket (from the most powerful peak in the bucket).
  final List<double?> peakAlphaFreq;

  /// Power of that peak per bucket.
  final List<double?> peakAlphaPower;

  Map<String, Object?> toJson() {
    final b = <String, Object?>{};
    for (final e in bands.entries) {
      b[e.key.toString()] = {
        'delta': e.value.delta,
        'theta': e.value.theta,
        'alpha': e.value.alpha,
        'beta': e.value.beta,
        'gamma': e.value.gamma,
      };
    }
    return {
      'buckets': bucketCount,
      'width': bucketWidthSecs,
      'start': startSecs,
      'end': endSecs,
      if (trainingStartSecs != null) 'trainingStart': trainingStartSecs,
      'bands': b,
      'pulse': pulse,
      'movement': movement,
      'peakAlphaFreq': peakAlphaFreq,
      'peakAlphaPower': peakAlphaPower,
    };
  }

  static SessionOverview? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final bandsJson = json['bands'] as Map<String, Object?>? ?? const {};
    final bands = <int, BandPowerSeries>{};
    for (final e in bandsJson.entries) {
      final electrode = int.tryParse(e.key);
      if (electrode == null || e.value is! Map<String, Object?>) {
        continue;
      }
      final entry = e.value as Map<String, Object?>;
      bands[electrode] = BandPowerSeries(
        delta: _numList(entry['delta']) ?? const [],
        theta: _numList(entry['theta']) ?? const [],
        alpha: _numList(entry['alpha']) ?? const [],
        beta: _numList(entry['beta']) ?? const [],
        gamma: _numList(entry['gamma']) ?? const [],
      );
    }
    return SessionOverview(
      bucketCount: (json['buckets'] as num?)?.toInt() ?? defaultBucketCount,
      bucketWidthSecs: (json['width'] as num?)?.toDouble() ?? 0,
      startSecs: (json['start'] as num?)?.toDouble() ?? 0,
      endSecs: (json['end'] as num?)?.toDouble() ?? 0,
      bands: bands,
      pulse: _numList(json['pulse']) ?? const [],
      movement: _numList(json['movement']) ?? const [],
      peakAlphaFreq: _numList(json['peakAlphaFreq']) ?? const [],
      peakAlphaPower: _numList(json['peakAlphaPower']) ?? const [],
      trainingStartSecs: (json['trainingStart'] as num?)?.toDouble(),
    );
  }

  static List<double?>? _numList(Object? v) {
    if (v is! List) {
      return null;
    }
    return v.map((e) => e is num ? e.toDouble() : null).toList();
  }

  /// Build a decimated summary from a full parsed session.
  ///
  /// [trainingStartSecs], when present, is the offset from recording start at
  /// which training (feedback) began; the returned overview is then trimmed to
  /// cover only the training portion (calibration lives in the `.muse` body
  /// but is excluded from the displayed/metriced window).
  factory SessionOverview.fromData(
    SessionData data, {
    double? trainingStartSecs,
  }) {
    if (data.bands.isEmpty) {
      return const SessionOverview(
        bucketCount: SessionOverview.defaultBucketCount,
        bucketWidthSecs: 1,
        startSecs: 0,
        endSecs: 0,
        bands: {},
        pulse: [],
        movement: [],
        peakAlphaFreq: [],
        peakAlphaPower: [],
      );
    }

    var minTs = double.infinity;
    var maxTs = -double.infinity;
    for (final b in data.bands) {
      minTs = min(minTs, b.timestamp);
      maxTs = max(maxTs, b.timestamp);
    }
    for (final p in data.pulses) {
      minTs = min(minTs, p.timestamp);
      maxTs = max(maxTs, p.timestamp);
    }
    for (final m in data.movements) {
      minTs = min(minTs, m.timestamp);
      maxTs = max(maxTs, m.timestamp);
    }

    var span = maxTs - minTs;
    if (span <= 0) {
      span = 1;
    }

    // Trim to the training portion. The boundary is an offset from the first
    // recorded event (which coincides with calibration start), so it is
    // insensitive to device-clock drift.
    final effectiveTrainingStart = (trainingStartSecs ?? 0) > 0
        ? ((trainingStartSecs!) <= span ? trainingStartSecs : null)
        : null;
    double startTs = minTs;
    if (effectiveTrainingStart != null) {
      startTs = minTs + effectiveTrainingStart;
      span -= effectiveTrainingStart;
    }
    final width = span / defaultBucketCount;

    final perElectrode = <int, List<BandsRecord>>{};
    for (final b in data.bands) {
      perElectrode.putIfAbsent(b.electrode, () => []).add(b);
    }

    final bands = <int, BandPowerSeries>{};
    for (final entry in perElectrode.entries) {
      bands[entry.key] = BandPowerSeries(
        delta: _bucketAvg(
          entry.value.map((b) => (b.timestamp, b.delta)).toList(),
          startTs,
          width,
        ),
        theta: _bucketAvg(
          entry.value.map((b) => (b.timestamp, b.theta)).toList(),
          startTs,
          width,
        ),
        alpha: _bucketAvg(
          entry.value.map((b) => (b.timestamp, b.alpha)).toList(),
          startTs,
          width,
        ),
        beta: _bucketAvg(
          entry.value.map((b) => (b.timestamp, b.beta)).toList(),
          startTs,
          width,
        ),
        gamma: _bucketAvg(
          entry.value.map((b) => (b.timestamp, b.gamma)).toList(),
          startTs,
          width,
        ),
      );
    }

    final pulse = _bucketAvg(
      data.pulses
          .where((p) => p.confidence >= 0.3)
          .map((p) => (p.timestamp, p.bpm))
          .toList(),
      startTs,
      width,
    );
    final movement = _bucketAvg(
      data.movements.map((m) => (m.timestamp, m.score)).toList(),
      startTs,
      width,
    );

    final freq = List<double?>.filled(defaultBucketCount, null);
    final power = List<double?>.filled(defaultBucketCount, null);
    for (final p in data.peakAlphas) {
      if (p.timestamp < startTs) {
        continue;
      }
      final idx = ((p.timestamp - startTs) / width).floor();
      if (idx >= 0 &&
          idx < defaultBucketCount &&
          (power[idx] == null || p.power > power[idx]!)) {
        power[idx] = p.power;
        freq[idx] = p.frequency;
      }
    }

    return SessionOverview(
      bucketCount: defaultBucketCount,
      bucketWidthSecs: width,
      startSecs: startTs,
      endSecs: maxTs,
      bands: bands,
      pulse: pulse,
      movement: movement,
      peakAlphaFreq: freq,
      peakAlphaPower: power,
      trainingStartSecs: effectiveTrainingStart,
    );
  }

  static List<double?> _bucketAvg(
    List<(double, double)> points,
    double start,
    double width,
  ) {
    final out = List<double?>.filled(defaultBucketCount, null);
    final sum = List<double>.filled(defaultBucketCount, 0);
    final cnt = List<int>.filled(defaultBucketCount, 0);
    for (final (t, v) in points) {
      // Points before the window start (e.g. calibration, when the overview is
      // trimmed to training) are excluded, not clamped into bucket 0.
      if (t < start) {
        continue;
      }
      var idx = ((t - start) / width).floor();
      if (idx >= defaultBucketCount) {
        idx = defaultBucketCount - 1;
      }
      sum[idx] += v;
      cnt[idx]++;
    }
    for (var i = 0; i < defaultBucketCount; i++) {
      if (cnt[i] > 0) {
        out[i] = sum[i] / cnt[i];
      }
    }
    return out;
  }
}

class BandPowerSeries {
  const BandPowerSeries({
    required this.delta,
    required this.theta,
    required this.alpha,
    required this.beta,
    required this.gamma,
  });

  final List<double?> delta;
  final List<double?> theta;
  final List<double?> alpha;
  final List<double?> beta;
  final List<double?> gamma;
}
