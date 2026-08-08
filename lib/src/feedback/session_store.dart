import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_container.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/settings.dart';

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
  /// e.g. `['eeg','bands','ppg']`. Empty/absent on old files means "all".
  final List<String> recordedData;

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
      savedAt: DateTime.tryParse((json['savedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      notes: (json['notes'] as String?) ?? '',
      stats: SessionStatsData.fromJson(json['stats']),
      deviceName: json['deviceName'] as String?,
      deviceModel: json['deviceModel'] as String?,
      deviceId: json['deviceId'] as String?,
      recordedChannels: (json['recordedChannels'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      recordedData: (json['recordedData'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const [],
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
        '[session] list(): storage=${storage.displayName} loc=${storage.location}');
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
    summaries.sort(
      (a, b) => b.metadata.savedAt.compareTo(a.metadata.savedAt),
    );
    debugPrint('[session] list: found ${summaries.length} session(s)');
    return summaries;
  }

  /// Read the raw .muse frame body for [id], or null if missing.
  Future<List<int>?> readMuse(String id) async {
    final storage = await _storage;
    final name = _museName(id);
    final bytes = await storage.readFile(name);
    debugPrint('[session] readMuse($id): file="$name" '
        'read=${bytes == null ? 'null' : '${bytes.length}B'} '
        'storage=${storage.displayName} loc=${storage.location}');
    if (bytes == null) {
      return null;
    }
    final body = SessionContainer.extractBody(Uint8List.fromList(bytes));
    debugPrint('[session] readMuse($id): extractBody='
        '${body == null ? 'null' : '${body.length}B'}');
    return body;
  }

  /// Read the thumbnail PNG bytes for [id], or null when missing.
  Future<List<int>?> readPng(String id) async {
    final storage = await _storage;
    final bytes =
        await storage.readPrefix(_museName(id), SessionContainer.headReadLimit);
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
    await storage.writeFile(_museName(id), container);
    debugPrint('[session] written ${_museName(id)} to ${storage.location}');
    return SessionSummary(id: id, metadata: metadata);
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
      await target.writeFile(name, bytes);
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
      final raw =
          await storage.readPrefix(name, SessionContainer.headReadLimit);
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
