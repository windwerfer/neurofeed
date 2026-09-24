import 'dart:convert';

import 'package:neurofeed/src/session_format/models.dart';
import 'package:neurofeed/src/util/timezone.dart';

enum GestureType { doubleBlink, doubleClench, eyeUp, eyeDown }

/// Root `annotations[]` row (v6). Interval types use duration > 0; gestures use 0.
class SessionAnnotation {
  const SessionAnnotation({
    required this.onset,
    required this.duration,
    required this.type,
  });

  final double onset;
  final double duration;
  final String type;

  Map<String, Object?> toJson() => {
    'onset': onset,
    'duration': duration,
    'type': type,
  };

  static SessionAnnotation? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['type'] as String?;
    if (type == null || type.isEmpty) return null;
    return SessionAnnotation(
      onset: (json['onset'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      type: type,
    );
  }
}

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
  });

  final double scoreTotalPct;
  final double meanSleepDir;
  final double? threshold;

  Map<String, Object?> toJson() => {
    'scoreTotalPct': scoreTotalPct,
    'meanSleepDir': meanSleepDir,
    if (threshold != null) 'threshold': threshold,
  };

  static SessionDrowsiness? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return SessionDrowsiness(
      scoreTotalPct: (json['scoreTotalPct'] as num?)?.toDouble() ?? 0,
      meanSleepDir: (json['meanSleepDir'] as num?)?.toDouble() ?? 0,
      threshold: (json['threshold'] as num?)?.toDouble(),
    );
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
  });

  final int trackCount;
  final double minCutoffHz;
  final double maxCutoffHz;
  final bool invert;
  final bool shuffle;
  final List<MusicTrackMarker> tracks;
  final List<MusicCutoffSample> series;

  Map<String, Object?> toJson() => {
    'trackCount': trackCount,
    'minCutoffHz': minCutoffHz,
    'maxCutoffHz': maxCutoffHz,
    'invert': invert,
    'shuffle': shuffle,
    if (tracks.isNotEmpty) 'tracks': [for (final t in tracks) t.toJson()],
    if (series.isNotEmpty) 'series': [for (final s in series) s.toJson()],
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
      series:
          (json['series'] as List<Object?>?)
              ?.map(MusicCutoffSample.fromJson)
              .whereType<MusicCutoffSample>()
              .toList() ??
          const [],
    );
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
    this.baselineSamples = const [],
  });

  final double atSecs;
  final SessionBaselineStats baseline;
  final List<double> baselineSamples;

  Map<String, Object?> toJson() => {
    'atSecs': atSecs,
    'baseline': baseline.toJson(),
    if (baselineSamples.isNotEmpty) 'baselineSamples': baselineSamples,
  };

  static SessionRecalibration? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final baseline = SessionBaselineStats.fromJson(json['baseline']);
    return SessionRecalibration(
      atSecs: (json['atSecs'] as num?)?.toDouble() ?? 0,
      baseline: baseline ?? const SessionBaselineStats(percentile: 0, count: 0),
      baselineSamples:
          (json['baselineSamples'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
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
    this.baselineSamples = const [],
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
  /// Raw native reward samples used by percentileOf after calibration.
  final List<double> baselineSamples;

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
    if (baselineSamples.isNotEmpty) 'baselineSamples': baselineSamples,
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
      baselineSamples:
          (json['baselineSamples'] as List?)
              ?.map((e) => (e as num).toDouble())
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
    required this.backgroundBinauralPresetId,
    required this.backgroundBinauralCarrierHz,
    required this.backgroundBinauralBeatHz,
    required this.markersInFeedbackEnabled,
    required this.eyeMarkersEnabled,
    this.modelSnapshot,
    this.guardFeature,
    this.guardModel,
    this.inhibitCeilingOverrides,
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
  final String backgroundBinauralPresetId;
  final double backgroundBinauralCarrierHz;
  final double backgroundBinauralBeatHz;
  final bool markersInFeedbackEnabled;
  final bool eyeMarkersEnabled;
  final ModelSnapshot? modelSnapshot;

  /// `band.delta` / `ai.drowsiness` / `none`. Preferred over parsing
  /// [guardrailEngine] when present.
  final String? guardFeature;

  /// `cbramod_a_vig` / `reve_base`.
  final String? guardModel;

  /// Settings slider overlays (`beta` / `delta`); omit when empty.
  final Map<String, double>? inhibitCeilingOverrides;

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
    'backgroundBinauralPresetId': backgroundBinauralPresetId,
    'backgroundBinauralCarrierHz': backgroundBinauralCarrierHz,
    'backgroundBinauralBeatHz': backgroundBinauralBeatHz,
    'markersInFeedbackEnabled': markersInFeedbackEnabled,
    'eyeMarkersEnabled': eyeMarkersEnabled,
    if (modelSnapshot != null) 'modelSnapshot': modelSnapshot!.toJson(),
    if (guardFeature != null) 'guardFeature': guardFeature,
    if (guardModel != null) 'guardModel': guardModel,
    if (inhibitCeilingOverrides != null && inhibitCeilingOverrides!.isNotEmpty)
      'inhibitCeilingOverrides': inhibitCeilingOverrides,
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
      backgroundBinauralPresetId:
          json['backgroundBinauralPresetId'] as String? ?? '',
      backgroundBinauralCarrierHz:
          (json['backgroundBinauralCarrierHz'] as num?)?.toDouble() ?? 0,
      backgroundBinauralBeatHz:
          (json['backgroundBinauralBeatHz'] as num?)?.toDouble() ?? 0,
      markersInFeedbackEnabled:
          json['markersInFeedbackEnabled'] as bool? ?? false,
      eyeMarkersEnabled: json['eyeMarkersEnabled'] as bool? ?? false,
      modelSnapshot: ModelSnapshot.fromJson(
        json['modelSnapshot'] as Map<String, dynamic>?,
      ),
      guardFeature: json['guardFeature'] as String?,
      guardModel: json['guardModel'] as String?,
      inhibitCeilingOverrides: () {
        final raw = json['inhibitCeilingOverrides'];
        if (raw is! Map) return null;
        final out = <String, double>{};
        for (final e in raw.entries) {
          if (e.value is num) out[e.key.toString()] = (e.value as num).toDouble();
        }
        return out.isEmpty ? null : out;
      }(),
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
    this.gestures = const [],
    this.calibration,
    this.drowsiness,
    this.music,
    this.feedbackSound,
    this.metadataDescription,
    this.sessionSettings,
    this.durationS = 0,
    this.startedAt,
    this.timeZone,
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
    this.protocolJson,
    this.annotations = const [],
    this.audioEvents = const [],
  });

  final String protocol;
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
  final List<GestureMarker> gestures;
  final SessionCalibration? calibration;
  final SessionDrowsiness? drowsiness;
  final SessionMusic? music;
  final String? feedbackSound;
  final String? metadataDescription;
  final SessionSettings? sessionSettings;
  final int durationS;
  final String? startedAt;
  /// IANA id at session start (e.g. `Asia/Bangkok`).
  final String? timeZone;
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

  /// Snapshot of the resolved protocol document at save time.
  final Map<String, Object?>? protocolJson;

  /// Root annotations timeline (pause / bad_quality / disconnect / gestures).
  final List<SessionAnnotation> annotations;

  /// Sparse feedback one-shot chimes (`reward_chime` / `guard_chime`).
  final List<Map<String, Object?>> audioEvents;

  Map<String, Object?> toJson() => {
    'protocol': protocol,
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
    if (gestures.isNotEmpty) 'gestures': [for (final g in gestures) g.toJson()],
    if (calibration != null) 'calibration': calibration!.toJson(),
    if (drowsiness != null) 'drowsiness': drowsiness!.toJson(),
    if (music != null) 'music': music!.toJson(),
    if (feedbackSound != null) 'feedbackSound': feedbackSound,
    if (metadataDescription != null) 'metadataDescription': metadataDescription,
    if (sessionSettings != null) 'sessionSettings': sessionSettings!.toJson(),
    'durationS': durationS,
    if (startedAt != null) 'startedAt': startedAt,
    if (timeZone != null) 'timeZone': timeZone,
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
    if (protocolJson != null) 'protocolJson': protocolJson,
    if (annotations.isNotEmpty)
      'annotations': [for (final a in annotations) a.toJson()],
  };

  static SessionMetadata? fromJson(Object? json) {
    final root = _asStringKeyedMap(json);
    if (root == null) {
      return null;
    }
    final feedback = root['feedback'];
    if (feedback is Map) {
      // v6 file dialect: nested feedback{} only (History / export / assemble).
      return _fromV6Nested(root, _asStringKeyedMap(feedback)!);
    }
    // In-memory / unit-test flat model shape (not a dual file dialect).
    return _fromFlatModel(root);
  }

  static SessionMetadata _fromV6Nested(
    Map<String, Object?> root,
    Map<String, Object?> fb,
  ) {
    final device = _asStringKeyedMap(root['device']);
    final subject = _asStringKeyedMap(root['subject']);
    final outcome = _asStringKeyedMap(fb['outcomeScalars']) ?? const {};
    final recordedChannels = () {
      final labels = device?['channelLabels'];
      if (labels is List) {
        return labels.whereType<String>().toList();
      }
      return const <String>[];
    }();
    final recordedData = _enabledStreamNames(root['streams']);
    final subjectId = subject?['id'] as String?;
    return SessionMetadata(
      protocol: fb['protocol'] as String? ?? '',
      durationMinutes: (fb['durationMinutes'] as num?)?.toInt() ?? 0,
      elapsedSeconds: (root['elapsedSeconds'] as num?)?.toInt() ?? 0,
      sound: (fb['sound'] as String?) ?? 'Ambient Drone',
      savedAt: (root['savedAt'] as String?) ??
          formatIso8601WithOffset(DateTime.now()),
      notes: (root['notes'] as String?) ?? '',
      stats: SessionStatsData.fromJson(root['stats']),
      deviceName: device?['name'] as String?,
      deviceModel: (device?['model'] as String?) ??
          (device?['firmware'] as String?),
      deviceId: device?['id'] as String?,
      recordedChannels: recordedChannels,
      recordedData: recordedData,
      gestures: const [],
      calibration: SessionCalibration.fromJson(fb['calibration']),
      drowsiness: null,
      feedbackSound: fb['feedbackSound'] as String?,
      music: SessionMusic.fromJson(fb['music']),
      metadataDescription: fb['metadataDescription'] as String?,
      sessionSettings: SessionSettings.fromJson(fb['sessionSettings']),
      durationS: (root['durationS'] as num?)?.toInt() ?? 0,
      startedAt: root['startedAt'] as String?,
      timeZone: root['timeZone'] as String?,
      protocolVersion: _protocolVersionFromJson(fb['protocolVersion']),
      calibrationProfile: fb['calibrationProfile'] as String?,
      avgSpo2: (root['avgSpo2'] as num?)?.toDouble(),
      peakAlphaHz: (root['peakAlphaHz'] as num?)?.toDouble(),
      peakAlphaPower: (root['peakAlphaPower'] as num?)?.toDouble(),
      pctInTarget: (outcome['pctInTarget'] as num?)?.toDouble() ??
          (fb['pctInTarget'] as num?)?.toDouble(),
      avgMovement: (root['avgMovement'] as num?)?.toDouble(),
      guardrailWarnCount: (outcome['guardrailWarnCount'] as num?)?.toInt(),
      avgSleepDir: (outcome['avgSleepDir'] as num?)?.toDouble(),
      signalQualityMean: (root['signalQualityMean'] as num?)?.toDouble(),
      pctQcOk: (root['pctQcOk'] as num?)?.toDouble(),
      guardrailEngine: root['guardrailEngine'] as String?,
      modelKind: root['modelKind'] as String?,
      modelSha256: root['modelSha256'] as String?,
      feedbackEngine: root['feedbackEngine'] as String?,
      userId: subjectId ?? root['userId'] as String?,
      sessionId: root['sessionId'] as String?,
      protocolJson: fb['protocolJson'] is Map
          ? Map<String, Object?>.from(fb['protocolJson'] as Map)
          : null,
      annotations:
          (root['annotations'] as List<Object?>?)
              ?.map(SessionAnnotation.fromJson)
              .whereType<SessionAnnotation>()
              .toList() ??
          const [],
      audioEvents: _audioEventsFromJson(fb['audioEvents']),
    );
  }

  static SessionMetadata _fromFlatModel(Map<String, Object?> json) {
    return SessionMetadata(
      protocol: json['protocol'] as String? ?? '',
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
      sound: (json['sound'] as String?) ?? 'Ambient Drone',
      savedAt: (json['savedAt'] as String?) ??
          formatIso8601WithOffset(DateTime.now()),
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
      timeZone: json['timeZone'] as String?,
      protocolVersion: _protocolVersionFromJson(json['protocolVersion']),
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
      protocolJson: json['protocolJson'] is Map
          ? Map<String, Object?>.from(json['protocolJson'] as Map)
          : null,
      annotations:
          (json['annotations'] as List<Object?>?)
              ?.map(SessionAnnotation.fromJson)
              .whereType<SessionAnnotation>()
              .toList() ??
          const [],
      audioEvents: _audioEventsFromJson(json['audioEvents']),
    );
  }

  /// Overlay notes / stats / savedAt onto this snapshot for a Save rewrite.
  SessionMetadata withSaveFields({
    required String notes,
    SessionStatsData? stats,
    double? avgSpo2,
  }) {
    final json = Map<String, Object?>.from(toJson());
    json['notes'] = notes;
    json['savedAt'] = formatIso8601WithOffset(DateTime.now());
    if (stats != null) {
      json['stats'] = stats.toJson();
      json['peakAlphaHz'] = stats.peakAlphaFreq;
      json['peakAlphaPower'] = stats.peakAlphaPower;
      json['pctInTarget'] = stats.targetPct;
    }
    if (avgSpo2 != null) {
      json['avgSpo2'] = avgSpo2;
    }
    return SessionMetadata.fromJson(json)!;
  }

  /// Parse metadata JSON bytes from a container head (`jsonDecode` maps are
  /// `Map<String, dynamic>`; [fromJson] expects `Map<String, Object?>`).
  static SessionMetadata? fromJsonBytes(List<int> bytes) {
    if (bytes.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      return fromJson(_coerceJson(decoded));
    } catch (_) {
      return null;
    }
  }
}


Map<String, Object?>? _asStringKeyedMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final e in value.entries) e.key.toString(): e.value,
    };
  }
  return null;
}

List<String> _enabledStreamNames(Object? streams) {
  final map = _asStringKeyedMap(streams);
  if (map == null) {
    return const [];
  }
  final out = <String>[];
  for (final e in map.entries) {
    final v = e.value;
    if (v is Map && v['enabled'] == true) {
      out.add(e.key);
    }
  }
  return out;
}

List<Map<String, Object?>> _audioEventsFromJson(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  return [
    for (final e in raw)
      if (e is Map) Map<String, Object?>.from(e),
  ];
}

String? _protocolVersionFromJson(Object? value) {
  if (value is String) return value;
  if (value is num) return value.toString();
  return null;
}

Object? _coerceJson(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final e in value.entries) e.key.toString(): _coerceJson(e.value),
    };
  }
  if (value is List) {
    return [for (final v in value) _coerceJson(v)];
  }
  return value;
}

/// Summary of a session or recording for the History list.
class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.metadata,
    this.kind = 'feedback',
    this.path,
  });

  final String id;
  final SessionMetadata metadata;

  /// `feedback` or `recording`. Sqlite column; default `feedback`.
  final String kind;

  /// History-root filename from sqlite (`session_$id.neurofeed` or
  /// `recording_$id.neurofeed`). Null on summaries that never hit sqlite.
  final String? path;

  bool get isRecording => kind == 'recording';

  Map<String, Object?> toJson() => {
    'id': id,
    'metadata': metadata.toJson(),
    'kind': kind,
    if (path != null) 'path': path,
  };

  static SessionSummary? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return SessionSummary(
      id: json['id'] as String? ?? '',
      metadata: SessionMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>?,
      )!,
      kind: json['kind'] as String? ?? 'feedback',
      path: json['path'] as String?,
    );
  }
}
