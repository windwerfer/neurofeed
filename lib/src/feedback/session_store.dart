import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
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
    this.startSecs,
    this.endSecs,
  });

  final String clipId;
  final String clipFile;

  /// Spoken transcript of the clip (placeholder until real recordings exist).
  final String spokenText;

  /// `open`, `closed`, or null when the clip does not instruct an eye state.
  final String? eyes;

  /// Start/end of the phase, in seconds from session (recording) start.
  final double? startSecs;
  final double? endSecs;

  Map<String, Object?> toJson() => {
    'clipId': clipId,
    'clipFile': clipFile,
    if (spokenText.isNotEmpty) 'spokenText': spokenText,
    if (eyes != null) 'eyes': eyes,
    if (startSecs != null) 'startSecs': startSecs,
    if (endSecs != null) 'endSecs': endSecs,
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
      startSecs: (json['startSecs'] as num?)?.toDouble(),
      endSecs: (json['endSecs'] as num?)?.toDouble(),
    );
  }
}

/// Repro record of how a session's calibration ran: its timeline
/// (calibration start/end, training start) in wall-clock epoch seconds, the
/// signal-gate rejection criteria, the ATR baseline statistics, and the per-
/// phase clip timings. Persisted in the metadata JSON, not the `.muse` body.
class SessionCalibration {
  const SessionCalibration({
    required this.version,
    this.calibrationStartSecs,
    this.calibrationEndSecs,
    this.trainingStartSecs,
    this.usedStartAnyway = false,
    this.greenStableSeconds,
    this.faultyPadSeconds,
    this.baseline,
    this.phases = const [],
  });

  /// Manifest version the calibration sequence was generated from.
  final int version;

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
    if (calibrationStartSecs != null)
      'calibrationStartSecs': calibrationStartSecs,
    if (calibrationEndSecs != null) 'calibrationEndSecs': calibrationEndSecs,
    if (trainingStartSecs != null) 'trainingStartSecs': trainingStartSecs,
    if (usedStartAnyway) 'usedStartAnyway': true,
    if (greenStableSeconds != null) 'greenStableSeconds': greenStableSeconds,
    if (faultyPadSeconds != null) 'faultyPadSeconds': faultyPadSeconds,
    if (baseline != null) 'baseline': baseline!.toJson(),
    if (phases.isNotEmpty) 'phases': [for (final p in phases) p.toJson()],
  };

  static SessionCalibration? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    return SessionCalibration(
      version: (json['version'] as num?)?.toInt() ?? 0,
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
    );
  }
}

class SessionSummary {
  const SessionSummary({required this.id, required this.metadata});

  final String id;
  final SessionMetadata metadata;
}

class SessionStore {
  SessionStore({Future<SessionStorage>? storage})
    : _storage = storage ?? _defaultStorage();

  final Future<SessionStorage> _storage;

  static Future<SessionStorage> _defaultStorage() async {
    throw UnimplementedError(
      'SessionStore needs an explicit storage; use sessionStoreProvider',
    );
  }

  String _museName(String id) => 'session_$id.muse.feedback';

  Future<List<SessionSummary>> list() async {
    final storage = await _storage;
    debugPrint(
      '[session] list(): storage=${storage.displayName} loc=${storage.location}',
    );
    final names = await storage.listFiles();
    final summaries = <SessionSummary>[];
    for (final name in names) {
      if (!name.startsWith('session_') || !name.endsWith('.muse.feedback')) {
        continue;
      }
      final id = name.substring(8, name.length - 14);
      final metadata = await _readMetadata(storage, name, id);
      summaries.add(SessionSummary(id: id, metadata: metadata));
    }
    summaries.sort((a, b) => b.metadata.savedAt.compareTo(a.metadata.savedAt));
    debugPrint('[session] list: found ${summaries.length} session(s)');
    return summaries;
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

  /// Read the thumbnail PNG bytes for [id], or null when missing.
  Future<List<int>?> readPng(String id) async {
    final storage = await _storage;
    final bytes = await storage.readPrefix(
      _museName(id),
      SessionContainer.headReadLimit,
    );
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    try {
      return SessionContainer.parseHead(Uint8List.fromList(bytes)).pngBytes;
    } catch (_) {
      return null;
    }
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
    debugPrint('[session] updateNotes($id): notes saved ($name)');
    return true;
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
    debugPrint('[session] moved $moved session(s)');
    return moved;
  }

  Future<SessionMetadata> _readMetadata(
    SessionStorage storage,
    String name,
    String id,
  ) async {
    try {
      final raw = await storage.readPrefix(
        name,
        SessionContainer.headReadLimit,
      );
      if (raw == null || raw.isEmpty) {
        return _fallback(id);
      }
      final head = SessionContainer.parseHead(Uint8List.fromList(raw));
      final decoded = jsonDecode(String.fromCharCodes(head.jsonBytes));
      return SessionMetadata.fromJson(decoded as Map<String, Object?>) ??
          _fallback(id);
    } catch (_) {
      return _fallback(id);
    }
  }

  SessionMetadata _fallback(String id) => SessionMetadata(
    protocol: ProtocolType.alphaTheta,
    durationMinutes: 0,
    elapsedSeconds: 0,
    sound: 'Ambient Drone',
    savedAt: DateTime.fromMillisecondsSinceEpoch(int.tryParse(id) ?? 0),
  );
}

/// Storage-backed store that derives its [SessionStorage] from the active
/// [Settings]. Reading [sessionStorageProvider] here keeps history and the
/// recorder on the same folder.
final sessionStoreProvider = FutureProvider<SessionStore>((ref) {
  final settings = ref.watch(settingsProvider);
  return SessionStore(storage: resolveSessionStorage(settings));
});

final sessionListProvider = FutureProvider<List<SessionSummary>>((ref) async {
  final store = await ref.watch(sessionStoreProvider.future);
  return store.list();
});
