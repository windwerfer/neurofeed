import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_cache.dart';
import 'package:muse_ml/src/feedback/session_container.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/feedback/session_summary.dart';
import 'package:muse_ml/src/settings.dart';

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
    'minHz': minCutoffHz,
    'maxHz': maxCutoffHz,
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
      minCutoffHz: (json['minHz'] as num?)?.toDouble() ?? 0,
      maxCutoffHz: (json['maxHz'] as num?)?.toDouble() ?? 0,
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

/// Snapshot of the session-affecting settings at save time: target settings,
/// guardrail engine/method, warning sound, music and binaural options, and
/// gesture-marker recording. Records how the session was configured so a
/// saved file stays interpretable without the live prefs.
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
  });

  final ProtocolType protocol;
  final int durationMinutes;
  final int elapsedSeconds;
  final String sound;
  final DateTime savedAt;
  final String notes;
  final SessionStatsData? stats;

  /// Device display name (e.g. the BLE name) the session was recorded with.
  final String? deviceName;

  /// Device model/firmware tag (e.g. "Classic" or "Athena").
  final String? deviceModel;

  /// Stable device identifier.
  final String? deviceId;

  /// Electrode labels present in the file (e.g. `['TP9','AF7','AF8','TP10']`).
  /// A future 8-electrode device records 8 labels here; the format is
  /// channel-agnostic so older readers still parse the frame body.
  final List<String> recordedChannels;

  /// Streams persisted in this file (subset of [RecordingStream] names),
  /// e.g. `['eeg','bands','pps','pulse','imu']`. Empty/absent on old files
  /// means "all".
  final List<String> recordedData;

  /// Decimated overview (bands/pulse/movement/peak) for fast history browsing.
  /// Null on old files.
  final SessionOverview? summary;

  /// Gesture markers (double blink / double clench / eye) recorded during the
  /// session. Computed data — stored in metadata, not the frame body.
  final List<GestureMarker> gestures;

  /// How the session calibrated (timeline, gate, baseline stats, clips)
  /// when recorded. Null on files recorded before calibration recording.
  final SessionCalibration? calibration;

  /// Sleep-guardrail trace (per-second model scores + drift score), when the
  /// session ran with the guardrail enabled. Null otherwise.
  final SessionDrowsiness? drowsiness;

  /// Music feedback record (tracks + cutoff trace), when the session ran in
  /// music-feedback mode. Null otherwise.
  final SessionMusic? music;

  /// Feedback layer the session ran with (`bowlChimes` / `rain` / `music` /
  /// `none`), when the file recorded it. Null on legacy files.
  final String? feedbackSound;

  /// Scientific description of what the protocol trains and how, copied from
  /// `assets/protocols.json` (`metadataDescription`) at save time.
  final String? metadataDescription;

  /// Snapshot of the session-affecting settings (target, guardrail engine,
  /// music/binaural options) at save time. Null on legacy files.
  final SessionSettings? sessionSettings;

  Map<String, Object?> toJson() => {
    'protocol': protocol.name,
    'durationMinutes': durationMinutes,
    'elapsedSeconds': elapsedSeconds,
    'sound': sound,
    'savedAt': savedAt.toIso8601String(),
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
    if (metadataDescription != null)
      'metadataDescription': metadataDescription,
    if (sessionSettings != null) 'sessionSettings': sessionSettings!.toJson(),
  };

  static SessionMetadata? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final protocolName = json['protocol'] as String?;
    final protocol = ProtocolType.values
        .where((p) => p.name == protocolName)
        .firstOrNull;
    if (protocol == null) {
      return null;
    }
    return SessionMetadata(
      protocol: protocol,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
      sound: (json['sound'] as String?) ?? 'Ambient Drone',
      savedAt:
          DateTime.tryParse((json['savedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
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
    );
  }
}

class SessionSummary {
  const SessionSummary({required this.id, required this.metadata});

  final String id;
  final SessionMetadata metadata;
}

class SessionStore {
  SessionStore({Future<SessionStorage>? storage, SessionCache? cache})
    : _storage = storage ?? _defaultStorage(),
      _cache = cache ?? SessionCache.noop();

  final Future<SessionStorage> _storage;
  final SessionCache _cache;

  /// Files (name + id + mtime) discovered by [list] that are missing from the
  /// cache or have changed since it was written. Backfilled in the background
  /// so the first history open stays fluid.
  List<({String name, String id, int mtimeMs})> _pendingBackfill = [];

  bool _backfillRunning = false;

  /// Number of sessions awaiting background backfill after the last [list].
  int get pendingBackfillCount => _pendingBackfill.length;

  /// The underlying storage (resolved) — used to place exports.
  Future<SessionStorage> get storage => _storage;

  static Future<SessionStorage> _defaultStorage() async {
    throw UnimplementedError(
      'SessionStore needs an explicit storage; use sessionStoreProvider',
    );
  }

  String _museName(String id) => 'session_$id.muse.feedback';

  /// Namespace for cache rows — a short hash of the storage location so two
  /// history folders never share metadata rows even when ids collide.
  static String storageKeyFor(SessionStorage storage) =>
      sha256.convert(utf8.encode(storage.location)).toString().substring(0, 16);

  Future<List<SessionSummary>> list() async {
    final storage = await _storage;
    debugPrint(
      '[session] list(): storage=${storage.displayName} loc=${storage.location}',
    );
    final files = await storage.listFilesMeta();
    final key = storageKeyFor(storage);
    final ids = <String>[];
    final mtimeById = <String, int>{};
    for (final f in files) {
      if (!f.name.startsWith('session_') || !f.name.endsWith('.muse.feedback')) {
        continue;
      }
      final id = f.name.substring(8, f.name.length - 14);
      ids.add(id);
      mtimeById[id] = f.mtimeMs;
    }

    final rows = await _cache.getRows(ids.toSet(), key);
    final rowById = {for (final r in rows) r.id: r};

    // Deletions apply immediately: drop cache rows whose file is gone.
    final stale = <String>{
      for (final r in rows)
        if (!mtimeById.containsKey(r.id)) r.id,
    };
    if (stale.isNotEmpty) {
      await _cache.remove(stale, key);
      for (final id in stale) {
        await _cache.deleteThumbnail(id);
      }
    }

    // Changed = brand-new files, or files whose mtime no longer matches the
    // cache. New files are excluded from this pass (they appear after the
    // background backfill); mtime-mismatched rows still carry valid metadata
    // (e.g. a session saved since the last open) so they render immediately.
    final changed = <({String name, String id, int mtimeMs})>[];
    final summaries = <SessionSummary>[];
    for (final f in files) {
      if (!f.name.startsWith('session_') || !f.name.endsWith('.muse.feedback')) {
        continue;
      }
      final id = f.name.substring(8, f.name.length - 14);
      final row = rowById[id];
      if (row == null) {
        changed.add((name: f.name, id: id, mtimeMs: f.mtimeMs));
        continue;
      }
      if (row.mtimeMs != f.mtimeMs) {
        changed.add((name: f.name, id: id, mtimeMs: f.mtimeMs));
      }
      summaries.add(
        SessionSummary(id: id, metadata: _metadataFromJson(row.metadataJson, id)),
      );
    }

    _pendingBackfill = changed;
    summaries.sort((a, b) => b.metadata.savedAt.compareTo(a.metadata.savedAt));
    debugPrint(
      '[session] list: found ${summaries.length} cached session(s), '
      '${changed.length} to backfill',
    );
    return summaries;
  }

  /// Background-fill the cache for files [list] found missing or changed.
  /// Clears the pending set; the caller (sessionListProvider) re-reads the
  /// list once this completes so the new sessions appear.
  Future<void> backfillPending() async {
    if (_backfillRunning) {
      return;
    }
    final pending = _pendingBackfill;
    if (pending.isEmpty) {
      return;
    }
    _backfillRunning = true;
    _pendingBackfill = [];
    try {
      final storage = await _storage;
      final key = storageKeyFor(storage);
      await Future.wait(
        pending.map((f) async {
          try {
            final head = await _readHead(storage, f.name);
            if (head != null) {
              final decoded = jsonDecode(
                String.fromCharCodes(head.jsonBytes),
              ) as Map<String, Object?>;
              final metadata = SessionMetadata.fromJson(decoded);
              if (metadata != null) {
                String? thumbPath;
                if (head.pngBytes.isNotEmpty) {
                  await _cache.writeThumbnail(f.id, head.pngBytes);
                  thumbPath = await _cache.thumbnailPath(f.id);
                }
                await _cache.upsert(
                  CachedSession(
                    id: f.id,
                    mtimeMs: f.mtimeMs,
                    savedAtMs: metadata.savedAt.millisecondsSinceEpoch,
                    metadataJson: const JsonEncoder().convert(metadata.toJson()),
                    thumbnailPath: thumbPath,
                  ),
                  key,
                );
                return;
              }
            }
          } catch (e) {
            debugPrint('[session] backfill(${f.id}) failed: $e');
          }
          // Unreadable/corrupt head: cache the fallback with the real mtime so
          // the file stops being re-read on every open (matches the old
          // _fallback behavior for broken files).
          await _cache.upsert(
            CachedSession(
              id: f.id,
              mtimeMs: f.mtimeMs,
              savedAtMs: 0,
              metadataJson: const JsonEncoder().convert(_fallback(f.id).toJson()),
              thumbnailPath: null,
            ),
            key,
          );
        }),
      );
    } finally {
      _backfillRunning = false;
    }
  }

  /// Read the PNG + metadata head of a session container in one prefix read.
  /// Returns null when the file is missing or the head cannot be parsed.
  Future<({Uint8List pngBytes, Uint8List jsonBytes})?> _readHead(
    SessionStorage storage,
    String name,
  ) async {
    final raw = await storage.readPrefix(name, SessionContainer.headReadLimit);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final head = SessionContainer.parseHead(Uint8List.fromList(raw));
    return (pngBytes: head.pngBytes, jsonBytes: head.jsonBytes);
  }

  SessionMetadata _metadataFromJson(String json, String id) {
    try {
      final decoded = jsonDecode(json) as Map<String, Object?>;
      return SessionMetadata.fromJson(decoded) ?? _fallback(id);
    } catch (_) {
      return _fallback(id);
    }
  }

  /// Read the raw .muse frame body for [id], or null if missing.
  Future<List<int>?> readMuse(String id) async {
    final storage = await _storage;
    final name = _museName(id);
    final bytes = await storage.readFile(name);
    debugPrint(
      '[session] readMuse($id): file="$name" '
      'read=${bytes == null ? 'null' : '${bytes.length}B'} '
      'storage=${storage.displayName} loc=${storage.location}',
    );
    if (bytes == null) {
      return null;
    }
    final body = SessionContainer.extractBody(Uint8List.fromList(bytes));
    debugPrint(
      '[session] readMuse($id): extractBody='
      '${body == null ? 'null' : '${body.length}B'}',
    );
    return body;
  }

  /// Read the thumbnail PNG bytes for [id], or null when missing. Cache-first:
  /// a cached thumbnail file is returned without touching the (possibly SAF)
  /// history folder; only a miss reads the container head and fills the cache.
  Future<List<int>?> readPng(String id) async {
    final cached = await _cache.readThumbnail(id);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final storage = await _storage;
    final head = await _readHead(storage, _museName(id));
    if (head == null || head.pngBytes.isEmpty) {
      return null;
    }
    await _cache.writeThumbnail(id, head.pngBytes);
    final key = storageKeyFor(storage);
    final rows = await _cache.getRows({id}, key);
    if (rows.isNotEmpty) {
      await _cache.upsert(
        rows.first.copyWith(thumbnailPath: await _cache.thumbnailPath(id)),
        key,
      );
    }
    return head.pngBytes;
  }

  /// Persist a finished session into the history folder as a single
  /// `.muse.feedback` container: leading PNG thumbnail, then metadata json,
  /// then the raw frame body.
  Future<SessionSummary> publishSession(
    String id,
    List<int> museBytes,
    SessionMetadata metadata, {
    List<int>? pngBytes,
  }) async {
    final storage = await _storage;
    await storage.ensureDir();
    final jsonBytes = const JsonEncoder().convert(metadata.toJson()).codeUnits;
    final container = SessionContainer.encode(
      pngBytes: pngBytes == null ? Uint8List(0) : Uint8List.fromList(pngBytes),
      jsonBytes: Uint8List.fromList(jsonBytes),
      bodyBytes: Uint8List.fromList(museBytes),
    );
    await storage.writeFileAtomic(_museName(id), container);
    final key = storageKeyFor(storage);
    String? thumbPath;
    if (pngBytes != null && pngBytes.isNotEmpty) {
      await _cache.writeThumbnail(id, Uint8List.fromList(pngBytes));
      thumbPath = await _cache.thumbnailPath(id);
    }
    // mtime is 0 ("unknown") on a fresh write: the next reconcile refreshes
    // it from listFilesMeta without re-reading the metadata we already have.
    await _cache.upsert(
      CachedSession(
        id: id,
        mtimeMs: 0,
        savedAtMs: metadata.savedAt.millisecondsSinceEpoch,
        metadataJson: const JsonEncoder().convert(metadata.toJson()),
        thumbnailPath: thumbPath,
      ),
      key,
    );
    debugPrint('[session] written ${_museName(id)} to ${storage.location}');
    return SessionSummary(id: id, metadata: metadata);
  }

  /// Replace the free-text notes of an existing session and rewrite the
  /// container head in place, preserving the thumbnail and the .muse body.
  /// Returns false when the session file is missing or unreadable.
  Future<bool> updateNotes(String id, String notes) async {
    final storage = await _storage;
    final name = _museName(id);
    final bytes = await storage.readFile(name);
    if (bytes == null || bytes.isEmpty) {
      debugPrint('[session] updateNotes($id): file not found ($name)');
      return false;
    }
    final full = Uint8List.fromList(bytes);
    final head = SessionContainer.parseHead(full);
    final decoded =
        jsonDecode(String.fromCharCodes(head.jsonBytes))
            as Map<String, Object?>;
    decoded['notes'] = notes;
    final jsonBytes = Uint8List.fromList(
      const JsonEncoder().convert(decoded).codeUnits,
    );
    final body = SessionContainer.extractBody(full);
    if (body == null) {
      debugPrint('[session] updateNotes($id): body missing ($name)');
      return false;
    }
    final container = SessionContainer.encode(
      pngBytes: head.pngBytes,
      jsonBytes: jsonBytes,
      bodyBytes: body,
    );
    await storage.writeFileAtomic(name, container);
    await _cache.upsert(
      CachedSession(
        id: id,
        mtimeMs: 0,
        savedAtMs: _savedAtMs(decoded),
        metadataJson: const JsonEncoder().convert(decoded),
        thumbnailPath: await _thumbnailPathForCache(id, storage),
      ),
      storageKeyFor(storage),
    );
    debugPrint('[session] updateNotes($id): notes saved ($name)');
    return true;
  }

  int _savedAtMs(Map<String, Object?> decoded) {
    final raw = decoded['savedAt'];
    if (raw is String) {
      final t = DateTime.tryParse(raw);
      if (t != null) {
        return t.millisecondsSinceEpoch;
      }
    }
    return 0;
  }

  Future<String?> _thumbnailPathForCache(
    String id,
    SessionStorage storage,
  ) async {
    final rows = await _cache.getRows({id}, storageKeyFor(storage));
    if (rows.isNotEmpty && rows.first.thumbnailPath != null) {
      return rows.first.thumbnailPath;
    }
    return _cache.thumbnailPath(id);
  }

  /// Delete one session from history (the `.muse.feedback` file). Returns
  /// false when the file was already gone.
  Future<bool> delete(String id) async {
    final storage = await _storage;
    final name = _museName(id);
    final existed = await storage.fileExists(name);
    await storage.deleteFile(name);
    await _cache.remove({id}, storageKeyFor(storage));
    await _cache.deleteThumbnail(id);
    debugPrint('[session] delete($id): ${existed ? 'deleted' : 'missing'} ($name)');
    return existed;
  }

  /// Copy every session in the current storage into [target], then delete the
  /// source copies so the folder change does not duplicate history. Returns the
  /// number of sessions moved (used for folder-change migration).
  Future<int> moveAllTo(SessionStorage target) async {
    final storage = await _storage;
    final names = await storage.listFiles();
    var moved = 0;
    for (final name in names) {
      if (!name.startsWith('session_') || !name.endsWith('.muse.feedback')) {
        continue;
      }
      final bytes = await storage.readFile(name);
      if (bytes == null) {
        continue;
      }
      await target.ensureDir();
      await target.writeFileAtomic(name, bytes);
      await storage.deleteFile(name);
      moved++;
    }
    // Ids survive a folder move verbatim, so carry the cached metadata across
    // to the new storage key. Mtimes will mismatch once and refresh on the
    // first open of the new folder.
    await _cache.moveStorageKey(storageKeyFor(storage), storageKeyFor(target));
    debugPrint('[session] moved $moved session(s)');
    return moved;
  }

  /// Fold a freshly computed [SessionOverview] (from a full-body parse of a
  /// legacy session without an embedded summary) back into the cached
  /// metadata so the next detail-view open fast-paths through the overview.
  /// Cache-only — the container file is never rewritten.
  Future<void> cacheOverview(String id, SessionOverview overview) async {
    final storage = await _storage;
    final key = storageKeyFor(storage);
    final rows = await _cache.getRows({id}, key);
    if (rows.isEmpty) {
      return;
    }
    try {
      final decoded =
          jsonDecode(rows.first.metadataJson) as Map<String, Object?>;
      decoded['summary'] = overview.toJson();
      await _cache.upsert(rows.first.copyWith(
        metadataJson: const JsonEncoder().convert(decoded),
      ), key);
      debugPrint('[session] cacheOverview($id): overview cached');
    } catch (e) {
      debugPrint('[session] cacheOverview($id) failed: $e');
    }
  }

  SessionMetadata _fallback(String id) => SessionMetadata(
    protocol: ProtocolType.drowsiness,
    durationMinutes: 0,
    elapsedSeconds: 0,
    sound: 'Ambient Drone',
    savedAt: DateTime.fromMillisecondsSinceEpoch(int.tryParse(id) ?? 0),
  );
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
    // list is re-read so the newly discovered sessions appear.
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
