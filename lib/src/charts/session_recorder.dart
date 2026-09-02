import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/feedback/computed_frame.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/rust/api/session_format.dart' as ffi;
import 'package:muse_ml/src/settings.dart';

/// v5 SessionRecorder — writes three uncompressed temp files during recording:
/// - raw: framed `.muse` body (`sessionHeaderBytes` + `sessionFrameBytes`)
/// - computed: JSON Lines (one Dart ComputedFrame per line)
/// - metadata: JSON Lines (calibration, guardrail, etc.)
///
/// Does not assemble the v5 container. Callers flush, read temps, and pass
/// bytes to [assembleV5Container].
class SessionRecorder {
  static const _flushInterval = Duration(seconds: 30);
  static const _maxPendingBytes = 65536;

  File? _rawFile;
  File? _computedFile;
  File? _metadataFile;
  String? _sessionId;

  final _rawPending = BytesBuilder();
  int _rawEvents = 0;
  int _computedFrames = 0;
  Timer? _flushTimer;

  /// Streams to persist. Defaults to all.
  Set<RecordingStream> recordStreams = RecordingStream.values.toSet();

  /// Electrode indices that produced data during this recording.
  final Set<int> channels = <int>{};

  bool _enabled(RecordingStream s) => recordStreams.contains(s);

  bool get isRecording => _rawFile != null;

  /// Timestamp id used in `session_<id>.raw` / `.muse.feedback`.
  String? get sessionId => _sessionId;

  String? get currentFilePath => _rawFile?.path;

  /// Directory where temp files are being written.
  Directory? get tempDir => _rawFile?.parent;

  /// Start a new session recording in [dir] (scratch directory).
  /// Creates three temp files: raw, computed, metadata
  Future<void> start(Directory dir) async {
    if (_rawFile != null) return;

    final ts = DateTime.now().millisecondsSinceEpoch;
    _sessionId = ts.toString();
    final base = '${dir.path}/session_$ts';

    _rawFile = File('$base.raw');
    _computedFile = File('$base.computed');
    _metadataFile = File('$base.metadata');

    _rawEvents = 0;
    _computedFrames = 0;
    channels.clear();

    await _rawFile!.writeAsBytes(ffi.sessionHeaderBytes(), mode: FileMode.write);

    debugPrint(
      '[session] recorder v5 start: $_rawFile, $_computedFile, $_metadataFile',
    );

    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
  }

  /// Write a Muse event to the raw file (uncompressed records, framed on flush).
  void writeEvent(MuseEventDto event) {
    if (_rawFile == null) return;

    final enabled = switch (event) {
      MuseEventDto_Eeg() => _enabled(RecordingStream.eeg),
      MuseEventDto_Telemetry() => _enabled(RecordingStream.telemetry),
      MuseEventDto_Accelerometer() || MuseEventDto_Gyroscope() =>
        _enabled(RecordingStream.imu),
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

    final encoded = ffi.encodeSessionEvent(event: event);
    if (encoded.isEmpty) return;

    _rawEvents++;
    _rawPending.add(encoded);
    if (_rawPending.length > _maxPendingBytes) flushRaw();
  }

  /// Write a metadata event (calibration step, guardrail event, etc.) as JSON line.
  void writeMetadata(Map<String, dynamic> meta) {
    if (_metadataFile == null) return;
    final line = '${jsonEncode(meta)}\n';
    _metadataFile!.writeAsStringSync(line, mode: FileMode.append);
  }

  /// Add a computed frame (1 Hz) to the computed file.
  void appendComputed(ComputedFrame frame) {
    if (_computedFile == null) return;
    _computedFrames++;
    final line = frame.toJsonBytes();
    _computedFile!.writeAsBytesSync(line, mode: FileMode.append);
    _computedFile!.writeAsBytesSync([0x0A], mode: FileMode.append);
  }

  /// Flush raw pending bytes as one `sessionFrameBytes` frame.
  void flushRaw() {
    if (_rawPending.isEmpty || _rawFile == null) return;
    final raw = _rawPending.toBytes();
    _rawPending.clear();
    final framed = ffi.sessionFrameBytes(data: raw);
    _rawFile!.writeAsBytesSync(framed, mode: FileMode.append);
  }

  /// Flush all to disk.
  Future<void> flush() async {
    flushRaw();
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

  /// Clean up temp files after a successful assemble. Keeps [sessionId].
  Future<void> cleanupTempFiles() async {
    stopPeriodicFlush();
    for (final f in [_rawFile, _computedFile, _metadataFile]) {
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
