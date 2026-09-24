import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/spine/assemble.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/session_v5/metadata_v6.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/feedback/session_scalars.dart';
import 'package:neurofeed/src/feedback/session_sqlite.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/session_v5/stats_assemble.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';
import 'package:neurofeed/src/version.dart';

/// History-root v5 names: `session_*.neurofeed` and
/// `recording_*.neurofeed`. Not `tmp_`.
bool isHistoryContainerName(String name) {
  if (!name.endsWith('.neurofeed')) return false;
  return name.startsWith('session_') || name.startsWith('recording_');
}


/// Id from a history-root `session_$id.neurofeed` or `recording_$id.neurofeed`.
String? historyContainerId(String name) {
  if (!name.endsWith('.neurofeed')) return null;
  if (name.startsWith('session_')) {
    final id = name.substring(
      'session_'.length,
      name.length - '.neurofeed'.length,
    );
    return id.isEmpty ? null : id;
  }
  if (name.startsWith('recording_')) {
    final id = name.substring(
      'recording_'.length,
      name.length - '.neurofeed'.length,
    );
    return id.isEmpty ? null : id;
  }
  return null;
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
  int _pendingBackfill = 0;

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
  int get pendingBackfillCount => _pendingBackfill;

  Future<List<SessionSummary>> list() async {
    final sqlite = await _sqlite;
    if (sqlite.consumeNeedsReindex()) {
      _pendingBackfill = 1;
    }
    var rows = await sqlite.listSessions();
    if (rows.isEmpty && _pendingBackfill == 0) {
      final storage = await _storage;
      final names = await storage.listFiles();
      if (names.any(isHistoryContainerName)) {
        _pendingBackfill = 1;
      }
    }
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
            timeZone: r.timeZone,
          ),
        ),
    ];
  }

  Future<void> backfillPending() async {
    if (_pendingBackfill == 0) return;
    await reindexFromFiles();
    _pendingBackfill = 0;
  }

  /// Rebuild sqlite rows from every history-root `.neurofeed` file.
  Future<int> reindexFromFiles() async {
    final storage = await _storage;
    final sqlite = await _sqlite;
    final files = await storage.listFilesMeta();
    var upserted = 0;
    for (final f in files) {
      if (!isHistoryContainerName(f.name)) continue;
      try {
        final ok = await _upsertRowFromHistoryFile(
          storage: storage,
          sqlite: sqlite,
          name: f.name,
          mtimeMs: f.mtimeMs,
        );
        if (ok) upserted++;
      } catch (e, st) {
        debugPrint('[session] reindex skip ${f.name}: $e\n$st');
      }
    }
    debugPrint('[session] reindexFromFiles: upserted $upserted');
    return upserted;
  }

  Future<bool> _upsertRowFromHistoryFile({
    required SessionStorage storage,
    required SessionSqlite sqlite,
    required String name,
    required int mtimeMs,
  }) async {
    final id = historyContainerId(name);
    if (id == null) return false;

    late final String path;
    Directory? workDir;
    try {
      if (storage is FileSystemSessionStorage) {
        path = '${storage.location}/$name';
        if (!await File(path).exists()) return false;
      } else if (storage is SafSessionStorage) {
        workDir = await Directory.systemTemp.createTemp('nf_reindex_');
        path = await storage.copySafFileToCache(name, 'reindex_$name');
      } else {
        return false;
      }

      final head = await v5ParseHeadFromPath(path: path);
      final decoded = jsonDecode(utf8.decode(head.metadataJson));
      if (decoded is! Map) return false;
      final meta = <String, Object?>{
        for (final e in decoded.entries) e.key.toString(): e.value,
      };
      final scalars = SessionRowScalars.fromV6Metadata(meta);

      // Prefer file stats; if absent, assemble from computed frames.
      SessionRowScalars filled = scalars;
      if (scalars.avgHr == null &&
          scalars.peakAlphaHz == null &&
          scalars.signalQualityMean == null) {
        try {
          final frames = await v5ExtractComputedFromPath(path: path);
          final labels = () {
            final device = meta['device'];
            if (device is Map && device['channelLabels'] is List) {
              return (device['channelLabels'] as List)
                  .whereType<String>()
                  .toList();
            }
            return const <String>['TP9', 'AF7', 'AF8', 'TP10'];
          }();
          final anns = () {
            final raw = meta['annotations'];
            if (raw is! List) return const <SessionAnnotation>[];
            return raw
                .map(SessionAnnotation.fromJson)
                .whereType<SessionAnnotation>()
                .toList();
          }();
          final assembled = assembleBaseStats(
            frames: frames,
            annotations: anns,
            channelLabels: labels.isEmpty
                ? const ['TP9', 'AF7', 'AF8', 'TP10']
                : labels,
          );
          final feedback = meta['feedback'];
          final outcome = feedback is Map
              ? <String, Object?>{
                  for (final e in (feedback['outcomeScalars'] as Map? ?? {}).entries)
                    e.key.toString(): e.value,
                }
              : null;
          filled = SessionRowScalars.fromStatsAndOutcome(
            stats: assembled,
            outcome: outcome,
          );
        } catch (_) {}
      }

      final kind = (meta['kind'] as String?) == 'recording'
          ? 'recording'
          : (name.startsWith('recording_') ? 'recording' : 'feedback');
      final savedAt =
          DateTime.tryParse(meta['savedAt'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc();
      final startedAt =
          DateTime.tryParse(meta['startedAt'] as String? ?? '')?.toUtc() ??
              savedAt;
      final durationS = (meta['durationS'] as num?)?.toInt() ??
          (meta['elapsedSeconds'] as num?)?.toInt() ??
          0;
      final device = meta['device'];
      final deviceMap = device is Map
          ? <String, Object?>{for (final e in device.entries) e.key.toString(): e.value}
          : null;
      final subject = meta['subject'];
      final subjectMap = subject is Map
          ? <String, Object?>{for (final e in subject.entries) e.key.toString(): e.value}
          : null;
      final feedback = meta['feedback'];
      final fbMap = feedback is Map
          ? <String, Object?>{for (final e in feedback.entries) e.key.toString(): e.value}
          : null;
      final channels = () {
        final labels = deviceMap?['channelLabels'];
        if (labels is List) return labels.whereType<String>().join(',');
        return '';
      }();
      final streams = () {
        final s = meta['streams'];
        if (s is! Map) return '';
        final names = <String>[];
        for (final e in s.entries) {
          final v = e.value;
          if (v is Map && v['enabled'] == true) names.add(e.key.toString());
        }
        return names.join(',');
      }();
      final header = head.header;
      final fileSize = await File(path).length();
      final now = DateTime.now();
      final existing = await sqlite.getSession(id);

      await sqlite.upsertSession(
        SessionRow(
          id: id,
          path: name,
          formatVersion: (meta['formatVersion'] as num?)?.toInt() ?? 6,
          appVersion: meta['appVersion'] as String? ?? appVersion,
          savedAt: savedAt,
          startedAt: startedAt,
          durationS: durationS,
          protocol: fbMap?['protocol'] as String? ??
              (kind == 'recording' ? '' : (meta['protocol'] as String? ?? '')),
          kind: kind,
          protocolVersion: fbMap?['protocolVersion']?.toString(),
          deviceName: deviceMap?['name'] as String?,
          deviceModel: deviceMap?['model'] as String?,
          deviceId: deviceMap?['id'] as String?,
          calibrationProfile: fbMap?['calibrationProfile'] as String?,
          recordedChannels: channels,
          recordedStreams: streams,
          offMeta: header.metadataOffset.toInt(),
          lenMeta: header.metadataLength.toInt(),
          offComputed: header.computedOffset.toInt(),
          lenComputed: header.computedLength.toInt(),
          offRaw: header.rawOffset.toInt(),
          lenRaw: 0,
          avgHr: filled.avgHr,
          hrMin: filled.hrMin,
          hrMax: filled.hrMax,
          avgSpo2: filled.avgSpo2,
          spo2Min: filled.spo2Min,
          spo2Max: filled.spo2Max,
          peakAlphaHz: filled.peakAlphaHz,
          peakAlphaPower: filled.peakAlphaPower,
          peakAlphaMeanHz: filled.peakAlphaMeanHz,
          pctInTarget: filled.pctInTarget,
          avgMovement: filled.avgMovement,
          stillnessPct: filled.stillnessPct,
          guardrailWarnCount: filled.guardrailWarnCount,
          avgSleepDir: filled.avgSleepDir,
          avgAlphaRel: filled.avgAlphaRel,
          guardWarnPct: filled.guardWarnPct,
          guardThreshold: filled.guardThreshold,
          signalQualityMean: filled.signalQualityMean,
          pctQcOk: filled.pctQcOk,
          qualityChannelUsable: filled.qualityChannelUsable,
          annotationPauseS: filled.annotationPauseS,
          annotationBadQualityS: filled.annotationBadQualityS,
          annotationDisconnectS: filled.annotationDisconnectS,
          batteryStartPct: filled.batteryStartPct,
          batteryEndPct: filled.batteryEndPct,
          experimentalScalars: filled.experimentalScalars,
          markerCount: existing?.markerCount ?? 0,
          guardrailEngine: existing?.guardrailEngine,
          modelKind: existing?.modelKind,
          modelSha256: existing?.modelSha256,
          feedbackEngine: existing?.feedbackEngine,
          userId: subjectMap?['id'] as String? ?? existing?.userId,
          sessionId: meta['sessionId'] as String? ?? id,
          notesPreview: () {
            final notes = meta['notes'] as String? ?? '';
            if (notes.isEmpty) return existing?.notesPreview;
            return notes.length > 50 ? notes.substring(0, 50) : notes;
          }(),
          fileSize: fileSize,
          mtime: mtimeMs,
          thumbnail: head.thumbnail.isNotEmpty ? head.thumbnail : existing?.thumbnail,
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
          timeZone: meta['timeZone'] as String?,
          savedAtMs: savedAt.millisecondsSinceEpoch,
        ),
      );
      return true;
    } finally {
      if (workDir != null) {
        try {
          await workDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }


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

  /// Full `.neurofeed` container bytes from the history folder.
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
    SubjectInfo? subject,
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
      final subjectInfo = subject ??
          SubjectInfo(id: metadata.userId ?? '');
      final assembleAnns = metadata.annotations.isNotEmpty
          ? metadata.annotations
          : assembleAnnotations(gestures: metadata.gestures);
      final assembleStats = assembleBaseStats(
        frames: frames,
        annotations: assembleAnns,
        channelLabels: metadata.recordedChannels.isEmpty
            ? const ['TP9', 'AF7', 'AF8', 'TP10']
            : metadata.recordedChannels,
      );
      final container = assembleV5Container(
        thumbnail: thumb,
        metadataJson: buildFeedbackMetadataV6(
          meta: metadata,
          subject: subjectInfo,
          stats: assembleStats,
        ),
        computedFrames: frames,
        rawBody: Uint8List.fromList(rawBody ?? const []),
      );
      await storage.writeFileAtomic(_containerName(id), container);
      fileSize = container.length;
    }
    final durationS = metadata.durationS != 0
        ? metadata.durationS
        : metadata.elapsedSeconds;
    final subjectInfoForRow = subject ??
        SubjectInfo(id: metadata.userId ?? '');
    final userId = subjectInfoForRow.id.isNotEmpty
        ? subjectInfoForRow.id
        : metadata.userId;
    final savedAtDt =
        DateTime.tryParse(metadata.savedAt)?.toUtc() ?? DateTime.now().toUtc();
    final startedAtDt =
        DateTime.tryParse(metadata.startedAt ?? metadata.savedAt)?.toUtc() ??
            savedAtDt;
    final anns = metadata.annotations.isNotEmpty
        ? metadata.annotations
        : assembleAnnotations(gestures: metadata.gestures);
    final channelLabels = metadata.recordedChannels.isEmpty
        ? const <String>['TP9', 'AF7', 'AF8', 'TP10']
        : metadata.recordedChannels;
    final assembledStats = assembleBaseStats(
      frames: frames,
      annotations: anns,
      channelLabels: channelLabels,
    );
    final outcome = <String, Object?>{
      if (metadata.pctInTarget != null) 'pctInTarget': metadata.pctInTarget,
      if (metadata.stats != null) 'avgAlphaRel': metadata.stats!.avgAlphaRel,
      if (metadata.guardrailWarnCount != null)
        'guardrailWarnCount': metadata.guardrailWarnCount,
      if (metadata.avgSleepDir != null) 'avgSleepDir': metadata.avgSleepDir,
      if (metadata.drowsiness != null) ...{
        'guardWarnPct': metadata.drowsiness!.scoreTotalPct,
        if (metadata.drowsiness!.meanSleepDir != 0)
          'avgSleepDir': metadata.drowsiness!.meanSleepDir,
        if (metadata.drowsiness!.threshold != null)
          'guardThreshold': metadata.drowsiness!.threshold,
      },
    };
    final rowScalars = SessionRowScalars.fromStatsAndOutcome(
      stats: assembledStats,
      outcome: outcome.isEmpty ? null : outcome,
    );
    // Prefer assembled stats; fall back to legacy extract / flat metadata.
    final legacy = extractComputedScalars(frames);
    final sqlite = await _sqlite;
    await sqlite.upsertSession(
      SessionRow(
        id: id,
        path: _containerName(id),
        formatVersion: 6,
        appVersion: appVersion,
        savedAt: savedAtDt,
        startedAt: startedAtDt,
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
        avgHr: rowScalars.avgHr ?? legacy.avgHr ?? metadata.stats?.avgBpm,
        hrMin: rowScalars.hrMin,
        hrMax: rowScalars.hrMax,
        avgSpo2: rowScalars.avgSpo2 ?? legacy.avgSpo2 ?? metadata.avgSpo2,
        spo2Min: rowScalars.spo2Min,
        spo2Max: rowScalars.spo2Max,
        peakAlphaHz:
            rowScalars.peakAlphaHz ?? legacy.peakAlphaHz ?? metadata.peakAlphaHz,
        peakAlphaPower: rowScalars.peakAlphaPower ??
            legacy.peakAlphaPower ??
            metadata.peakAlphaPower,
        peakAlphaMeanHz: rowScalars.peakAlphaMeanHz,
        pctInTarget: rowScalars.pctInTarget ??
            legacy.pctInTarget ??
            metadata.pctInTarget,
        avgMovement:
            rowScalars.avgMovement ?? legacy.avgMovement ?? metadata.avgMovement,
        stillnessPct: rowScalars.stillnessPct ?? metadata.stats?.stillnessPct,
        guardrailWarnCount: rowScalars.guardrailWarnCount ??
            legacy.guardrailWarnCount ??
            metadata.guardrailWarnCount,
        avgSleepDir:
            rowScalars.avgSleepDir ?? legacy.avgSleepDir ?? metadata.avgSleepDir,
        avgAlphaRel: rowScalars.avgAlphaRel ?? metadata.stats?.avgAlphaRel,
        guardWarnPct: rowScalars.guardWarnPct,
        guardThreshold: rowScalars.guardThreshold,
        signalQualityMean:
            rowScalars.signalQualityMean ?? metadata.signalQualityMean,
        pctQcOk: rowScalars.pctQcOk ?? metadata.pctQcOk,
        qualityChannelUsable: rowScalars.qualityChannelUsable,
        annotationPauseS: rowScalars.annotationPauseS,
        annotationBadQualityS: rowScalars.annotationBadQualityS,
        annotationDisconnectS: rowScalars.annotationDisconnectS,
        batteryStartPct: rowScalars.batteryStartPct,
        batteryEndPct: rowScalars.batteryEndPct,
        experimentalScalars: rowScalars.experimentalScalars,
        markerCount: metadata.gestures.length,
        guardrailEngine: metadata.guardrailEngine,
        modelKind: metadata.modelKind,
        modelSha256: metadata.modelSha256,
        feedbackEngine: metadata.feedbackEngine,
        userId: userId,
        timeZone: metadata.timeZone,
        savedAtMs: savedAtDt.millisecondsSinceEpoch,
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
  /// Container head in place (via `v5RewriteHeadToPath`; NFED6), copying thumbnail, computed, and raw
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
          existing.copyWith(
            notesPreview: notes.length > 50 ? notes.substring(0, 50) : notes,
            fileSize: destLen,
            mtime: DateTime.now().millisecondsSinceEpoch,
            updatedAt: DateTime.now(),
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
