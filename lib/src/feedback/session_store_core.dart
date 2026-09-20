import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/session_v5/assemble.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/feedback/session_sqlite.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';
import 'package:neurofeed/src/version.dart';

/// History-root v5 names: `session_*.neurofeed` and
/// `recording_*.neurofeed`. Not `tmp_`.
bool isHistoryContainerName(String name) {
  if (!name.endsWith('.neurofeed')) return false;
  return name.startsWith('session_') || name.startsWith('recording_');
}

/// Count published session and recording containers in a [listFiles] result.
({int sessions, int recordings}) countHistoryContainers(
  Iterable<String> names,
) {
  var sessions = 0;
  var recordings = 0;
  for (final name in names) {
    if (!name.endsWith('.neurofeed')) continue;
    if (name.startsWith('session_')) {
      sessions++;
    } else if (name.startsWith('recording_')) {
      recordings++;
    }
  }
  return (sessions: sessions, recordings: recordings);
}

class SessionStore {
  SessionStore({Future<SessionStorage>? storage})
    : _storage = storage ?? _defaultStorage(),
      _sqlite = _initSqlite(storage);

  final Future<SessionStorage> _storage;
  final Future<SessionSqlite> _sqlite;

  static Future<SessionSqlite> _initSqlite(
    Future<SessionStorage>? storage,
  ) async {
    if (storage != null) {
      final s = await storage;
      final cacheDir = await resolveSessionCacheDir(s);
      return SessionSqlite.open(cacheDirectory: cacheDir);
    }
    // Fallback - shouldn't happen in practice
    final defaultStorage = await _defaultStorage();
    final cacheDir = await resolveSessionCacheDir(defaultStorage);
    return SessionSqlite.open(cacheDirectory: cacheDir);
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
          kind: r.kind,
          path: r.path,
          metadata: SessionMetadata(
            protocol: r.protocol,
            durationMinutes: r.durationS ~/ 60,
            elapsedSeconds: r.durationS,
            sound: 'Ambient Drone',
            savedAt: r.savedAt.toIso8601String(),
            deviceName: r.deviceName,
            deviceModel: r.deviceModel,
            deviceId: r.deviceId,
            recordedChannels: r.recordedChannels.isEmpty
                ? const <String>[]
                : r.recordedChannels
                      .split(',')
                      .where((s) => s.isNotEmpty)
                      .toList(),
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
    final bytes = await storage.readFile(await _fileNameFor(id));
    if (bytes == null) return null;
    return v5ExtractRaw(bytes: Uint8List.fromList(bytes));
  }

  /// Filesystem path of a history container. SAF copies into cache first.
  Future<String?> resolveContainerPath(String id) async {
    final storage = await _storage;
    final name = await _fileNameFor(id);
    if (storage is FileSystemSessionStorage) {
      final path = '${storage.location}/$name';
      if (await File(path).exists()) return path;
      return null;
    }
    if (storage is SafSessionStorage) {
      if (!await storage.fileExists(name)) return null;
      return storage.copySafFileToCache(name, 'view_$name');
    }
    return null;
  }

  /// Full v5 container bytes from the history folder.
  Future<Uint8List?> readContainer(String id) async {
    final storage = await _storage;
    final bytes = await storage.readFile(await _fileNameFor(id));
    if (bytes == null) return null;
    return Uint8List.fromList(bytes);
  }

  Future<List<int>?> readPng(String id) async {
    final sqlite = await _sqlite;
    final session = await sqlite.getSession(id);
    if (session != null &&
        session.thumbnail != null &&
        session.thumbnail!.isNotEmpty) {
      return session.thumbnail;
    }
    // Fallback: parse from container file if not in cache
    final storage = await _storage;
    final bytes = await storage.readFile(await _fileNameFor(id));
    if (bytes == null) return null;
    try {
      final head = v5ParseHead(bytes: Uint8List.fromList(bytes));
      return head.thumbnail;
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

  String _containerName(String id) => 'session_$id.neurofeed';

  /// Sqlite `path` when present (`recording_$id.neurofeed` for
  /// recordings). Falls back to `session_$id.neurofeed`.
  Future<String> _fileNameFor(String id) async {
    final sqlite = await _sqlite;
    final row = await sqlite.getSession(id);
    final path = row?.path;
    if (path != null && path.isNotEmpty) return path;
    return _containerName(id);
  }

  /// Namespace for cache rows — a short hash of the storage location so two
  /// history folders never share metadata rows even when ids collide.
  static String storageKeyFor(SessionStorage storage) =>
      sha256.convert(utf8.encode(storage.location)).toString().substring(0, 16);

  /// Persist a finished session into the history folder as a single
  /// `.neurofeed` container. Prefer [encodedV5Path] (file copy). [encodedV5]
  /// and part-wise assemble are small-fixture paths only.
  Future<SessionSummary> publishSession(
    String id,
    SessionMetadata metadata, {
    Uint8List? encodedV5,
    String? encodedV5Path,
    List<int>? rawBody,
    List<int>? thumbnail,
    List<ComputedFrame>? computedFrames,
  }) async {
    final storage = await _storage;
    await storage.ensureDir();
    late final int fileSize;
    late final Uint8List thumb;
    late final List<ComputedFrame> frames;
    if (encodedV5Path != null) {
      final head = await v5ParseHeadFromPath(path: encodedV5Path);
      thumb = head.thumbnail;
      frames = await v5ExtractComputedFromPath(path: encodedV5Path);
      await storage.copyFromPath(_containerName(id), encodedV5Path);
      fileSize = await File(encodedV5Path).length();
    } else if (encodedV5 != null) {
      final head = v5ParseHead(bytes: encodedV5);
      thumb = head.thumbnail;
      frames = v5ExtractComputed(bytes: encodedV5);
      await storage.writeFileAtomic(_containerName(id), encodedV5);
      fileSize = encodedV5.length;
    } else {
      frames = computedFrames ?? const <ComputedFrame>[];
      thumb = Uint8List.fromList(
        (thumbnail != null && thumbnail.isNotEmpty)
            ? thumbnail
            : placeholderWebP,
      );
      final container = assembleV5Container(
        thumbnail: thumb,
        metadataJson: metadata.toJson(),
        computedFrames: frames,
        rawBody: Uint8List.fromList(rawBody ?? const []),
      );
      await storage.writeFileAtomic(_containerName(id), container);
      fileSize = container.length;
    }
    final scalars = extractComputedScalars(frames);
    final durationS = metadata.durationS != 0
        ? metadata.durationS
        : metadata.elapsedSeconds;
    final sqlite = await _sqlite;
    await sqlite.upsertSession(
      SessionRow(
        id: id,
        path: _containerName(id),
        formatVersion: 5,
        appVersion: appVersion,
        savedAt: DateTime.tryParse(metadata.savedAt) ?? DateTime.now(),
        startedAt:
            DateTime.tryParse(metadata.startedAt ?? metadata.savedAt) ??
            DateTime.now(),
        durationS: durationS,
        protocol: metadata.protocol,
        kind: 'feedback',
        protocolVersion: metadata.protocolVersion,
        deviceName: metadata.deviceName,
        deviceModel: metadata.deviceModel,
        deviceId: metadata.deviceId,
        calibrationProfile: metadata.calibrationProfile,
        recordedChannels: metadata.recordedChannels.join(','),
        recordedStreams: '',
        offMeta: 0,
        lenMeta: 0,
        offComputed: 0,
        lenComputed: 0,
        offRaw: 0,
        lenRaw: 0,
        avgHr: scalars.avgHr ?? metadata.stats?.avgBpm,
        avgSpo2: scalars.avgSpo2 ?? metadata.avgSpo2,
        peakAlphaHz: scalars.peakAlphaHz ?? metadata.peakAlphaHz,
        peakAlphaPower: scalars.peakAlphaPower ?? metadata.peakAlphaPower,
        pctInTarget: scalars.pctInTarget ?? metadata.pctInTarget,
        avgMovement: scalars.avgMovement ?? metadata.avgMovement,
        guardrailWarnCount:
            scalars.guardrailWarnCount ?? metadata.guardrailWarnCount,
        avgSleepDir: scalars.avgSleepDir ?? metadata.avgSleepDir,
        signalQualityMean: metadata.signalQualityMean,
        pctQcOk: metadata.pctQcOk,
        markerCount: metadata.gestures.length,
        guardrailEngine: metadata.guardrailEngine,
        modelKind: metadata.modelKind,
        modelSha256: metadata.modelSha256,
        feedbackEngine: metadata.feedbackEngine,
        userId: metadata.userId,
        sessionId: metadata.sessionId,
        notesPreview: metadata.notes.isNotEmpty
            ? (metadata.notes.length > 50
                  ? metadata.notes.substring(0, 50)
                  : metadata.notes)
            : null,
        fileSize: fileSize,
        mtime: DateTime.now().millisecondsSinceEpoch,
        thumbnail: thumb.isNotEmpty ? thumb : null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    debugPrint('[session] written ${_containerName(id)} to ${storage.location}');
    return SessionSummary(
      id: id,
      metadata: metadata,
      kind: 'feedback',
      path: _containerName(id),
    );
  }

  /// Replace the free-text notes of an existing session and rewrite the
  /// v5 container head in place, copying thumbnail, computed, and raw
  /// sections as opaque bytes. Returns false when the session file is missing
  /// or unreadable.
  Future<bool> updateNotes(String id, String notes) async {
    final storage = await _storage;
    final name = await _fileNameFor(id);
    if (!await storage.fileExists(name)) {
      debugPrint('[session] updateNotes($id): file not found ($name)');
      return false;
    }
    Directory? workDir;
    late final String srcPath;
    late final String destPath;
    try {
      if (storage is FileSystemSessionStorage) {
        srcPath = '${storage.location}/$name';
        destPath = '${storage.location}/.$name.notes.tmp';
      } else if (storage is SafSessionStorage) {
        workDir = await Directory.systemTemp.createTemp('nf_notes_');
        srcPath = await storage.copySafFileToCache(name, 'notes_$name');
        destPath = '${workDir.path}/dst.neurofeed';
      } else {
        debugPrint('[session] updateNotes($id): unsupported storage');
        return false;
      }
      final head = await v5ParseHeadFromPath(path: srcPath);
      final decoded =
          jsonDecode(String.fromCharCodes(head.metadataJson))
              as Map<String, Object?>;
      decoded['notes'] = notes;
      final jsonBytes = Uint8List.fromList(
        const JsonEncoder().convert(decoded).codeUnits,
      );
      await v5RewriteHeadToPath(
        srcPath: srcPath,
        destPath: destPath,
        metadataJson: jsonBytes,
        thumbnail: Uint8List(0),
      );
      final destLen = await File(destPath).length();
      if (storage is FileSystemSessionStorage) {
        final target = File(srcPath);
        final tmp = File(destPath);
        try {
          await tmp.rename(target.path);
        } on FileSystemException {
          if (await target.exists()) {
            await target.delete();
          }
          await tmp.rename(target.path);
        }
      } else {
        await storage.copyFromPath(name, destPath);
      }
      final sqlite = await _sqlite;
      final existing = await sqlite.getSession(id);
      if (existing != null) {
        await sqlite.upsertSession(
          SessionRow(
            id: existing.id,
            path: existing.path,
            formatVersion: existing.formatVersion,
            appVersion: existing.appVersion,
            savedAt: existing.savedAt,
            startedAt: existing.startedAt,
            durationS: existing.durationS,
            protocol: existing.protocol,
            kind: existing.kind,
            protocolVersion: existing.protocolVersion,
            deviceName: existing.deviceName,
            deviceModel: existing.deviceModel,
            deviceId: existing.deviceId,
            calibrationProfile: existing.calibrationProfile,
            recordedChannels: existing.recordedChannels,
            recordedStreams: existing.recordedStreams,
            offMeta: existing.offMeta,
            lenMeta: existing.lenMeta,
            offComputed: existing.offComputed,
            lenComputed: existing.lenComputed,
            offRaw: existing.offRaw,
            lenRaw: existing.lenRaw,
            avgHr: existing.avgHr,
            avgSpo2: existing.avgSpo2,
            peakAlphaHz: existing.peakAlphaHz,
            peakAlphaPower: existing.peakAlphaPower,
            pctInTarget: existing.pctInTarget,
            avgMovement: existing.avgMovement,
            guardrailWarnCount: existing.guardrailWarnCount,
            avgSleepDir: existing.avgSleepDir,
            signalQualityMean: existing.signalQualityMean,
            pctQcOk: existing.pctQcOk,
            markerCount: existing.markerCount,
            guardrailEngine: existing.guardrailEngine,
            modelKind: existing.modelKind,
            modelSha256: existing.modelSha256,
            feedbackEngine: existing.feedbackEngine,
            userId: existing.userId,
            sessionId: existing.sessionId,
            notesPreview: notes.length > 50 ? notes.substring(0, 50) : notes,
            fileSize: destLen,
            mtime: DateTime.now().millisecondsSinceEpoch,
            createdAt: existing.createdAt,
            updatedAt: DateTime.now(),
            thumbnail: existing.thumbnail,
          ),
        );
      }
      debugPrint('[session] updateNotes($id): notes saved ($name)');
      return true;
    } finally {
      if (workDir != null) {
        try {
          await workDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  /// Delete one session from history (the `.neurofeed` file). Returns
  /// false when the file was already gone.
  Future<bool> delete(String id) async {
    final storage = await _storage;
    final name = await _fileNameFor(id);
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
      if (!isHistoryContainerName(name)) {
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
    debugPrint('[session] moved $moved file(s)');
    return moved;
  }
}
