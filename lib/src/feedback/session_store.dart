import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
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

  String _museName(String id) => 'session_$id.muse';

  Future<List<SessionSummary>> list() async {
    final storage = await _storage;
    debugPrint(
        '[session] list(): storage=${storage.displayName} loc=${storage.location}');
    final names = await storage.listFiles();
    final summaries = <SessionSummary>[];
    for (final name in names) {
      if (!name.startsWith('session_') || !name.endsWith('.muse')) {
        continue;
      }
      final id = name.substring(8, name.length - 5);
      final jsonName = 'session_$id.json';
      final metadata = await _readMetadata(storage, jsonName, id);
      summaries.add(SessionSummary(id: id, metadata: metadata));
    }
    summaries.sort(
      (a, b) => b.metadata.savedAt.compareTo(a.metadata.savedAt),
    );
    debugPrint('[session] list(): found ${summaries.length} session(s)');
    return summaries;
  }

  /// Read the raw .muse bytes for [id], or null if missing.
  Future<List<int>?> readMuse(String id) async {
    final storage = await _storage;
    return storage.readFile(_museName(id));
  }

  /// Read the thumbnail PNG bytes for [id], or null when missing.
  Future<List<int>?> readPng(String id) async {
    final storage = await _storage;
    return storage.readFile('session_$id.png');
  }

  /// Persist a finished session into the history folder: the .muse bytes,
  /// the metadata json, and an optional thumbnail png.
  Future<SessionSummary> publishSession(
    String id,
    List<int> museBytes,
    SessionMetadata metadata, {
    List<int>? pngBytes,
  }) async {
    final storage = await _storage;
    await storage.ensureDir();
    await storage.writeFile(_museName(id), museBytes);
    await storage.writeFile(
      'session_$id.json',
      const JsonEncoder.withIndent('  ').convert(metadata.toJson()).codeUnits,
    );
    if (pngBytes != null) {
      await storage.writeFile('session_$id.png', pngBytes);
    }
    debugPrint('[session] written session_$id.muse to ${storage.location}');
    return SessionSummary(id: id, metadata: metadata);
  }

  /// Copy every session in the current storage into [target], then delete the
  /// source copies so the folder change does not duplicate history. Returns the
  /// number of `.muse` files moved (used for folder-change migration).
  Future<int> moveAllTo(SessionStorage target) async {
    final storage = await _storage;
    final names = await storage.listFiles();
    var moved = 0;
    for (final name in names) {
      if (!name.startsWith('session_') || !name.endsWith('.muse')) {
        continue;
      }
      final bytes = await storage.readFile(name);
      if (bytes == null) {
        continue;
      }
      await target.ensureDir();
      await target.writeFile(name, bytes);
      await storage.deleteFile(name);
      final stem = name.substring(0, name.length - 5);
      final jsonName = '$stem.json';
      final json = await storage.readFile(jsonName);
      if (json != null) {
        await target.writeFile(jsonName, json);
        await storage.deleteFile(jsonName);
      }
      final pngName = '$stem.png';
      final png = await storage.readFile(pngName);
      if (png != null) {
        await target.writeFile(pngName, png);
        await storage.deleteFile(pngName);
      }
      moved++;
    }
    debugPrint('[session] moved $moved session(s)');
    return moved;
  }

  Future<SessionMetadata> _readMetadata(
    SessionStorage storage,
    String jsonName,
    String id,
  ) async {
    try {
      final raw = await storage.readFile(jsonName);
      if (raw == null) {
        return _fallback(id);
      }
      final decoded = jsonDecode(String.fromCharCodes(raw));
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
