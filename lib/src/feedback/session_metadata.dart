import 'package:muse_ml/src/feedback/protocol.dart';
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
  final double? trainingStartSecs;

  /// Per-electrode band series keyed by electrode index.
  final Map<int, BandPowerSeries> bands;

  /// One bpm per bucket (null when no pulse data in that bucket).
  final List<double?> pulse;

  /// One SpO2 % per bucket (null when no SpO2 data in that bucket).
  final List<double?> spo2;

  /// Movement score per bucket.
  final List<double?> movement;

  /// Peak-alpha frequency per bucket.
  final List<double?> peakAlphaFreq;

  /// Power of that peak per bucket.
  final List<double?> peakAlphaPower;

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

  static SessionOverview? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
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
      bucketCount: (json['bucketCount'] as num?)?.toInt() ?? (json['buckets'] as num?)?.toInt() ?? 0,
      bucketWidthSecs: (json['bucketWidthSecs'] as num?)?.toDouble() ?? (json['width'] as num?)?.toDouble() ?? 0,
      startSecs: (json['startSecs'] as num?)?.toDouble() ?? (json['start'] as num?)?.toDouble() ?? 0,
      endSecs: (json['endSecs'] as num?)?.toDouble() ?? (json['end'] as num?)?.toDouble() ?? 0,
      trainingStartSecs: (json['trainingStartSecs'] as num?)?.toDouble() ?? (json['trainingStart'] as num?)?.toDouble(),
      bands: bands,
      pulse: (json['pulse'] as List?)?.map((e) => (e as num?)?.toDouble()).toList() ?? [],
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

enum GestureType { doubleBlink, doubleClench, eyeUp, eyeDown }

class GestureMarker {
  const GestureMarker({required this.type, required this.offsetSeconds});

  final GestureType type;
  final int offsetSeconds;

  Map<String, Object?> toJson() => {'type': type.name, 'at': offsetSeconds};

  static GestureMarker? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final name = json['type'] as String?;
    final type = GestureType.values.where((t) => t.name == name).firstOrNull;
    if (type == null) {
      return null;
    }
    return GestureMarker(
      type: type,
      offsetSeconds: (json['at'] as num?)?.toInt() ?? 0,
    );
  }
}

class DrowsinessSample {
  const DrowsinessSample({
    required this.offsetSecs,
    required this.sleepDir,
    required this.delta,
    required this.warning,
  });

  final double offsetSecs;
  final double sleepDir;
  final double delta;
  final bool warning;

  Map<String, Object?> toJson() => {
    'at': offsetSecs,
    'sleepDir': sleepDir,
    'delta': delta,
    'warning': warning,
  };

  static DrowsinessSample? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return DrowsinessSample(
      offsetSecs: (json['at'] as num?)?.toDouble() ?? 0,
      sleepDir: (json['sleepDir'] as num?)?.toDouble() ?? 0,
      delta: (json['delta'] as num?)?.toDouble() ?? 0,
      warning: json['warning'] as bool? ?? false,
    );
  }
}

class SessionDrowsiness {
  const SessionDrowsiness({
    required this.scoreTotalPct,
    required this.meanSleepDir,
    this.threshold,
    this.series = const [],
    this.buckets = const [],
    this.bucketWidthSecs = 0,
  });

  final double scoreTotalPct;
  final double meanSleepDir;
  final double? threshold;
  final List<DrowsinessSample> series;
  final List<DrowsinessSample> buckets;
  final double bucketWidthSecs;

  Map<String, Object?> toJson() => {
    'scoreTotalPct': scoreTotalPct,
    'meanSleepDir': meanSleepDir,
    if (threshold != null) 'threshold': threshold,
    if (buckets.isNotEmpty) 'width': bucketWidthSecs,
    if (buckets.isNotEmpty)
      'buckets': [for (final b in buckets) b.toJson()]
    else
      'series': [for (final s in series) s.toJson()],
  };

  static SessionDrowsiness? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return SessionDrowsiness(
      scoreTotalPct: (json['scoreTotalPct'] as num?)?.toDouble() ?? 0,
      meanSleepDir: (json['meanSleepDir'] as num?)?.toDouble() ?? 0,
      threshold: (json['threshold'] as num?)?.toDouble(),
      bucketWidthSecs: (json['width'] as num?)?.toDouble() ?? 0,
      series:
          (json['series'] as List<Object?>?)
              ?.map(DrowsinessSample.fromJson)
              .whereType<DrowsinessSample>()
              .toList() ??
          const [],
      buckets:
          (json['buckets'] as List<Object?>?)
              ?.map(DrowsinessSample.fromJson)
              .whereType<DrowsinessSample>()
              .toList() ??
          const [],
    );
  }

  static (List<DrowsinessSample> buckets, double width) decimate(
    List<DrowsinessSample> series, {
    double? trainingStartSecs,
    int bucketCount = 400,
  }) {
    if (series.isEmpty) {
      return (const [], 1.0);
    }
    final start = trainingStartSecs ?? series.first.offsetSecs;
    final end = series.last.offsetSecs;
    final duration = end > start ? end - start : 1.0;
    final width = duration / bucketCount;
    final buckets = <DrowsinessSample>[];
    for (var i = 0; i < bucketCount; i++) {
      final bStart = start + i * width;
      final bEnd = bStart + width;
      final matching = series.where((s) => s.offsetSecs >= bStart && (i == bucketCount - 1 ? s.offsetSecs <= bEnd : s.offsetSecs < bEnd)).toList();
      if (matching.isNotEmpty) {
        final meanSleep = matching.fold<double>(0, (a, s) => a + s.sleepDir) / matching.length;
        final meanDelta = matching.fold<double>(0, (a, s) => a + s.delta) / matching.length;
        final warning = matching.any((s) => s.warning);
        buckets.add(DrowsinessSample(offsetSecs: bStart, sleepDir: meanSleep, delta: meanDelta, warning: warning));
      } else {
        buckets.add(DrowsinessSample(offsetSecs: bStart, sleepDir: 0, delta: 0, warning: false));
      }
    }
    return (buckets, width);
  }
}

class MusicTrackMarker {
  const MusicTrackMarker({required this.offsetSecs, required this.name});

  final double offsetSecs;
  final String name;

  Map<String, Object?> toJson() => {'at': offsetSecs, 'name': name};

  static MusicTrackMarker? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return MusicTrackMarker(
      offsetSecs: (json['at'] as num?)?.toDouble() ?? 0,
      name: (json['name'] as String?) ?? '',
    );
  }
}

class MusicCutoffSample {
  const MusicCutoffSample({required this.offsetSecs, required this.cutoffHz});

  final double offsetSecs;
  final double cutoffHz;

  Map<String, Object?> toJson() => {'at': offsetSecs, 'hz': cutoffHz};

  static MusicCutoffSample? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return MusicCutoffSample(
      offsetSecs: (json['at'] as num?)?.toDouble() ?? 0,
      cutoffHz: (json['hz'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SessionMusic {
  const SessionMusic({
    required this.trackCount,
    required this.minCutoffHz,
    required this.maxCutoffHz,
    required this.invert,
    required this.shuffle,
    this.tracks = const [],
    this.series = const [],
    this.buckets = const [],
    this.bucketWidthSecs = 0,
  });

  final int trackCount;
  final double minCutoffHz;
  final double maxCutoffHz;
  final bool invert;
  final bool shuffle;
  final List<MusicTrackMarker> tracks;
  final List<MusicCutoffSample> series;
  final List<MusicCutoffSample> buckets;
  final double bucketWidthSecs;

  Map<String, Object?> toJson() => {
    'trackCount': trackCount,
    'minCutoffHz': minCutoffHz,
    'maxCutoffHz': maxCutoffHz,
    'invert': invert,
    'shuffle': shuffle,
    if (tracks.isNotEmpty) 'tracks': [for (final t in tracks) t.toJson()],
    if (buckets.isNotEmpty) 'width': bucketWidthSecs,
    if (buckets.isNotEmpty)
      'buckets': [for (final b in buckets) b.toJson()]
    else
      'series': [for (final s in series) s.toJson()],
  };

  static SessionMusic? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return SessionMusic(
      trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
      minCutoffHz: (json['minCutoffHz'] as num?)?.toDouble() ?? 0,
      maxCutoffHz: (json['maxCutoffHz'] as num?)?.toDouble() ?? 0,
      invert: json['invert'] as bool? ?? false,
      shuffle: json['shuffle'] as bool? ?? false,
      tracks:
          (json['tracks'] as List<Object?>?)
              ?.map(MusicTrackMarker.fromJson)
              .whereType<MusicTrackMarker>()
              .toList() ??
          const [],
      bucketWidthSecs: (json['width'] as num?)?.toDouble() ?? 0,
      series:
          (json['series'] as List<Object?>?)
              ?.map(MusicCutoffSample.fromJson)
              .whereType<MusicCutoffSample>()
              .toList() ??
          const [],
      buckets:
          (json['buckets'] as List<Object?>?)
              ?.map(MusicCutoffSample.fromJson)
              .whereType<MusicCutoffSample>()
              .toList() ??
          const [],
    );
  }

  static (List<MusicCutoffSample> buckets, double width) decimate(
    List<MusicCutoffSample> series, {
    double? trainingStartSecs,
    int bucketCount = 400,
  }) {
    if (series.isEmpty) {
      return (const [], 1.0);
    }
    final start = trainingStartSecs ?? series.first.offsetSecs;
    final end = series.last.offsetSecs;
    final duration = end > start ? end - start : 1.0;
    final width = duration / bucketCount;
    final buckets = <MusicCutoffSample>[];
    for (var i = 0; i < bucketCount; i++) {
      final bStart = start + i * width;
      final bEnd = bStart + width;
      final matching = series.where((s) => s.offsetSecs >= bStart && (i == bucketCount - 1 ? s.offsetSecs <= bEnd : s.offsetSecs < bEnd)).toList();
      if (matching.isNotEmpty) {
        final meanHz = matching.fold<double>(0, (a, s) => a + s.cutoffHz) / matching.length;
        buckets.add(MusicCutoffSample(offsetSecs: bStart, cutoffHz: meanHz));
      } else {
        buckets.add(MusicCutoffSample(offsetSecs: bStart, cutoffHz: 0));
      }
    }
    return (buckets, width);
  }
}

class SessionBaselineStats {
  const SessionBaselineStats({
    required this.percentile,
    required this.count,
    this.mean,
    this.stddev,
    this.floor,
    this.ceiling,
  });

  final double percentile;
  final int count;
  final double? mean;
  final double? stddev;
  final double? floor;
  final double? ceiling;

  Map<String, Object?> toJson() => {
    'percentile': percentile,
    'count': count,
    if (mean != null) 'mean': mean,
    if (stddev != null) 'stddev': stddev,
    if (floor != null) 'floor': floor,
    if (ceiling != null) 'ceiling': ceiling,
  };

  static SessionBaselineStats? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return SessionBaselineStats(
      percentile: (json['percentile'] as num?)?.toDouble() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
      mean: (json['mean'] as num?)?.toDouble(),
      stddev: (json['stddev'] as num?)?.toDouble(),
      floor: (json['floor'] as num?)?.toDouble(),
      ceiling: (json['ceiling'] as num?)?.toDouble(),
    );
  }
}

class SessionCalibrationPhase {
  const SessionCalibrationPhase({
    required this.name,
    required this.durationSecs,
    required this.sampleCount,
    this.clipFile,
    this.spokenText,
    this.eyes,
    this.challengeText,
    this.startSecs,
    this.endSecs,
    this.kind,
  });

  final String name;
  final double durationSecs;
  final int sampleCount;
  final String? clipFile;
  final String? spokenText;
  final String? eyes;
  final String? challengeText;
  final double? startSecs;
  final double? endSecs;
  final String? kind;

  Map<String, Object?> toJson() => {
    'name': name,
    'durationSecs': durationSecs,
    'sampleCount': sampleCount,
    if (clipFile != null) 'clipFile': clipFile,
    if (spokenText != null) 'spokenText': spokenText,
    if (eyes != null) 'eyes': eyes,
    if (challengeText != null) 'challengeText': challengeText,
    if (startSecs != null) 'startSecs': startSecs,
    if (endSecs != null) 'endSecs': endSecs,
    if (kind != null) 'kind': kind,
  };

  static SessionCalibrationPhase? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return SessionCalibrationPhase(
      name: json['name'] as String? ?? '',
      durationSecs: (json['durationSecs'] as num?)?.toDouble() ?? 0,
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
      clipFile: json['clipFile'] as String?,
      spokenText: json['spokenText'] as String?,
      eyes: json['eyes'] as String?,
      challengeText: json['challengeText'] as String?,
      startSecs: (json['startSecs'] as num?)?.toDouble(),
      endSecs: (json['endSecs'] as num?)?.toDouble(),
      kind: json['kind'] as String?,
    );
  }
}

class SessionRecalibration {
  const SessionRecalibration({
    required this.atSecs,
    required this.baseline,
  });

  final double atSecs;
  final SessionBaselineStats baseline;

  Map<String, Object?> toJson() => {
    'atSecs': atSecs,
    'baseline': baseline.toJson(),
  };

  static SessionRecalibration? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final baseline = SessionBaselineStats.fromJson(json['baseline']);
    return SessionRecalibration(
      atSecs: (json['atSecs'] as num?)?.toDouble() ?? 0,
      baseline: baseline ?? const SessionBaselineStats(
        percentile: 0,
        count: 0,
      ),
    );
  }
}

class SessionCalibration {
  const SessionCalibration({
    required this.version,
    required this.kind,
    required this.calibrationId,
    this.calibrationJson,
    this.calibrationStartSecs,
    this.calibrationEndSecs,
    this.trainingStartSecs,
    this.usedStartAnyway = false,
    this.greenStableSeconds,
    this.faultyPadSeconds,
    this.baseline,
    this.phases = const [],
    this.recalibrations = const [],
  });

  final int version;
  final String kind;
  final String calibrationId;
  final Map<String, Object?>? calibrationJson;
  final double? calibrationStartSecs;
  final double? calibrationEndSecs;
  final double? trainingStartSecs;
  final bool usedStartAnyway;
  final int? greenStableSeconds;
  final int? faultyPadSeconds;
  final SessionBaselineStats? baseline;
  final List<SessionCalibrationPhase> phases;
  final List<SessionRecalibration> recalibrations;

  double? get trainingStartOffsetSecs {
    final start = calibrationStartSecs;
    final training = trainingStartSecs;
    if (start == null || training == null) {
      return null;
    }
    final offset = training - start;
    return offset.isFinite && offset >= 0 ? offset : null;
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'kind': kind,
    'calibrationId': calibrationId,
    if (calibrationJson != null) 'calibrationJson': calibrationJson,
    if (calibrationStartSecs != null)
      'calibrationStartSecs': calibrationStartSecs,
    if (calibrationEndSecs != null) 'calibrationEndSecs': calibrationEndSecs,
    if (trainingStartSecs != null) 'trainingStartSecs': trainingStartSecs,
    if (usedStartAnyway) 'usedStartAnyway': true,
    if (greenStableSeconds != null) 'greenStableSeconds': greenStableSeconds,
    if (faultyPadSeconds != null) 'faultyPadSeconds': faultyPadSeconds,
    if (baseline != null) 'baseline': baseline!.toJson(),
    if (phases.isNotEmpty) 'phases': [for (final p in phases) p.toJson()],
    if (recalibrations.isNotEmpty)
      'recalibrations': [for (final r in recalibrations) r.toJson()],
  };

  static SessionCalibration? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return SessionCalibration(
      version: (json['version'] as num?)?.toInt() ?? 0,
      kind: json['kind'] as String? ?? '',
      calibrationId: json['calibrationId'] as String? ?? '',
      calibrationJson: json['calibrationJson'] as Map<String, Object?>?,
      calibrationStartSecs: (json['calibrationStartSecs'] as num?)?.toDouble(),
      calibrationEndSecs: (json['calibrationEndSecs'] as num?)?.toDouble(),
      trainingStartSecs: (json['trainingStartSecs'] as num?)?.toDouble(),
      usedStartAnyway: json['usedStartAnyway'] as bool? ?? false,
      greenStableSeconds: (json['greenStableSeconds'] as num?)?.toInt(),
      faultyPadSeconds: (json['faultyPadSeconds'] as num?)?.toInt(),
      baseline: SessionBaselineStats.fromJson(json['baseline']),
      phases:
          (json['phases'] as List<Object?>?)
              ?.map(SessionCalibrationPhase.fromJson)
              .whereType<SessionCalibrationPhase>()
              .toList() ??
          const [],
      recalibrations:
          (json['recalibrations'] as List<Object?>?)
              ?.map(SessionRecalibration.fromJson)
              .whereType<SessionRecalibration>()
              .toList() ??
          const [],
    );
  }
}

class SessionSettings {
  const SessionSettings({
    required this.dynamicAdapt,
    required this.responsiveness,
    required this.baselinePercentile,
    required this.guardrailEnabled,
    required this.guardrailEngine,
    required this.warningThresholdPercentile,
    required this.warningSound,
    required this.musicFolder,
    required this.musicMinCutoffHz,
    required this.musicMaxCutoffHz,
    required this.musicInvert,
    required this.musicShuffle,
    required this.binauralPresetId,
    required this.binauralCarrierHz,
    required this.binauralBeatHz,
    required this.markersInFeedbackEnabled,
    required this.eyeMarkersEnabled,
    this.modelSnapshot,
  });

  final bool dynamicAdapt;
  final double responsiveness;
  final int baselinePercentile;
  final bool guardrailEnabled;
  final String guardrailEngine;
  final int warningThresholdPercentile;
  final String warningSound;
  final String? musicFolder;
  final double musicMinCutoffHz;
  final double musicMaxCutoffHz;
  final bool musicInvert;
  final bool musicShuffle;
  final String binauralPresetId;
  final double binauralCarrierHz;
  final double binauralBeatHz;
  final bool markersInFeedbackEnabled;
  final bool eyeMarkersEnabled;
  final ModelSnapshot? modelSnapshot;

  Map<String, Object?> toJson() => {
    'dynamicAdapt': dynamicAdapt,
    'responsiveness': responsiveness,
    'baselinePercentile': baselinePercentile,
    'guardrailEnabled': guardrailEnabled,
    'guardrailEngine': guardrailEngine,
    'warningThresholdPercentile': warningThresholdPercentile,
    'warningSound': warningSound,
    if (musicFolder != null) 'musicFolder': musicFolder,
    'musicMinCutoffHz': musicMinCutoffHz,
    'musicMaxCutoffHz': musicMaxCutoffHz,
    'musicInvert': musicInvert,
    'musicShuffle': musicShuffle,
    'binauralPresetId': binauralPresetId,
    'binauralCarrierHz': binauralCarrierHz,
    'binauralBeatHz': binauralBeatHz,
    'markersInFeedbackEnabled': markersInFeedbackEnabled,
    'eyeMarkersEnabled': eyeMarkersEnabled,
    if (modelSnapshot != null) 'modelSnapshot': modelSnapshot!.toJson(),
  };

  static SessionSettings? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return SessionSettings(
      dynamicAdapt: json['dynamicAdapt'] as bool? ?? false,
      responsiveness: (json['responsiveness'] as num?)?.toDouble() ?? 0,
      baselinePercentile: (json['baselinePercentile'] as num?)?.toInt() ?? 0,
      guardrailEnabled: json['guardrailEnabled'] as bool? ?? false,
      guardrailEngine: json['guardrailEngine'] as String? ?? 'none',
      warningThresholdPercentile:
          (json['warningThresholdPercentile'] as num?)?.toInt() ?? 0,
      warningSound: json['warningSound'] as String? ?? '',
      musicFolder: json['musicFolder'] as String?,
      musicMinCutoffHz: (json['musicMinCutoffHz'] as num?)?.toDouble() ?? 0,
      musicMaxCutoffHz: (json['musicMaxCutoffHz'] as num?)?.toDouble() ?? 0,
      musicInvert: json['musicInvert'] as bool? ?? false,
      musicShuffle: json['musicShuffle'] as bool? ?? false,
      binauralPresetId: json['binauralPresetId'] as String? ?? '',
      binauralCarrierHz: (json['binauralCarrierHz'] as num?)?.toDouble() ?? 0,
      binauralBeatHz: (json['binauralBeatHz'] as num?)?.toDouble() ?? 0,
      markersInFeedbackEnabled:
          json['markersInFeedbackEnabled'] as bool? ?? false,
      eyeMarkersEnabled: json['eyeMarkersEnabled'] as bool? ?? false,
      modelSnapshot: ModelSnapshot.fromJson(json['modelSnapshot'] as Map<String, dynamic>?),
    );
  }
}

class SessionStatsData {
  const SessionStatsData({
    this.peakAlphaFreq,
    this.peakAlphaPower,
    required this.targetPct,
    required this.stillnessPct,
    this.avgBpm,
    required this.avgAlphaRel,
  });

  final double? peakAlphaFreq;
  final double? peakAlphaPower;
  final double targetPct;
  final double stillnessPct;
  final double? avgBpm;
  final double avgAlphaRel;

  Map<String, Object?> toJson() => {
    'peakAlphaFreq': peakAlphaFreq,
    'peakAlphaPower': peakAlphaPower,
    'targetPct': targetPct,
    'stillnessPct': stillnessPct,
    'avgBpm': avgBpm,
    'avgAlphaRel': avgAlphaRel,
  };

  static SessionStatsData? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return SessionStatsData(
      peakAlphaFreq: (json['peakAlphaFreq'] as num?)?.toDouble(),
      peakAlphaPower: (json['peakAlphaPower'] as num?)?.toDouble(),
      targetPct: (json['targetPct'] as num?)?.toDouble() ?? 0,
      stillnessPct: (json['stillnessPct'] as num?)?.toDouble() ?? 0,
      avgBpm: (json['avgBpm'] as num?)?.toDouble(),
      avgAlphaRel: (json['avgAlphaRel'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SessionMetadata {
  const SessionMetadata({
    required this.protocol,
    required this.durationMinutes,
    required this.elapsedSeconds,
    required this.sound,
    required this.savedAt,
    this.notes = '',
    this.stats,
    this.deviceName,
    this.deviceModel,
    this.deviceId,
    this.recordedChannels = const [],
    this.recordedData = const [],
    this.summary,
    this.gestures = const [],
    this.calibration,
    this.drowsiness,
    this.music,
    this.feedbackSound,
    this.metadataDescription,
    this.sessionSettings,
    this.durationS = 0,
    this.startedAt,
    this.protocolVersion,
    this.calibrationProfile,
    this.avgSpo2,
    this.peakAlphaHz,
    this.peakAlphaPower,
    this.pctInTarget,
    this.avgMovement,
    this.guardrailWarnCount,
    this.avgSleepDir,
    this.signalQualityMean,
    this.pctQcOk,
    this.guardrailEngine,
    this.modelKind,
    this.modelSha256,
    this.feedbackEngine,
    this.userId,
    this.sessionId,
  });

  final ProtocolType protocol;
  final int durationMinutes;
  final int elapsedSeconds;
  final String sound;
  final String savedAt;
  final String notes;
  final SessionStatsData? stats;
  final String? deviceName;
  final String? deviceModel;
  final String? deviceId;
  final List<String> recordedChannels;
  final List<String> recordedData;
  final SessionOverview? summary;
  final List<GestureMarker> gestures;
  final SessionCalibration? calibration;
  final SessionDrowsiness? drowsiness;
  final SessionMusic? music;
  final String? feedbackSound;
  final String? metadataDescription;
  final SessionSettings? sessionSettings;
  final int durationS;
  final String? startedAt;
  final String? protocolVersion;
  final String? calibrationProfile;
  final double? avgSpo2;
  final double? peakAlphaHz;
  final double? peakAlphaPower;
  final double? pctInTarget;
  final double? avgMovement;
  final int? guardrailWarnCount;
  final double? avgSleepDir;
  final double? signalQualityMean;
  final double? pctQcOk;
  final String? guardrailEngine;
  final String? modelKind;
  final String? modelSha256;
  final String? feedbackEngine;
  final String? userId;
  final String? sessionId;

  Map<String, Object?> toJson() => {
    'protocol': protocol.name,
    'durationMinutes': durationMinutes,
    'elapsedSeconds': elapsedSeconds,
    'sound': sound,
    'savedAt': savedAt,
    'notes': notes,
    if (stats != null) 'stats': stats!.toJson(),
    if (deviceName != null) 'deviceName': deviceName,
    if (deviceModel != null) 'deviceModel': deviceModel,
    if (deviceId != null) 'deviceId': deviceId,
    if (recordedChannels.isNotEmpty) 'recordedChannels': recordedChannels,
    if (recordedData.isNotEmpty) 'recordedData': recordedData,
    if (summary != null) 'summary': summary!.toJson(),
    if (gestures.isNotEmpty) 'gestures': [for (final g in gestures) g.toJson()],
    if (calibration != null) 'calibration': calibration!.toJson(),
    if (drowsiness != null) 'drowsiness': drowsiness!.toJson(),
    if (music != null) 'music': music!.toJson(),
    if (feedbackSound != null) 'feedbackSound': feedbackSound,
    if (metadataDescription != null) 'metadataDescription': metadataDescription,
    if (sessionSettings != null) 'sessionSettings': sessionSettings!.toJson(),
    'durationS': durationS,
    if (startedAt != null) 'startedAt': startedAt,
    if (protocolVersion != null) 'protocolVersion': protocolVersion,
    if (calibrationProfile != null) 'calibrationProfile': calibrationProfile,
    if (avgSpo2 != null) 'avgSpo2': avgSpo2,
    if (peakAlphaHz != null) 'peakAlphaHz': peakAlphaHz,
    if (peakAlphaPower != null) 'peakAlphaPower': peakAlphaPower,
    if (pctInTarget != null) 'pctInTarget': pctInTarget,
    if (avgMovement != null) 'avgMovement': avgMovement,
    if (guardrailWarnCount != null) 'guardrailWarnCount': guardrailWarnCount,
    if (avgSleepDir != null) 'avgSleepDir': avgSleepDir,
    if (signalQualityMean != null) 'signalQualityMean': signalQualityMean,
    if (pctQcOk != null) 'pctQcOk': pctQcOk,
    if (guardrailEngine != null) 'guardrailEngine': guardrailEngine,
    if (modelKind != null) 'modelKind': modelKind,
    if (modelSha256 != null) 'modelSha256': modelSha256,
    if (feedbackEngine != null) 'feedbackEngine': feedbackEngine,
    if (userId != null) 'userId': userId,
    if (sessionId != null) 'sessionId': sessionId,
  };

  static SessionMetadata? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final protocolName = json['protocol'] as String?;
    final protocol = ProtocolType.values
        .where((p) => p.name == protocolName)
        .firstOrNull ?? ProtocolType.drowsiness;
    return SessionMetadata(
      protocol: protocol,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
      sound: (json['sound'] as String?) ?? 'Ambient Drone',
      savedAt: (json['savedAt'] as String?) ?? DateTime.now().toIso8601String(),
      notes: (json['notes'] as String?) ?? '',
      stats: SessionStatsData.fromJson(json['stats']),
      deviceName: json['deviceName'] as String?,
      deviceModel: json['deviceModel'] as String?,
      deviceId: json['deviceId'] as String?,
      recordedChannels:
          (json['recordedChannels'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      recordedData:
          (json['recordedData'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      summary: SessionOverview.fromJson(json['summary']),
      gestures:
          (json['gestures'] as List<Object?>?)
              ?.map(GestureMarker.fromJson)
              .whereType<GestureMarker>()
              .toList() ??
          const [],
      calibration: SessionCalibration.fromJson(json['calibration']),
      drowsiness: SessionDrowsiness.fromJson(json['drowsiness']),
      feedbackSound: json['feedbackSound'] as String?,
      music: SessionMusic.fromJson(json['music']),
      metadataDescription: json['metadataDescription'] as String?,
      sessionSettings: SessionSettings.fromJson(json['sessionSettings']),
      durationS: (json['durationS'] as num?)?.toInt() ?? 0,
      startedAt: json['startedAt'] as String?,
      protocolVersion: json['protocolVersion'] as String?,
      calibrationProfile: json['calibrationProfile'] as String?,
      avgSpo2: (json['avgSpo2'] as num?)?.toDouble(),
      peakAlphaHz: (json['peakAlphaHz'] as num?)?.toDouble(),
      peakAlphaPower: (json['peakAlphaPower'] as num?)?.toDouble(),
      pctInTarget: (json['pctInTarget'] as num?)?.toDouble(),
      avgMovement: (json['avgMovement'] as num?)?.toDouble(),
      guardrailWarnCount: (json['guardrailWarnCount'] as num?)?.toInt(),
      avgSleepDir: (json['avgSleepDir'] as num?)?.toDouble(),
      signalQualityMean: (json['signalQualityMean'] as num?)?.toDouble(),
      pctQcOk: (json['pctQcOk'] as num?)?.toDouble(),
      guardrailEngine: json['guardrailEngine'] as String?,
      modelKind: json['modelKind'] as String?,
      modelSha256: json['modelSha256'] as String?,
      feedbackEngine: json['feedbackEngine'] as String?,
      userId: json['userId'] as String?,
      sessionId: json['sessionId'] as String?,
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
