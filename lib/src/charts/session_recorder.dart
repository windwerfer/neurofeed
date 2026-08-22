import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';
import 'package:muse_ml/src/settings.dart';

class SessionRecorder {
  static const _flushInterval = Duration(seconds: 30);
  static const _maxPendingBytes = 65536;

  File? _file;
  Timer? _flushTimer;
  final _pending = BytesBuilder();
  int _events = 0;

  /// Streams to persist. Defaults to all — callers that want a subset (e.g.
  /// the user turned off raw EEG in settings) assign `recordStreams` before
  /// [start]. Streams map to event tags so the file stays self-describing
  /// regardless of what is enabled.
  Set<RecordingStream> recordStreams = RecordingStream.values.toSet();

  /// Electrode indices that produced data during this recording. Used by the
  /// session metadata so a file records which channels it contains — works for
  /// any channel count (Muse 4ch, future 8ch Crown).
  final Set<int> channels = <int>{};

  bool _enabled(RecordingStream s) => recordStreams.contains(s);

  bool get isRecording => _file != null;

  String? get currentFilePath => _file?.path;

  Future<void> start([Directory? dir]) async {
    if (_file != null) return;
    final d = dir ?? Directory.systemTemp;
    final sep = d.path.endsWith('/') ? '' : '/';
    final path = '${d.path}${sep}live_${DateTime.now().millisecondsSinceEpoch}.muse.feedback';
    _file = File(path);
    _events = 0;
    debugPrint('[session] recorder start: $path');

    await _file!.writeAsBytes(sessionHeaderBytes(),
        mode: FileMode.writeOnlyAppend);

    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
  }

  void writeEvent(MuseEventDto event) {
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
    // Only EEG/bands carry the electrode channel info, so track it here
    // (encodeSessionEvent records the raw payload but no channel set).
    switch (event) {
      case MuseEventDto_Eeg():
        channels.add(event.field0.electrode);
      case MuseEventDto_Bands():
        channels.add(event.field0.electrode);
      default:
        break;
    }
    final encoded = encodeSessionEvent(event: event);
    if (encoded.isEmpty) return;
    _events++;
    _pending.add(encoded);
    if (_pending.length > _maxPendingBytes) flush();
  }

  Future<File?> markSaved() async {
    await flush();
    if (_file == null) {
      debugPrint('[session] markSaved: no active file, returning null');
      return null;
    }
    final dir = _file!.parent;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final newPath = '${dir.path}/session_$ts.muse.feedback';
    debugPrint('[session] markSaved: renaming ${_file!.path} -> $newPath');
    try {
      final saved = await _file!.rename(newPath);
      _file = null;
      debugPrint('[session] markSaved: OK -> ${saved.path}');
      return saved;
    } catch (e) {
      debugPrint('[session] markSaved: rename FAILED ($e)');
      rethrow;
    }
  }

  Future<void> stop() async {
    debugPrint('[session] stop(): events=$_events');
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
    if (_file != null) {
      try {
        await _file!.delete();
        debugPrint('[session] stop(): deleted temp file');
      } catch (e) {
        debugPrint('[session] stop(): delete failed ($e)');
      }
      _file = null;
    }
  }

  Future<void> flush() async {
    if (_pending.isEmpty || _file == null) return;
    final raw = _pending.toBytes();
    _pending.clear();
    try {
      final frame = sessionFrameBytes(data: raw);
      await _file!.writeAsBytes(frame, mode: FileMode.writeOnlyAppend);
    } catch (e) {
      debugPrint('[session] flush FAILED, re-queueing ($e)');
      _pending.add(raw);
    }
  }
}
