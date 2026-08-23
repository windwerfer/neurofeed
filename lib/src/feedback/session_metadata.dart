import 'session_v5_models.dart';

/// Decimated per-second view of a session, stored in the metadata JSON so the
/// history detail can render bands / heart rate / SpO2 / movement / peak alpha
/// without reading the (potentially large) `.muse` body or replaying every raw
/// frame. The frame body stays the authoritative source for export/full analysis.
class SessionOverview {
  const SessionOverview({
    required this.bucketCount,
    required this.bucketWidthSecs,
    required this.startSecs,
    required this.endSecs,
    this.trainingStartSecs,
    this.bands = const {},
    this.pulse = const [],
    this.spo2 = const [],
    this.movement = const [],
    this.peakAlphaFreq = const [],
    this.peakAlphaPower = const [],
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

  /// One SpO2 % per bucket (null when no SpO2 data in that bucket).
  final List<double?> spo2;

  /// Movement score per bucket.
  final List<double?> movement;

  /// Peak-alpha frequency per bucket (from the most powerful peak in the bucket).
  final List<double?> peakAlphaFreq;

  /// Power of that peak per bucket.
  final List<double?> peakAlphaPower;

  /// Builds a [SessionOverview] from pre-computed columnar series (for v5 files).
  static SessionOverview fromColumns({
    required int bucketCount,
    required double bucketWidthSecs,
    required double startSecs,
    required double endSecs,
    double? trainingStartSecs,
    required Map<int, BandPowerSeries> bands,
    required List<double?> pulse,
    required List<double?> spo2,
    required List<double?> movement,
    required List<double?> peakAlphaFreq,
    required List<double?> peakAlphaPower,
  }) {
    return SessionOverview(
      bucketCount: bucketCount,
      bucketWidthSecs: bucketWidthSecs,
      startSecs: startSecs,
      endSecs: endSecs,
      trainingStartSecs: trainingStartSecs,
      bands: bands,
      pulse: pulse,
      spo2: spo2,
      movement: movement,
      peakAlphaFreq: peakAlphaFreq,
      peakAlphaPower: peakAlphaPower,
    );
  }

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
      'bucketCount': bucketCount,
      'bucketWidthSecs': bucketWidthSecs,
      'startSecs': startSecs,
      'endSecs': endSecs,
      if (trainingStartSecs != null) 'trainingStartSecs': trainingStartSecs,
      'bands': b,
      'pulse': pulse,
      'spo2': spo2,
      'movement': movement,
      'peakAlphaFreq': peakAlphaFreq,
      'peakAlphaPower': peakAlphaPower,
    };
  }

  static SessionOverview? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final bands = <int, BandPowerSeries>{};
    if (json['bands'] is Map) {
      for (final e in (json['bands'] as Map).entries) {
        final k = int.tryParse(e.key);
        if (k != null) {
          bands[k] = BandPowerSeries.fromJson(e.value as Map<String, dynamic>?)!;
        }
      }
    }
    return SessionOverview(
      bucketCount: (json['bucketCount'] as num?)?.toInt() ?? 0,
      bucketWidthSecs: (json['bucketWidthSecs'] as num?)?.toDouble() ?? 0,
      startSecs: (json['startSecs'] as num?)?.toDouble() ?? 0,
      endSecs: (json['endSecs'] as num?)?.toDouble() ?? 0,
      trainingStartSecs: (json['trainingStartSecs'] as num?)?.toDouble(),
      bands: bands,
      pulse:
          (json['pulse'] as List?)?.map((e) => (e as num?)?.toDouble()).toList() ?? [],
      spo2: (json['spo2'] as List?)?.map((e) => (e as num?)?.toDouble()).toList() ?? [],
      movement: (json['movement'] as List?)?.map((e) => (e as num?)?.toDouble()).toList() ?? [],
      peakAlphaFreq: (json['peakAlphaFreq'] as List?)?.map((e) => (e as num?)?.toDouble()).toList() ?? [],
      peakAlphaPower: (json['peakAlphaPower'] as List?)?.map((e) => (e as num?)?.toDouble()).toList() ?? [],
    );
  }
}

/// Per-electrode band power series for one bucket.
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

  Map<String, Object?> toJson() => {
    'delta': delta,
    'theta': theta,
    'alpha': alpha,
    'beta': beta,
    'gamma': gamma,
  };

  static BandPowerSeries? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return BandPowerSeries(
      delta: (json['delta'] as List?)?.map((e) => (e as num?)?.toDouble()).toList() ?? [],
      theta: (json['theta'] as List?)?.map((e) => (e as num?)?.toDouble()).toList() ?? [],
      alpha: (json['alpha'] as List?)?.map((e) => (e as num?)?.toDouble()).toList() ?? [],
      beta: (json['beta'] as List?)?.map((e) => (e as num?)?.toDouble()).toList() ?? [],
      gamma: (json['gamma'] as List?)?.map((e) => (e as num?)?.toDouble()).toList() ?? [],
    );
  }
}

/// Summary of a session for the history list.
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.metadata,
  });

  final String id;
  final SessionMetadata metadata;

  Map<String, Object?> toJson() => {
    'id': id,
    'metadata': metadata.toJson(),
  };

  static SessionSummary? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return SessionSummary(
      id: json['id'] as String? ?? '',
      metadata: SessionMetadata.fromJson(json['metadata'] as Map<String, dynamic>?)!,
    );
  }
}