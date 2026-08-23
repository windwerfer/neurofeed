import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:muse_ml/src/feedback/computed_frame.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/rust/api/session_format.dart' as ffi;
import 'package:muse_ml/src/settings.dart';

/// v5 SessionRecorder — writes three uncompressed temp files during recording:
/// - raw: raw event bytes (uncompressed .muse body format)
/// - computed: JSON Lines (one ComputedFrame per line)
/// - metadata: JSON Lines (metadata events: calibration, guardrail, etc.)
///
/// On [finalize], generates a WebP thumbnail and assembles the v5 container
/// via Rust FFI: [68-byte header][WebP thumbnail][metadata(zstd)][computed(zstd)][raw(zstd)]
class SessionRecorder {
  static const _flushInterval = Duration(seconds: 30);
  static const _maxPendingBytes = 65536;

  // Three temp files for v5 sections
  File? _rawFile;
  File? _computedFile;
  File? _metadataFile;

  // Pending bytes buffer for raw events (before flush to disk)
  final _rawPending = BytesBuilder();
  int _rawEvents = 0;
  int _computedFrames = 0;

  /// Streams to persist. Defaults to all.
  Set<RecordingStream> recordStreams = RecordingStream.values.toSet();

  /// Electrode indices that produced data during this recording.
  final Set<int> channels = <int>{};

  bool _enabled(RecordingStream s) => recordStreams.contains(s);

  bool get isRecording => _rawFile != null;

  String? get currentFilePath => _rawFile?.path;

  /// Directory where temp files are being written.
  Directory? get tempDir => _rawFile?.parent;

  /// Start a new session recording in [dir] (scratch directory).
  /// Creates three temp files: raw, computed, metadata
  Future<void> start(Directory dir) async {
    if (_rawFile != null) return;

    final ts = DateTime.now().millisecondsSinceEpoch;
    final base = '${dir.path}/session_$ts';

    _rawFile = File('$base.raw');
    _computedFile = File('$base.computed');
    _metadataFile = File('$base.metadata');

    _rawEvents = 0;
    _computedFrames = 0;
    channels.clear();

    // Write the .muse body header (magic + version)
await _rawFile!.writeAsBytes(ffi.sessionHeaderBytes(),
        mode: FileMode.write);

    debugPrint('[session] recorder v5 start: $_rawFile, $_computedFile, $_metadataFile');

    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
  }

  Timer? _flushTimer;

  /// Write a Muse event to the raw file (uncompressed).
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

    // Track electrode channels
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
    final line = jsonEncode(meta) + '\n';
    _metadataFile!.writeAsStringSync(line, mode: FileMode.append);
  }

  /// Add a computed frame (1 Hz) to the computed file.
  void appendComputed(ComputedFrame frame) {
    if (_computedFile == null) return;
    _computedFrames++;
    final line = frame.toJsonBytes();
    _computedFile!.writeAsBytesSync(line, mode: FileMode.append);
    _computedFile!.writeAsBytesSync([0x0A], mode: FileMode.append); // newline
  }

  /// Flush raw pending bytes to disk.
  void flushRaw() {
    if (_rawPending.isEmpty || _rawFile == null) return;
    final raw = _rawPending.toBytes();
    _rawPending.clear();
    _rawFile!.writeAsBytesSync(raw, mode: FileMode.append);
  }

  /// Flush all to disk.
  Future<void> flush() async {
    flushRaw();
  }

  /// Finalize the session: flush all, generate thumbnail, assemble v5 container.
  /// Returns the final session file, or null if no recording was active.
  Future<File?> finalize({
    required Uint8List thumbnailPng,
    required Map<String, dynamic> metadataJson,
  }) async {
    await flush();

    _flushTimer?.cancel();
    _flushTimer = null;

    if (_rawFile == null) {
      debugPrint('[session] finalize: no active recording');
      return null;
    }

    // Read the three temp files
    final rawBytes = await _rawFile!.readAsBytes();
    final computedBytes = await _computedFile!.readAsBytes();
    final metadataBytes = await _metadataFile!.readAsBytes();

    // Convert thumbnail PNG to WebP (640x360, lossy quality 75)
    final thumbnailWebP = _encodeThumbnailWebP(thumbnailPng);

    // Encode metadata JSON to bytes
    final metadataJsonBytes = utf8.encode(jsonEncode(metadataJson));

    // Parse computed frames from computed file (JSON Lines)
    final computedFrames = _parseComputedFrames(computedBytes);

    // Convert to FFI ComputedFrame for encoding
    final ffiFrames = _toFfiFrames(computedFrames);

    // Assemble v5 container using Rust FFI
    final v5Bytes = ffi.containerEncodeV5(
      thumbnail: thumbnailWebP,
      metadataJson: metadataJsonBytes,
      computedFrames: ffiFrames,
      rawBody: rawBytes,
    );

    // Write final v5 file to history location
    final historyDir = _rawFile!.parent;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final finalPath = '${historyDir.path}/session_$ts.muse.feedback';
    final finalFile = File(finalPath);
    await finalFile.writeAsBytes(v5Bytes);

    debugPrint('[session] finalize: wrote v5 session to $finalPath '
        '(raw=${rawBytes.length}B, computed=${computedBytes.length}B, '
        'metadata=${metadataBytes.length}B, thumb=${thumbnailWebP.length}B)');

    // Clean up temp files
    await _cleanupTempFiles();

    return finalFile;
  }

  /// Convert PNG bytes to WebP (640x360).
  Uint8List _encodeThumbnailWebP(Uint8List pngBytes) {
    final image = img.decodeImage(pngBytes);
    if (image == null) {
      debugPrint('[session] thumbnail: failed to decode PNG, using empty');
      return Uint8List(0);
    }
    final resized = img.copyResize(image, width: 640, height: 360);
    // image package v4: encodeWebP takes (image) without quality parameter
    final webpBytes = img.encodeWebP(resized);
    return Uint8List.fromList(webpBytes);
  }

  /// Parse computed frames from JSON Lines.
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
      debugPrint('[session] failed to parse computed frames: $e');
      return [];
    }
  }

  /// Clean up temp files after successful assembly.
  Future<void> _cleanupTempFiles() async {
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
    debugPrint('[session] stop(): rawEvents=$_rawEvents, computedFrames=$_computedFrames');
    _flushTimer?.cancel();
    _flushTimer = null;
    await _cleanupTempFiles();
  }

  /// Get the collected computed frames (not available in v5 until finalize reads from disk).
  List<ComputedFrame> get computedFrames => const [];

  /// Clear computed frames (no-op in v5).
  void clearComputedFrames() {}

  /// Convert internal ComputedFrame list to FFI ComputedFrame list for encoding.
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
}