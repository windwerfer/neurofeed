import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/session_v5/assemble.dart';
import 'package:neurofeed/src/feedback/feedback_state.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/feedback/session_store.dart';
import 'package:neurofeed/src/rust/api/session_format.dart' as ffi;
import 'package:neurofeed/src/views/feedback_dashboard.dart';

/// An assembled scratch v5 left over from a crash or an interrupted save.
class RecoverableSession {
  RecoverableSession({
    required this.id,
    required this.scratchV5,
    required this.protocol,
    required this.elapsedSeconds,
    required this.calibrationKind,
    this.metadata,
  });

  final String id;
  final File scratchV5;
  final String protocol;
  final int elapsedSeconds;
  final String calibrationKind;
  final SessionMetadata? metadata;

  /// Publish the scratch v5 into history, then delete it.
  Future<void> save(SessionStore store) async {
    final head = await ffi.v5ParseHeadFromPath(path: scratchV5.path);
    final meta = SessionMetadata.fromJsonBytes(head.metadataJson) ??
        SessionMetadata(
          protocol: protocol,
          durationMinutes: elapsedSeconds <= 0 ? 0 : (elapsedSeconds / 60).ceil(),
          elapsedSeconds: elapsedSeconds,
          sound: '',
          savedAt: DateTime.now().toIso8601String(),
          sessionId: id,
        );
    await store.publishSession(id, meta, encodedV5Path: scratchV5.path);
    await discard();
  }

  /// Delete the scratch v5. Temps are already gone after assemble.
  Future<void> discard() async {
    if (await scratchV5.exists()) {
      await scratchV5.delete();
    }
  }
}

class _ScratchFiles {
  File? v5;
  File? raw;
  File? computed;
  File? metadata;
}

String? _idFrom(String name, String suffix) {
  const prefix = 'session_';
  if (!name.startsWith(prefix) || !name.endsWith(suffix)) return null;
  final id = name.substring(prefix.length, name.length - suffix.length);
  return id.isEmpty ? null : id;
}

Future<void> _deleteTemps(_ScratchFiles files) async {
  for (final f in [files.raw, files.computed, files.metadata]) {
    if (f != null && await f.exists()) {
      try {
        await f.delete();
      } catch (e) {
        debugPrint('[crash] failed to delete ${f.path}: $e');
      }
    }
  }
}

SessionMetadata _metadataFromTemps({
  required String id,
  required Uint8List jsonl,
  required List<ffi.ComputedFrame> frames,
}) {
  var protocol = '';
  var calibrationKind = '';
  String? calibrationId;
  if (jsonl.isNotEmpty) {
    for (final line in utf8.decode(jsonl, allowMalformed: true).split('\n')) {
      if (line.trim().isEmpty) continue;
      try {
        final meta = jsonDecode(line);
        if (meta is! Map) continue;
        final type = meta['type'];
        if (type == 'protocol') {
          protocol = meta['protocol'] as String? ?? protocol;
        } else if (type == 'calibration_start') {
          calibrationKind = meta['kind'] as String? ?? calibrationKind;
          calibrationId = meta['calibrationId'] as String? ?? calibrationId;
        }
      } catch (_) {}
    }
  }
  final elapsed = frames.isEmpty ? 0 : frames.last.t.round();
  final scalars = extractComputedScalars(frames);
  return SessionMetadata(
    protocol: protocol,
    durationMinutes: elapsed <= 0 ? 0 : (elapsed / 60).ceil(),
    elapsedSeconds: elapsed,
    durationS: elapsed,
    sound: '',
    savedAt: DateTime.now().toIso8601String(),
    sessionId: id,
    calibration: calibrationId == null && calibrationKind.isEmpty
        ? null
        : SessionCalibration(
            version: 2,
            kind: calibrationKind.isEmpty ? 'single' : calibrationKind,
            calibrationId: calibrationId ?? '',
          ),
    drowsiness: frames.isEmpty
        ? null
        : SessionDrowsiness(
            scoreTotalPct:
                (scalars.guardrailWarnCount ?? 0) * 100 / frames.length,
            meanSleepDir: scalars.avgSleepDir ?? 0,
          ),
    avgSpo2: scalars.avgSpo2,
    peakAlphaHz: scalars.peakAlphaHz,
    peakAlphaPower: scalars.peakAlphaPower,
    pctInTarget: scalars.pctInTarget,
    avgMovement: scalars.avgMovement,
    guardrailWarnCount: scalars.guardrailWarnCount,
    avgSleepDir: scalars.avgSleepDir,
  );
}

Future<RecoverableSession?> _fromV5(File file, String id) async {
  var protocol = '';
  var elapsed = 0;
  var calibrationKind = '';
  SessionMetadata? meta;
  try {
    final head = await ffi.v5ParseHeadFromPath(path: file.path);
    meta = SessionMetadata.fromJsonBytes(head.metadataJson);
    if (meta != null) {
      protocol = meta.protocol;
      elapsed = meta.elapsedSeconds;
      calibrationKind = meta.calibration?.kind ?? '';
    }
  } catch (e) {
    debugPrint('[crash] failed to parse ${file.path}: $e');
  }
  return RecoverableSession(
    id: id,
    scratchV5: file,
    protocol: protocol,
    elapsedSeconds: elapsed,
    calibrationKind: calibrationKind,
    metadata: meta,
  );
}

Future<RecoverableSession?> _assembleTemps({
  required Directory scratch,
  required String id,
  required _ScratchFiles files,
}) async {
  try {
    final computed = files.computed != null && await files.computed!.exists()
        ? await files.computed!.readAsBytes()
        : Uint8List(0);
    final metadataBytes =
        files.metadata != null && await files.metadata!.exists()
            ? await files.metadata!.readAsBytes()
            : Uint8List(0);
    final frames = parseComputedJsonl(computed);
    final meta = _metadataFromTemps(
      id: id,
      jsonl: metadataBytes,
      frames: frames,
    );
    final file = await writeScratchV5(
      dir: scratch,
      id: id,
      metadataJson: meta.toJson(),
      rawPath: files.raw != null && await files.raw!.exists()
          ? files.raw!.path
          : '',
      computedPath: files.computed != null && await files.computed!.exists()
          ? files.computed!.path
          : '',
    );
    await _deleteTemps(files);
    return RecoverableSession(
      id: id,
      scratchV5: file,
      protocol: meta.protocol,
      elapsedSeconds: meta.elapsedSeconds,
      calibrationKind: meta.calibration?.kind ?? '',
      metadata: meta,
    );
  } catch (e, st) {
    debugPrint('[crash] assemble temps for $id failed: $e\n$st');
    return null;
  }
}

/// Scan [scratchDirectory] for leftover `session_*.neurofeed` and orphan
/// three-temps. Temps are assembled with [writeScratchV5] before return.
/// Does not scan `getTemporaryDirectory()/sessions`.
Future<List<RecoverableSession>> scanRecoverableSessions(
  SessionStorage storage,
) async {
  final scratch = scratchDirectory(storage);
  if (!await scratch.exists()) return const [];

  final byId = <String, _ScratchFiles>{};
  await for (final entity in scratch.list()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    void take(String? id, void Function(_ScratchFiles f) set) {
      if (id == null) return;
      set(byId.putIfAbsent(id, _ScratchFiles.new));
    }

    take(_idFrom(name, '.neurofeed'), (f) => f.v5 = entity);
    take(_idFrom(name, '.raw'), (f) => f.raw = entity);
    take(_idFrom(name, '.computed'), (f) => f.computed = entity);
    take(_idFrom(name, '.metadata'), (f) => f.metadata = entity);
  }

  final recovered = <RecoverableSession>[];
  for (final entry in byId.entries) {
    final id = entry.key;
    final files = entry.value;
    if (files.v5 != null) {
      await _deleteTemps(files);
      final session = await _fromV5(files.v5!, id);
      if (session != null) recovered.add(session);
      continue;
    }
    if (files.raw == null && files.computed == null) {
      await _deleteTemps(files);
      continue;
    }
    final session = await _assembleTemps(
      scratch: scratch,
      id: id,
      files: files,
    );
    if (session != null) recovered.add(session);
  }
  return recovered;
}

/// Re-open the session summary for leftover scratch sessions at startup.
/// The summary cannot be dismissed except by Save or Discard.
Future<void> showCrashRecoveryDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final storage = await ref.read(sessionStorageProvider.future);
  final sessions = await scanRecoverableSessions(storage);
  if (sessions.isEmpty) return;

  for (final session in sessions) {
    if (!context.mounted) return;
    ref.read(feedbackStateProvider.notifier).restoreEndedSession(
      id: session.id,
      scratchPath: session.scratchV5.path,
      metadata: session.metadata,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const FeedbackDashboardView(),
      ),
    );
  }
}
