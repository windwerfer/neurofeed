import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/session_assembler.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/rust/api/session_format.dart' as ffi;

/// An assembled scratch v5 left over from a crash or an interrupted save.
class RecoverableSession {
  RecoverableSession({
    required this.id,
    required this.scratchV5,
    required this.protocol,
    required this.elapsedSeconds,
    required this.calibrationKind,
  });

  final String id;
  final File scratchV5;
  final String protocol;
  final int elapsedSeconds;
  final String calibrationKind;

  /// Publish the scratch v5 into history, then delete it.
  Future<void> save(SessionStore store) async {
    final bytes = Uint8List.fromList(await scratchV5.readAsBytes());
    final head = ffi.v5ParseHead(bytes: bytes);
    final meta = SessionMetadata.fromJsonBytes(head.metadataJson) ??
        SessionMetadata(
          protocol: protocol,
          durationMinutes: elapsedSeconds <= 0 ? 0 : (elapsedSeconds / 60).ceil(),
          elapsedSeconds: elapsedSeconds,
          sound: '',
          savedAt: DateTime.now().toIso8601String(),
          sessionId: id,
        );
    await store.publishSession(id, meta, encodedV5: bytes);
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
  try {
    final bytes = Uint8List.fromList(await file.readAsBytes());
    final head = ffi.v5ParseHead(bytes: bytes);
    final meta = SessionMetadata.fromJsonBytes(head.metadataJson);
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
  );
}

Future<RecoverableSession?> _assembleTemps({
  required Directory scratch,
  required String id,
  required _ScratchFiles files,
}) async {
  try {
    final raw = files.raw != null && await files.raw!.exists()
        ? await files.raw!.readAsBytes()
        : Uint8List(0);
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
      rawBody: raw,
      computedJsonl: computed,
    );
    await _deleteTemps(files);
    return RecoverableSession(
      id: id,
      scratchV5: file,
      protocol: meta.protocol,
      elapsedSeconds: meta.elapsedSeconds,
      calibrationKind: meta.calibration?.kind ?? '',
    );
  } catch (e, st) {
    debugPrint('[crash] assemble temps for $id failed: $e\n$st');
    return null;
  }
}

/// Scan [scratchDirectory] for leftover `session_*.muse.feedback` and orphan
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

    take(_idFrom(name, '.muse.feedback'), (f) => f.v5 = entity);
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

/// Blocking Save / Discard modal for leftover scratch sessions at startup.
Future<void> showCrashRecoveryDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final storage = await ref.read(sessionStorageProvider.future);
  final sessions = await scanRecoverableSessions(storage);
  if (sessions.isEmpty) return;

  for (final session in sessions) {
    if (!context.mounted) return;
    final shouldSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CrashRecoveryDialog(session: session),
    );
    if (shouldSave == true) {
      final store = await ref.read(sessionStoreProvider.future);
      await session.save(store);
      ref.invalidate(sessionListProvider);
    } else {
      await session.discard();
    }
  }
}

class _CrashRecoveryDialog extends StatelessWidget {
  const _CrashRecoveryDialog({required this.session});

  final RecoverableSession session;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Incomplete Session Detected'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The app crashed or was closed during a recording session. '
                'You have an incomplete session that can be recovered.',
              ),
              const SizedBox(height: 16),
              _InfoRow(label: 'Session', value: session.id),
              _InfoRow(
                label: 'Protocol',
                value: session.protocol.isEmpty ? 'Unknown' : session.protocol,
              ),
              _InfoRow(label: 'Duration', value: '${session.elapsedSeconds}s'),
              if (session.calibrationKind.isNotEmpty)
                _InfoRow(label: 'Calibration', value: session.calibrationKind),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save Session'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
