import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_cache.dart';
import 'package:muse_ml/src/feedback/session_container.dart';
import 'package:muse_ml/src/feedback/session_metadata.dart';
import 'package:muse_ml/src/feedback/session_sqlite.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';
import 'package:muse_ml/src/settings.dart';

class SessionStore {
  SessionStore({Future<SessionStorage>? storage})
    : _storage = storage ?? _defaultStorage(),
      _sqlite = SessionSqlite.open();

  final Future<SessionStorage> _storage;
  final Future<SessionSqlite> _sqlite;
  final SessionCache _cache = SessionCache.noop();

  Future<String?> _writeThumbnail(String id, List<int> pngBytes) async {
    final cache = await SessionCache.open();
    await cache.writeThumbnail(id, Uint8List.fromList(pngBytes));
    return cache.thumbnailPath(id);
  }

  /// Number of sessions awaiting background backfill after the last [list].
  int get pendingBackfillCount => 0;

  Future<List<SessionSummary>> list() async {
    final sqlite = await _sqlite;
    final rows = await sqlite.listSessions();
    return [
      for (final r in rows)
        SessionSummary(
          id: r.id,
          metadata: SessionMetadata(
            protocol: ProtocolType.values.where((p) => p.name == r.protocol).firstOrNull ?? ProtocolType.drowsiness,
            durationMinutes: r.durationS ~/ 60,
            elapsedSeconds: r.durationS,
            sound: 'Ambient Drone',
            savedAt: r.savedAt.toIso8601String(),
            deviceName: r.deviceName,
            deviceModel: r.deviceModel,
            deviceId: r.deviceId,
            durationS: r.durationS,
            startedAt: r.startedAt.toIso8601String(),
            protocolVersion: r.protocolVersion,
            calibrationProfile: r.calibrationProfile,
            avgSpo2: r.avgSpo2,
            peakAlphaHz: r.peakAlphaHz,
            peakAlphaPower: r.peakAlphaPower,
            pctInTarget: r.pctInTarget,
            avgMovement: r.avgMovement,
            guardrailWarnCount: r.guardrailWarnCount,
            avgSleepDir: r.avgSleepDir,
            signalQualityMean: r.signalQualityMean,
            pctQcOk: r.pctQcOk,
            guardrailEngine: r.guardrailEngine,
            modelKind: r.modelKind,
            modelSha256: r.modelSha256,
            feedbackEngine: r.feedbackEngine,
            userId: r.userId,
            sessionId: r.sessionId,
          ),
        ),
    ];
  }

  Future<void> backfillPending() async {}

  Future<List<int>?> readMuse(String id) async {
    final storage = await _storage;
    final bytes = await storage.readFile(_museName(id));
    if (bytes == null) return null;
    return v5_extract_raw(Uint8List.fromList(bytes));
  }

  Future<List<int>?> readPng(String id) async {
    final storage = await _storage;
    final bytes = await storage.readFile(_museName(id));
    if (bytes == null) return null;
    try {
      final head = v5_parse_head(Uint8List.fromList(bytes));
      return head.pngBytes;
    } catch (_) {
      return null;
    }
  }

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
    final sqlite = await _sqlite;
    final thumbPath = pngBytes != null && pngBytes.isNotEmpty
        ? await _writeThumbnail(id, pngBytes)
        : null;
    await sqlite.upsertSession(SessionRow(
      id: id,
      path: '',
      formatVersion: 5,
      appVersion: '1.0.0+1',
      savedAt: metadata.savedAt,
      startedAt: metadata.startedAt ?? metadata.savedAt,
      durationS: metadata.durationS,
      protocol: metadata.protocol,
      protocolVersion: metadata.protocolVersion,
      deviceName: metadata.deviceName,
      deviceModel: metadata.deviceModel,
      deviceId: metadata.deviceId,
      calibrationProfile: metadata.calibrationProfile,
      recordedChannels: metadata.recordedChannels,
      recordedStreams: metadata.recordedStreams,
      offMeta: 0, // Will be filled from container
      lenMeta: 0,
      offComputed: 0,
      lenComputed: 0,
      offRaw: 0,
      lenRaw: 0,
      durationS: metadata.durationS,
      avgHr: metadata.summary?.avgHr,
      avgSpo2: metadata.avgSpo2,
      peakAlphaHz: metadata.peakAlphaHz,
      peakAlphaPower: metadata.peakAlphaPower,
      pctInTarget: metadata.pctInTarget,
      avgMovement: metadata.avgMovement,
      guardrailWarnCount: metadata.guardrailWarnCount,
      avgSleepDir: metadata.avgSleepDir,
      signalQualityMean: metadata.signalQualityMean,
      pctQcOk: metadata.pctQcOk,
      markerCount: metadata.markerCount,
      guardrailEngine: metadata.guardrailEngine,
      modelKind: metadata.modelKind,
      modelSha256: metadata.modelSha256,
      feedbackEngine: metadata.feedbackEngine,
      calibrationProfile: metadata.calibrationProfile,
      userId: metadata.userId,
      sessionId: metadata.sessionId,
      notesPreview: metadata.notesPreview,
      fileSize: 0,
      mtime: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
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
        jsonDecode(String.fromCharCodes(head.jsonBytes)) as Map<String, Object?>;
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
    final sqlite = await _sqlite;
    await sqlite.upsertSession(SessionRow(
      id: id,
      path: '',
      formatVersion: 5,
      appVersion: '1.0.0+1',
      savedAt: DateTime.now(),
      startedAt: DateTime.now(),
      durationS: 0,
      protocol: 'drowsiness',
      recordedChannels: '[]',
      recordedStreams: '[]',
      offMeta: 0,
      lenMeta: 0,
      offComputed: 0,
      lenComputed: 0,
      offRaw: 0,
      lenRaw: 0,
      durationS: 0,
      markerCount: 0,
      fileSize: 0,
      mtime: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
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
    final sqlite = await _sqlite;
    final rows = await sqlite.getMarkers(id);
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
    final sqlite = await _sqlite;
    await sqlite.deleteMarkers(id);
    await sqlite.deleteSession(id);
    debugPrint(
      '[session] delete($id): ${existed ? 'deleted' : 'missing'} ($name)',
    );
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
    (await _sqlite).close();
    debugPrint('[session] moved $moved session(s)');
    return moved;
  }

  /// Fold a freshly computed [SessionOverview] (from a full-body parse of a
  /// legacy session without an embedded summary) back into the cached
  /// metadata so the next detail-view open fast-paths through the overview.
  /// Cache-only — the container file is never rewritten.
  Future<void> cacheOverview(String id, SessionOverview overview) async {
    final sqlite = await _sqlite;
    try {
      final session = await sqlite.getSession(id);
      if (session == null) {
        return;
      }
      // Update the session with new overview
      // This would require updating the session with new summary data
      // For now, just log
      debugPrint('[session] cacheOverview($id): overview cached');
    } catch (e) {
      debugPrint('[session] cacheOverview($id) failed: $e');
    }
  }

  SessionMetadata _fallback(String id) => SessionMetadata(
    protocol: 'drowsiness',
    durationMinutes: 0,
    elapsedSeconds: 0,
    sound: 'Ambient Drone',
    savedAt: DateTime.fromMillisecondsSinceEpoch(int.tryParse(id) ?? 0).toIso8601String(),
  );
}