import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_cache.dart';
import 'package:muse_ml/src/feedback/session_container.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/feedback/session_metadata.dart';
import 'package:muse_ml/src/feedback/session_v5_models.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:muse_ml/src/feedback/session_store_core.dart';

export 'session_store_core.dart' show SessionStore;

/// Gesture types detected during a feedback session and persisted (computed,
/// not raw) in the session metadata.
enum GestureType { doubleBlink, doubleClench, eyeUp, eyeDown }

/// A single time-stamped gesture marker inside a feedback session.
class GestureMarker {
  const GestureMarker({required this.type, required this.offsetSeconds});

  final GestureType type;

  /// Seconds from session start (matches [FeedbackState.elapsedSeconds]).
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

/// One per-second sleep-guardrail reading taken during a feedback session
/// (computed, not raw — the 1 Hz model score is not part of the .muse body).
class DrowsinessSample {
  const DrowsinessSample({
    required this.offsetSecs,
    required this.sleepDir,
    required this.delta,
    required this.warning,
  });

  /// Seconds from session start (matches [FeedbackState.elapsedSeconds]).
  final double offsetSecs;

  /// Sleep-direction score from the on-device model (higher = more sleep-like).
  final double sleepDir;

  /// Frontal delta relative power of the AF7/AF8 average at that second.
  final double delta;

  /// Whether the guardrail warning was active at that second.
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

/// Sleep-guardrail trace of a feedback session: the decimated [buckets]
/// (≤ [SessionOverview.defaultBucketCount] rows, aligned to the training
/// window like the bands summary) plus a whole-session [scoreTotalPct]
/// (fraction of scored seconds where the warning was active) and
/// [meanSleepDir]. Persisted in the metadata. The full per-second [series] is
/// kept in memory for live views but is not written to the head (a 90-minute
/// session would otherwise add ~5400 rows read on every history listing).
class SessionDrowsiness {
  const SessionDrowsiness({
    required this.scoreTotalPct,
    required this.meanSleepDir,
    this.threshold,
    this.series = const [],
    this.buckets = const [],
    this.bucketWidthSecs = 0,
  });

  /// Percentage of scored seconds (guardrail running, playing) in which the
  /// drift warning was active — 0 = never flagged, 100 = flagged constantly.
  final double scoreTotalPct;

  /// Mean sleep-direction score over the scored seconds.
  final double meanSleepDir;

  /// Baseline sleep-direction percentile threshold the warnings fired
  /// against, for drawing the reference line on the trace.
  final double? threshold;

  /// Full per-second trace (in-memory / live sessions only, not persisted).
  final List<DrowsinessSample> series;

  /// Decimated trace for the history view. Bucket [i] covers
  /// `[i*[bucketWidthSecs], (i+1)*[bucketWidthSecs])` seconds since training
  /// start, matching the bands overview's x-axis. Empty buckets (no scored
  /// second) are omitted, mirroring how `SessionOverview` leaves nulls.
  final List<DrowsinessSample> buckets;

  /// Seconds per bucket in [buckets] (0 when [buckets] is empty).
  final double bucketWidthSecs;

  /// Build the persisted (≤400-row) snapshot from a per-second [series] that
  /// spans `[trainingStartSecs, last]` of the session. [trainingStartSecs] is
  /// the calibration→training boundary offset (drowsiness is only sampled
  /// while playing, i.e. after it).
  ///
  /// Returns `(buckets, width)` — empty bucket list when [series] is empty.
  static (List<DrowsinessSample>, double) decimate(
    List<DrowsinessSample> series, {
    double? trainingStartSecs,
  }) {
    if (series.isEmpty) {
      return (const [], 0);
    }
    final anchor = trainingStartSecs ?? series.first.offsetSecs;
    var last = anchor;
    for (final s in series) {
      if (s.offsetSecs > last) {
        last = s.offsetSecs;
      }
    }
    final span = (last - anchor).clamp(1.0, double.infinity);
    final width = span / SessionOverview.defaultBucketCount;
    final sumSleep = List<double>.filled(SessionOverview.defaultBucketCount, 0);
    final sumDelta = List<double>.filled(SessionOverview.defaultBucketCount, 0);
    final cnt = List<int>.filled(SessionOverview.defaultBucketCount, 0);
    final warnAny = List<bool>.filled(
      SessionOverview.defaultBucketCount,
      false,
    );
    for (final s in series) {
      final t = s.offsetSecs - anchor;
      if (t < 0) {
        continue;
      }
      var idx = (t / width).floor();
      if (idx >= SessionOverview.defaultBucketCount) {
        idx = SessionOverview.defaultBucketCount - 1;
      }
      sumSleep[idx] += s.sleepDir;
      sumDelta[idx] += s.delta;
      cnt[idx]++;
      if (s.warning) {
        warnAny[idx] = true;
      }
    }
    final buckets = <DrowsinessSample>[];
    for (var i = 0; i < SessionOverview.defaultBucketCount; i++) {
      if (cnt[i] == 0) {
        continue;
      }
      buckets.add(
        DrowsinessSample(
          offsetSecs: i * width + width / 2,
          sleepDir: sumSleep[i] / cnt[i],
          delta: sumDelta[i] / cnt[i],
          warning: warnAny[i],
        ),
      );
    }
    return (buckets, width);
  }

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
}

/// One music track played during a feedback session, stamped with the
/// session-relative offset it started at.
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

/// Per-second low-pass cutoff value of the music feedback channel.
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

/// Music feedback record of a session: which tracks played (with offsets) and
/// the low-pass cutoff trace the reward drove. Like [sessionDrowsiness], the
/// full per-second [series] stays in memory while the head persists only the
/// decimated [buckets].
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

  /// Build the persisted (≤400-bucket) snapshot from the per-second [series],
  /// averaged like the bands/drowsiness overview. Returns `(buckets, width)`.
  static (List<MusicCutoffSample>, double) decimate(
    List<MusicCutoffSample> series, {
    double? trainingStartSecs,
  }) {
    if (series.isEmpty) {
      return (const [], 0);
    }
    final anchor = trainingStartSecs ?? series.first.offsetSecs;
    var last = anchor;
    for (final s in series) {
      if (s.offsetSecs > last) {
        last = s.offsetSecs;
      }
    }
    if (last <= anchor) {
      return (
        [
          MusicCutoffSample(
            offsetSecs: anchor,
            cutoffHz: series.first.cutoffHz,
          ),
        ],
        0,
      );
    }
    final span = (last - anchor).clamp(1.0, double.infinity);
    final width = span / SessionOverview.defaultBucketCount;
    final sum = List<double>.filled(SessionOverview.defaultBucketCount, 0);
    final cnt = List<int>.filled(SessionOverview.defaultBucketCount, 0);
    for (final s in series) {
      final t = s.offsetSecs - anchor;
      if (t < 0) {
        continue;
      }
      var idx = (t / width).floor();
      if (idx >= SessionOverview.defaultBucketCount) {
        idx = SessionOverview.defaultBucketCount - 1;
      }
      sum[idx] += s.cutoffHz;
      cnt[idx]++;
    }
    final buckets = <MusicCutoffSample>[];
    for (var i = 0; i < SessionOverview.defaultBucketCount; i++) {
      if (cnt[i] == 0) {
        continue;
      }
      buckets.add(
        MusicCutoffSample(
          offsetSecs: i * width + width / 2,
          cutoffHz: sum[i] / cnt[i],
        ),
      );
    }
    return (buckets, width);
  }

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
      bucketWidthSecs: (json['width'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Mean ± stddev of the ATR baseline used for calibration.
class SessionBaselineStats {
  const SessionBaselineStats({
    required this.percentile,
    required this.count,
    this.mean,
    this.stddev,
  });

  final int percentile;
  final int count;
  final double? mean;
  final double? stddev;

  Map<String, Object?> toJson() => {
    'percentile': percentile,
    'count': count,
    if (mean != null) 'mean': mean,
    if (stddev != null) 'stddev': stddev,
  };

  static SessionBaselineStats? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return SessionBaselineStats(
      percentile: (json['percentile'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
      mean: (json['mean'] as num?)?.toDouble(),
      stddev: (json['stddev'] as num?)?.toDouble(),
    );
  }
}

/// One clip phase that ran during calibration (recorded per-phase, with the
/// clip + spoken text it used so the calibration is reproducible).
class SessionCalibrationPhase {
  const SessionCalibrationPhase({
    required this.clipId,
    required this.clipFile,
    this.spokenText = '',
    this.eyes,
    this.challengeText,
    this.startSecs,
    this.endSecs,
    this.kind = 'intro',
  });

  final String clipId;
  final String clipFile;

  /// Spoken transcript of the clip (placeholder until real recordings exist).
  final String spokenText;

  /// `open`, `closed`, or null when the clip does not instruct an eye state.
  final String? eyes;

  /// The mentally-active challenge shown on screen during this stage (one
  /// picked at random per calibration run), or null for stages without one.
  final String? challengeText;

  /// Start/end of the phase, in seconds from session (recording) start.
  /// The guidance clip plays between the two; the raw EEG in that window is
  /// intentionally present (metadata marks the window) so the file stays a
  /// single contiguous recording.
  final double? startSecs;
  final double? endSecs;

  /// `intro` (random intro of a `single` calibration) or `stage` (a staged
  /// guidance clip). Old files default to `intro`.
  final String kind;

  Map<String, Object?> toJson() => {
    'clipId': clipId,
    'clipFile': clipFile,
    if (spokenText.isNotEmpty) 'spokenText': spokenText,
    if (eyes != null) 'eyes': eyes,
    if (challengeText != null) 'challengeText': challengeText,
    if (startSecs != null) 'startSecs': startSecs,
    if (endSecs != null) 'endSecs': endSecs,
    if (kind != 'intro') 'kind': kind,
  };

  static SessionCalibrationPhase? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return SessionCalibrationPhase(
      clipId: json['clipId'] as String? ?? '',
      clipFile: json['clipFile'] as String? ?? '',
      spokenText: json['spokenText'] as String? ?? '',
      eyes: json['eyes'] as String?,
      challengeText: json['challengeText'] as String?,
      startSecs: (json['startSecs'] as num?)?.toDouble(),
      endSecs: (json['endSecs'] as num?)?.toDouble(),
      kind: json['kind'] as String? ?? 'intro',
    );
  }
}

/// One in-flight recalibration that replaced the session baseline: when it
/// happened (seconds from recording start) and the new baseline statistics.
class SessionRecalibration {
  const SessionRecalibration({
    required this.atSecs,
    required this.baseline,
  });

  /// Seconds from recording (calibration) start to the recalibration event.
  final double atSecs;

  /// The baseline statistics the session threshold was re-anchored to.
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

/// Repro record of how a session's calibration ran: the calibration id and
/// its full definition snapshot, the timeline (calibration start/end,
/// training start) in wall-clock epoch seconds, the signal-gate rejection
/// criteria, the ATR baseline statistics, the per-phase clip timings, and
/// every in-flight recalibration. Persisted in the metadata JSON, not the
/// `.muse` body.
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

  /// Manifest version the calibration sequence was generated from.
  final int version;

  /// Calibration recipe kind that ran: `single` (intro + one silent baseline)
  /// or `staged` (fixed ordered clip/collect steps).
  final String kind;

  /// Id of the calibration that ran (the `calibrations` key in
  /// `assets/calibrations.json`, e.g. `eyes-closed-01`).
  final String calibrationId;

  /// Immutable snapshot of the calibration definition from
  /// `assets/calibrations.json` (name + both variants) at session time, so
  /// the file stays reproducible even if the asset changes later.
  final Map<String, Object?>? calibrationJson;

  /// Wall-clock epoch seconds when calibration began (also recording start).
  final double? calibrationStartSecs;

  /// Wall-clock epoch seconds when the baseline finished.
  final double? calibrationEndSecs;

  /// Wall-clock epoch seconds when training/feedback began. Because the
  /// recorded event timestamps live on the Muse device clock, trimming uses
  /// [trainingStartOffsetSecs] (relative to recording start) instead.
  final double? trainingStartSecs;

  /// Whether the user bypassed the green-stable gate via the faulty-pad
  /// continue-anyway fallback.
  final bool usedStartAnyway;

  /// Rejection-criteria constants applied during calibration.
  final int? greenStableSeconds;
  final int? faultyPadSeconds;

  final SessionBaselineStats? baseline;

  final List<SessionCalibrationPhase> phases;

  /// In-flight recalibrations that re-anchored the threshold mid-session.
  final List<SessionRecalibration> recalibrations;

  /// Seconds from recording (calibration) start to the training boundary, in
  /// wall-clock time. Used to trim displayed/metricted data to the training
  /// portion regardless of device-clock drift.
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

  /// `bandMath`, a model kind name (`lunaBase`/`lunaLarge`/`reveBase`), or
  /// `none` when the guardrail did not run.
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

  /// Snapshot of the guardrail AI model at session time (v5).
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
      modelSnapshot: ModelSnapshot.fromJson(json['modelSnapshot']),
    );
  }
}
/// Storage-backed store that derives its [SessionStorage] from the active
/// [Settings]. Reading [sessionStorageProvider] here keeps history and the
/// recorder on the same folder.
final sessionStoreProvider = FutureProvider<SessionStore>((ref) async {
  final settings = ref.watch(settingsProvider);
  final cache = await ref.watch(sessionCacheProvider.future);
  return SessionStore(storage: resolveSessionStorage(settings), cache: cache);
});

/// Background-loads the session list through the metadata cache.
class SessionListNotifier extends AsyncNotifier<List<SessionSummary>> {
  bool _disposed = false;

  @override
  Future<List<SessionSummary>> build() async {
    ref.onDispose(() => _disposed = true);
    final store = await ref.watch(sessionStoreProvider.future);
    final summaries = await store.list();
    // Lazy loading: the first emission is the already-cached subset (fast).
    // New or changed files are backfilled in the background; once done the
    /// list is re-read so the newly discovered sessions appear.
    if (store.pendingBackfillCount > 0) {
      unawaited(_backfill(store));
    }
    return summaries;
  }

  Future<void> _backfill(SessionStore store) async {
    await store.backfillPending();
    if (!_disposed) {
      ref.invalidateSelf();
    }
  }
}

final sessionListProvider =
    AsyncNotifierProvider<SessionListNotifier, List<SessionSummary>>(
      SessionListNotifier.new,
    );
