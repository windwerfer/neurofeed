import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/computed_frame.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/rust/api/session_format.dart' as ffi;
import 'package:path_provider/path_provider.dart';

/// Represents an incomplete session found in the cache directory.
class IncompleteSession {
  IncompleteSession({
    required this.id,
    required this.rawFile,
    required this.computedFile,
    required this.metadataFile,
    required this.durationMinutes,
    required this.protocol,
    required this.calibrationKind,
    required this.calibrationPhases,
    required this.artifactCount,
    required this.guardrailWarningCount,
  });

  final String id;
  final File rawFile;
  final File computedFile;
  final File metadataFile;
  final int durationMinutes;
  final String protocol;
  final String calibrationKind;
  final List<String> calibrationPhases;
  final int artifactCount;
  final int guardrailWarningCount;

  /// Assemble the v5 session file from temp files and publish to history.
  Future<File?> saveSession(SessionStorage storage) async {
    final metadataJson = _buildMetadataJson();
    final thumbnailPng = await _generateThumbnail();

    // Read the three temp files
    final rawBytes = await rawFile.readAsBytes();
    final computedBytes = await computedFile.readAsBytes();

    // Parse computed frames
    final computedFrames = _parseComputedFrames(computedBytes);

    // Convert to FFI frames
    final ffiFrames = _toFfiFrames(computedFrames);

    // Assemble v5 container
    final v5Bytes = ffi.containerEncodeV5(
      thumbnail: thumbnailPng,
      metadataJson: utf8.encode(jsonEncode(metadataJson)),
      computedFrames: ffiFrames,
      rawBody: rawBytes,
    );

    // Write final file to history
    await storage.ensureDir();
    final historyDir = Directory(storage.location);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final finalPath = '${historyDir.path}/session_$ts.muse.feedback';
    final finalFile = File(finalPath);
    await finalFile.writeAsBytes(v5Bytes);

    // Clean up temp files
    await _cleanupTempFiles();

    return finalFile;
  }

  Future<void> discard() async {
    await _cleanupTempFiles();
  }

  Future<void> _cleanupTempFiles() async {
    for (final f in [rawFile, computedFile, metadataFile]) {
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  Map<String, dynamic> _buildMetadataJson() {
    return {
      'formatVersion': 5,
      'appVersion': '1.0.0+1',
      'savedAt': DateTime.now().toIso8601String(),
      'notes': '',
      'protocol': protocol,
      'durationMinutes': durationMinutes,
      'elapsedSeconds': durationMinutes * 60,
      'feedbackSound': 'bowlChimes',
      'metadataDescription': '',
      'device': {
        'name': 'Unknown',
        'id': 'Unknown',
        'firmware': 'Unknown',
        'model': 'Unknown',
        'sensors': ['EEG'],
        'channelCount': 4,
        'channelLabels': ['TP9', 'AF7', 'AF8', 'TP10'],
      },
      'calibration': {
        'version': 2,
        'kind': calibrationKind,
        'calibrationId': 'unknown',
        'calibrationStartSecs': null,
        'calibrationEndSecs': null,
        'trainingStartSecs': null,
        'usedStartAnyway': false,
        'greenStableSeconds': 3,
        'faultyPadSeconds': 20,
        'baseline': null,
        'phases': calibrationPhases.map((p) => {'clipId': p}).toList(),
        'recalibrations': [],
        'trainingStartOffsetSecs': null,
      },
      'streams': {
        'eeg': {'enabled': true, 'rateHz': 256},
        'bands': {'enabled': true, 'rateHz': 10},
        'pulse': {'enabled': true, 'rateHz': 1},
        'spo2': {'enabled': true, 'rateHz': 1},
        'movement': {'enabled': true, 'rateHz': 1},
        'peakAlpha': {'enabled': true, 'rateHz': 10},
        'imu': {'enabled': false, 'rateHz': 52},
        'ppg': {'enabled': false, 'rateHz': 64},
        'telemetry': {'enabled': false, 'rateHz': 1},
        'gestures': {'enabled': false, 'rateHz': 1},
      },
      'sessionSettings': {},
      'summary': null,
      'gestures': [],
      'drowsiness': {
        'scoreTotalPct': guardrailWarningCount > 0 ? 100.0 : 0.0,
        'meanSleepDir': 0.0,
        'threshold': null,
        'bucketWidthSecs': 0,
        'buckets': [],
      },
      'music': null,
      'modelSnapshot': null,
    };
  }

  List<ComputedFrame> _parseComputedFrames(Uint8List bytes) {
    if (bytes.isEmpty) return [];
    try {
      final frames = <ComputedFrame>[];
      for (final line in utf8.decode(bytes).split('\n')) {
        if (line.trim().isEmpty) continue;
        frames.add(ComputedFrame.fromJson(jsonDecode(line)));
      }
      return frames;
    } catch (e) {
      return [];
    }
  }

  List<ffi.ComputedFrame> _toFfiFrames(List<ComputedFrame> frames) {
    return frames.map(_toFfiFrame).toList();
  }

  ffi.ComputedFrame _toFfiFrame(ComputedFrame frame) {
    return ffi.ComputedFrame(
      t: frame.t,
      bands: frame.bands.map((b) => Float32List.fromList(b)).toList(),
      pulse: frame.pulse,
      movement: frame.movement,
      peakAlpha: frame.peakAlpha != null
          ? ffi.PeakAlphaInfo(freq: frame.peakAlpha!.freq, power: frame.peakAlpha!.power)
          : null,
      spo2: frame.spo2,
      lineNoise: Float32List.fromList(frame.lineNoise),
      signalQuality: Uint8List.fromList(frame.signalQuality),
      guardrail: ffi.GuardrailInfo(
        sleepDir: frame.guardrail.sleepDir,
        clarity: frame.guardrail.clarity,
        warning: frame.guardrail.warning,
        delta: frame.guardrail.delta,
      ),
      feedback: ffi.FeedbackInfo(
        ratio: frame.feedback.ratio,
        threshold: frame.feedback.threshold,
        inTarget: frame.feedback.inTarget,
        pct: frame.feedback.pct,
      ),
      gestures: frame.gestures,
    );
  }

  Future<Uint8List> _generateThumbnail() async {
    // Generate a simple placeholder thumbnail
    return Uint8List(0);
  }
}

/// Scans the cache directory for incomplete sessions (interrupted recordings).
Future<List<IncompleteSession>> scanIncompleteSessions() async {
  final cacheDir = Directory((await getTemporaryDirectory()).path);
  final sessionsDir = Directory('${cacheDir.path}/sessions');

  if (!await sessionsDir.exists()) {
    return [];
  }

  final sessions = <IncompleteSession>[];

  await for (final entity in sessionsDir.list()) {
    if (entity is Directory) {
      final dir = entity;
      final rawFile = File('${dir.path}/session_${dir.path.split('/').last}.raw');
      final computedFile = File('${dir.path}/session_${dir.path.split('/').last}.computed');
      final metadataFile = File('${dir.path}/session_${dir.path.split('/').last}.metadata');

      if (await rawFile.exists() &&
          await computedFile.exists() &&
          await metadataFile.exists()) {
        // Parse metadata file to get session info
        final metaLines = await metadataFile.readAsLines();
        String protocol = 'drowsiness';
        String calibrationKind = 'single';
        List<String> calibrationPhases = [];
        int artifactCount = 0;
        int guardrailWarningCount = 0;
        int durationMinutes = 0;

        for (final line in metaLines) {
          if (line.trim().isEmpty) continue;
          try {
            final meta = jsonDecode(line);
            if (meta['type'] == 'protocol') {
              protocol = meta['protocol'] ?? 'drowsiness';
            } else if (meta['type'] == 'calibration_start') {
              calibrationKind = meta['kind'] ?? 'single';
            } else if (meta['type'] == 'calibration_phase') {
              calibrationPhases.add(meta['clipId'] ?? '');
            } else if (meta['type'] == 'artifact') {
              artifactCount++;
            } else if (meta['type'] == 'guardrail_warning') {
              guardrailWarningCount++;
            } else if (meta['type'] == 'session_duration') {
              durationMinutes = (meta['minutes'] ?? 0) as int;
            }
          } catch (_) {}
        }

        final id = dir.path.split('/').last;
        sessions.add(IncompleteSession(
          id: id,
          rawFile: rawFile,
          computedFile: computedFile,
          metadataFile: metadataFile,
          durationMinutes: durationMinutes,
          protocol: protocol,
          calibrationKind: calibrationKind,
          calibrationPhases: calibrationPhases,
          artifactCount: artifactCount,
          guardrailWarningCount: guardrailWarningCount,
        ));
      }
    }
  }

  return sessions;
}

/// Shows a blocking modal dialog for incomplete sessions found at startup.
/// User MUST choose Save or Discard before continuing.
Future<void> showCrashRecoveryDialog(BuildContext context, WidgetRef ref) async {
  final incompleteSessions = await scanIncompleteSessions();

  if (incompleteSessions.isEmpty) return;

  for (final session in incompleteSessions) {
    if (!context.mounted) return;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false, // BLOCKING - cannot dismiss
      builder: (context) => _CrashRecoveryDialog(session: session),
    ).then((shouldSave) async {
      if (shouldSave == true) {
        final storage = await ref.read(sessionStorageProvider.future);
        await session.saveSession(storage);
      } else {
        await session.discard();
      }
    });
  }
}

class _CrashRecoveryDialog extends ConsumerWidget {
  const _CrashRecoveryDialog({required this.session});

  final IncompleteSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false, // Prevent back button dismiss
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
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              _InfoRow(label: 'Session', value: session.id),
              _InfoRow(label: 'Protocol', value: session.protocol),
              _InfoRow(label: 'Duration', value: '${session.durationMinutes} min'),
              _InfoRow(label: 'Calibration', value: session.calibrationKind),
              _InfoRow(label: 'Phases', value: session.calibrationPhases.join(', ')),
              _InfoRow(label: 'Artifacts detected', value: session.artifactCount.toString()),
              _InfoRow(label: 'Guardrail warnings', value: session.guardrailWarningCount.toString()),
              const SizedBox(height: 16),
              const Text(
                'Choose what to do:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
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