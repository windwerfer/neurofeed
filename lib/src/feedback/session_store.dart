import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:path_provider/path_provider.dart';

/// Resolves the persistent session storage directory.
///
/// On Android/iOS this is under the app's documents directory so saved
/// sessions survive process restarts. `Directory.systemTemp` maps to the app
/// cache directory on mobile, which the OS may clear — that would silently
/// wipe saved sessions. Desktop falls back to the system temp directory.
Future<Directory> defaultSessionDir() async {
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/muse_ml_sessions');
      debugPrint('[session] storage dir: ${dir.path}');
      return dir;
    } catch (e) {
      debugPrint('[session] documents dir unavailable ($e), using systemTemp');
    }
  }
  return Directory('${Directory.systemTemp.path}/muse_ml_sessions');
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
  });

  final ProtocolType protocol;
  final int durationMinutes;
  final int elapsedSeconds;
  final String sound;
  final DateTime savedAt;
  final String notes;
  final SessionStatsData? stats;

  Map<String, Object?> toJson() => {
    'protocol': protocol.name,
    'durationMinutes': durationMinutes,
    'elapsedSeconds': elapsedSeconds,
    'sound': sound,
    'savedAt': savedAt.toIso8601String(),
    'notes': notes,
    if (stats != null) 'stats': stats!.toJson(),
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
    );
  }
}

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.metadata,
    required this.musePath,
    this.pngPath,
  });

  final String id;
  final SessionMetadata metadata;
  final String musePath;
  final String? pngPath;
}

class SessionStore {
  SessionStore({Future<Directory>? dir}) : _dir = dir ?? defaultSessionDir();

  final Future<Directory> _dir;

  Future<List<SessionSummary>> list() async {
    final dir = await _dir;
    debugPrint('[session] list(): dir=${dir.path} exists=${await dir.exists()}');
    if (!await dir.exists()) {
      return [];
    }
    final summaries = <SessionSummary>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.muse')) {
        continue;
      }
      final stem = entity.path.substring(0, entity.path.length - 5);
      final metadata = await _readMetadata('$stem.json');
      final id = _idFromPath(entity.path);
      summaries.add(
        SessionSummary(
          id: id,
          metadata: metadata,
          musePath: entity.path,
          pngPath: File('$stem.png').existsSync() ? '$stem.png' : null,
        ),
      );
    }
    summaries.sort(
      (a, b) => b.metadata.savedAt.compareTo(a.metadata.savedAt),
    );
    debugPrint('[session] list(): found ${summaries.length} session(s)');
    return summaries;
  }

  Future<void> writeMetadata(File museFile, SessionMetadata metadata) async {
    final stem = museFile.path.substring(0, museFile.path.length - 5);
    final jsonPath = '$stem.json';
    try {
      await File(jsonPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(metadata.toJson()),
      );
      debugPrint('[session] metadata written: $jsonPath');
    } catch (e) {
      debugPrint('[session] metadata write FAILED: $jsonPath ($e)');
      rethrow;
    }
  }

  Future<SessionMetadata> _readMetadata(String jsonPath) async {
    final file = File(jsonPath);
    if (!file.existsSync()) {
      return SessionMetadata(
        protocol: ProtocolType.alphaTheta,
        durationMinutes: 0,
        elapsedSeconds: 0,
        sound: 'Ambient Drone',
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(_idFromPath(jsonPath)) ?? 0,
        ),
      );
    }
    try {
      final raw = jsonDecode(await file.readAsString());
      return SessionMetadata.fromJson(raw as Map<String, Object?>) ??
          _fallback(jsonPath);
    } catch (_) {
      return _fallback(jsonPath);
    }
  }

  SessionMetadata _fallback(String jsonPath) => SessionMetadata(
    protocol: ProtocolType.alphaTheta,
    durationMinutes: 0,
    elapsedSeconds: 0,
    sound: 'Ambient Drone',
    savedAt: DateTime.fromMillisecondsSinceEpoch(
      int.tryParse(_idFromPath(jsonPath)) ?? 0,
    ),
  );

  String _idFromPath(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final stem = name.startsWith('session_') ? name.substring(8) : name;
    final id = stem.split('.').first;
    return id;
  }
}

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final sessionListProvider = FutureProvider<List<SessionSummary>>(
  (ref) => ref.watch(sessionStoreProvider).list(),
);
