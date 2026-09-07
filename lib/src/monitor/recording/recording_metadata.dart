import 'package:muse_ml/src/session_v5/models.dart';
import 'package:muse_ml/src/settings.dart';

/// Snapshot sidecar for monitor tmp / recording captures. Not [SessionMetadata].
class RecordingMetadata {
  const RecordingMetadata({
    required this.formatVersion,
    required this.appVersion,
    required this.kind,
    required this.savedAt,
    required this.startedAt,
    required this.elapsedSeconds,
    required this.durationS,
    this.notes = '',
    required this.device,
    required this.streams,
  });

  final int formatVersion;
  final String appVersion;
  final String kind;
  final DateTime savedAt;
  final DateTime startedAt;
  final int elapsedSeconds;
  final int durationS;
  final String notes;
  final DeviceInfoV5 device;
  final StreamsConfig streams;

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'appVersion': appVersion,
    'kind': kind,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'startedAt': startedAt.toUtc().toIso8601String(),
    'elapsedSeconds': elapsedSeconds,
    'durationS': durationS,
    'notes': notes,
    'device': device.toJson(),
    'streams': streams.toJson(),
  };

  static RecordingMetadata fromJson(Map<String, dynamic> json) {
    return RecordingMetadata(
      formatVersion: (json['formatVersion'] as num?)?.toInt() ?? 5,
      appVersion: json['appVersion'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      startedAt:
          DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
      durationS: (json['durationS'] as num?)?.toInt() ?? 0,
      notes: json['notes'] as String? ?? '',
      device: DeviceInfoV5.fromJson(json['device'] as Map<String, dynamic>?)!,
      streams: StreamsConfig.fromJson(
        json['streams'] as Map<String, dynamic>?,
      )!,
    );
  }

  static StreamInfo _info(
    Set<RecordingStream> enabled,
    RecordingStream s,
    int rateHz,
  ) {
    final on = enabled.contains(s);
    return StreamInfo(enabled: on, rateHz: on ? rateHz : 0);
  }

  /// Complete ten-key [StreamsConfig]. Disabled streams are present with
  /// `enabled: false`, `rateHz: 0`. Gestures are not a [RecordingStream].
  static StreamsConfig streamsConfig(Set<RecordingStream> enabled) {
    return StreamsConfig(
      eeg: _info(enabled, RecordingStream.eeg, 256),
      bands: _info(enabled, RecordingStream.bands, 1),
      pulse: _info(enabled, RecordingStream.pulse, 1),
      spo2: _info(enabled, RecordingStream.spo2, 1),
      movement: _info(enabled, RecordingStream.movement, 1),
      peakAlpha: _info(enabled, RecordingStream.peakAlpha, 1),
      imu: _info(enabled, RecordingStream.imu, 52),
      ppg: _info(enabled, RecordingStream.ppg, 64),
      telemetry: _info(enabled, RecordingStream.telemetry, 1),
      gestures: const StreamInfo(enabled: false, rateHz: 0),
    );
  }
}
