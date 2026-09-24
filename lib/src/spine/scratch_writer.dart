import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/session_v5/computed_frame.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/spine/capture_client.dart' as spine;

enum SidecarMode { jsonl, snapshot }

/// v5 scratch writer. Production uses the Rust capture writer. Inject
/// [headerBytes] to keep a local Dart writer (unit tests without FFI).
///
/// Live temps:
/// - raw: v5 raw body (NFEDBIN + inner zstd frames)
/// - computed: uncompressed JSON Lines
/// - sidecar: uncompressed JSONL `.metadata` (feedback) or atomic `.json`
class SessionRecorder {
  SessionRecorder({List<int> Function()? headerBytes})
    : _useRust = headerBytes == null,
      _headerBytes = headerBytes;

  static const _flushInterval = Duration(seconds: 30);

  final bool _useRust;
  final List<int> Function()? _headerBytes;

  File? _rawFile;
  File? _computedFile;
  File? _metadataFile;
  String? _sessionId;
  SidecarMode _sidecar = SidecarMode.jsonl;

  int _rawEvents = 0;
  int _computedFrames = 0;
  Timer? _flushTimer;

  /// Called after a frame is appended, with `_rawFile.lengthSync()`.
  void Function(int fileLength)? onRawFlushed;

  /// Streams to persist. Defaults to all.
  Set<RecordingStream> recordStreams = RecordingStream.values.toSet();

  /// Electrode indices that produced data during this recording.
  final Set<int> channels = <int>{};

  bool _enabled(RecordingStream s) => recordStreams.contains(s);

  bool get usesRustCapture => _useRust;

  bool get isRecording => _rawFile != null;

  /// Timestamp id used in `${prefix}_<id>.raw` / `.neurofeed`.
  String? get sessionId => _sessionId;

  String? get currentFilePath => _rawFile?.path;

  String? get rawPath => _rawFile?.path;

  String? get computedPath => _computedFile?.path;

  /// Directory where temp files are being written.
  Directory? get tempDir => _rawFile?.parent;

  /// Start a new session recording in [dir] (scratch directory).
  /// Creates raw + computed temps and a sidecar (`.metadata` JSONL or `.json`
  /// snapshot). [prefix] defaults to `session` so the base path is
  /// `$dir/${prefix}_$ts`.
  Future<void> start(
    Directory dir, {
    String prefix = 'session',
    String? id,
    SidecarMode sidecar = SidecarMode.jsonl,
    int? startedAtMs,
  }) async {
    if (_rawFile != null) return;

    final ts = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    _sessionId = ts;
    _sidecar = sidecar;
    final base = '${dir.path}/${prefix}_$ts';

    _rawFile = File('$base.raw');
    _computedFile = File('$base.computed');
    _metadataFile = sidecar == SidecarMode.snapshot
        ? File('$base.json')
        : File('$base.metadata');

    _rawEvents = 0;
    _computedFrames = 0;
    channels.clear();

    if (_useRust) {
      try {
        await spine.startCapture(
          dir: dir,
          prefix: prefix,
          id: ts,
          streams: recordStreams,
          startedAtMs: startedAtMs ?? DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {
        _rawFile = null;
        _computedFile = null;
        _metadataFile = null;
        _sessionId = null;
        rethrow;
      }
    } else {
      await _rawFile!.writeAsBytes(_headerBytes!(), mode: FileMode.write);
      await _computedFile!.writeAsBytes(const <int>[], mode: FileMode.write);
    }

    debugPrint(
      '[session] recorder v5 start: $_rawFile, $_computedFile, $_metadataFile',
    );

    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
  }

  /// Atomically overwrite the snapshot sidecar (`prefix_$id.json.tmp` then
  /// rename onto `prefix_$id.json`). No-op in JSONL mode.
  Future<void> writeSidecarSnapshot(Map<String, Object?> json) async {
    if (_sidecar != SidecarMode.snapshot || _metadataFile == null) return;
    if (_useRust) {
      spine.captureWriteSidecar(json: spine.metadataJsonBytes(json));
      return;
    }
    final target = _metadataFile!;
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(utf8.encode(jsonEncode(json)), flush: true);
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) {
        await target.delete();
      }
      await tmp.rename(target.path);
    }
  }

  /// Test injector. Live EEG is forked in Rust; production does not call this.
  void writeEvent(MuseEventDto event) {
    if (_rawFile == null || !_useRust) return;

    final enabled = switch (event) {
      MuseEventDto_Eeg() => _enabled(RecordingStream.eeg),
      MuseEventDto_Telemetry() => _enabled(RecordingStream.telemetry),
      MuseEventDto_Accelerometer() ||
      MuseEventDto_Gyroscope() => _enabled(RecordingStream.imu),
      MuseEventDto_Ppg() => _enabled(RecordingStream.ppg),
      MuseEventDto_Bands() => _enabled(RecordingStream.bands),
      MuseEventDto_Pulse() => _enabled(RecordingStream.pulse),
      MuseEventDto_SpO2() => _enabled(RecordingStream.spo2),
      MuseEventDto_Movement() => _enabled(RecordingStream.movement),
      MuseEventDto_PeakAlpha() => _enabled(RecordingStream.peakAlpha),
      _ => false,
    };
    if (!enabled) return;

    switch (event) {
      case MuseEventDto_Eeg():
        channels.add(event.field0.electrode);
      case MuseEventDto_Bands():
        channels.add(event.field0.electrode);
      default:
        break;
    }

    spine.captureAppendEvent(event: event);
    _rawEvents++;
  }

  /// Pause/resume the Rust raw fork (no samples written while paused).
  void setRawPaused(bool paused) {
    if (!_useRust || _rawFile == null) return;
    spine.captureWriteSidecar(
      json: utf8.encode(jsonEncode({'type': '__capture_pause', 'paused': paused})),
    );
  }

  /// Write a metadata event (calibration step, guardrail event, etc.) as JSON line.
  void writeMetadata(Map<String, dynamic> meta) {
    if (_metadataFile == null) return;
    if (_useRust) {
      spine.captureWriteSidecar(json: utf8.encode(jsonEncode(meta)));
      return;
    }
    final line = '${jsonEncode(meta)}\n';
    _metadataFile!.writeAsStringSync(line, mode: FileMode.append);
  }

  /// Add a computed frame (1 Hz) to the computed file.
  void appendComputed(ComputedFrame frame) {
    if (_computedFile == null) return;
    _computedFrames++;
    if (_useRust) {
      spine.captureAppendComputedLine(line: frame.toJsonBytes());
      return;
    }
    final line = frame.toJsonBytes();
    _computedFile!.writeAsBytesSync(line, mode: FileMode.append);
    _computedFile!.writeAsBytesSync([0x0A], mode: FileMode.append);
  }

  Future<void> flushRaw() async {
    if (!_useRust || _rawFile == null) return;
    await spine.captureFlush();
    if (_rawFile!.existsSync()) {
      onRawFlushed?.call(_rawFile!.lengthSync());
    }
  }

  /// Flush all to disk.
  Future<void> flush() async {
    await flushRaw();
  }

  void stopPeriodicFlush() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// Read the three temp files after a flush. Does not delete them.
  Future<({Uint8List raw, Uint8List computed, Uint8List metadata})?>
  readTemps() async {
    if (_rawFile == null) return null;
    final raw = await _rawFile!.readAsBytes();
    final computed = (_computedFile != null && await _computedFile!.exists())
        ? await _computedFile!.readAsBytes()
        : Uint8List(0);
    final metadata = (_metadataFile != null && await _metadataFile!.exists())
        ? await _metadataFile!.readAsBytes()
        : Uint8List(0);
    return (raw: raw, computed: computed, metadata: metadata);
  }

  /// Drop local file handles after Rust assemble deleted the temps.
  void detachAfterAssemble() {
    stopPeriodicFlush();
    _rawFile = null;
    _computedFile = null;
    _metadataFile = null;
  }

  /// Clean up temp files after a successful assemble. Keeps [sessionId].
  Future<void> cleanupTempFiles() async {
    stopPeriodicFlush();
    if (_useRust) {
      await spine.captureDiscard();
      detachAfterAssemble();
      return;
    }
    final sidecarTmp = _metadataFile != null && _sidecar == SidecarMode.snapshot
        ? File('${_metadataFile!.path}.tmp')
        : null;
    for (final f in [_rawFile, _computedFile, _metadataFile, sidecarTmp]) {
      if (f != null && await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    _rawFile = null;
    _computedFile = null;
    _metadataFile = null;
  }

  /// Stop recording and delete temp files (discard session).
  Future<void> stop() async {
    debugPrint(
      '[session] stop(): rawEvents=$_rawEvents, computedFrames=$_computedFrames',
    );
    await cleanupTempFiles();
    _sessionId = null;
  }

  /// Get the collected computed frames (not available in v5 until assemble reads from disk).
  List<ComputedFrame> get computedFrames => const [];

  /// Clear computed frames (no-op in v5).
  void clearComputedFrames() {}
}
