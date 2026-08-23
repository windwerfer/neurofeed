/// Session metadata classes for v5 format.
/// Uses manual JSON serialization to avoid freezed nested class limitations.

import 'session_v5_models.dart';

/// Snapshot of the guardrail AI model at session time (v5).
/// Critical for reproducibility when fine-tuning foundation models.
class ModelSnapshot {
  const ModelSnapshot({
    required this.engine,
    this.weightsSha256,
    this.configJson,
    this.repoRevision,
    required this.loadedAt,
  });

  /// Engine name: `bandMath`, `lunaBase`, `lunaLarge`, `reveBase`, or `none`.
  final String engine;

  /// SHA-256 of the model.safetensors weights file.
  final String? weightsSha256.

  /// Full model config JSON (from model_config_json() FFI).
  final Map<String, Object?>? configJson.

  /// Git tag/rev of the model repo (e.g., `v0.0.4-latent-embedding-fix`).
  final String? repoRevision.

  /// ISO8601 timestamp when model was loaded for this session.
  final DateTime loadedAt.

  Map<String, Object?> toJson() => {
    'engine': engine,
    if (weightsSha256 != null) 'weightsSha256': weightsSha256,
    if (configJson != null) 'configJson': configJson,
    if (repoRevision != null) 'repoRevision': repoRevision,
    'loadedAt': loadedAt.toIso8601String(),
  }

  static ModelSnapshot? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null
    final engine = json['engine'] as String?;
    if (engine == null) return null
    return ModelSnapshot(
      engine: engine,
      weightsSha256: json['weightsSha256'] as String?,
      configJson: json['configJson'] as Map<String, Object?>?,
      repoRevision: json['repoRevision'] as String?,
      loadedAt: DateTime.tryParse(json['loadedAt'] as String?) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    )
  }
}

/// Full device information (v5). Supersedes deviceName/deviceModel/deviceId.
class DeviceInfoV5 {
  const DeviceInfoV5({
    required this.name,
    required this.id,
    required this.firmware,
    required this.model,
    required this.sensors,
    required this.channelCount,
    required this.channelLabels,
  })

  final String name
  final String id
  final String firmware
  final String model
  final List<String> sensors
  final int channelCount
  final List<String> channelLabels

  Map<String, Object?> toJson() => {
    'name': name,
    'id': id,
    'firmware': firmware,
    'model': model,
    'sensors': sensors,
    'channelCount': channelCount,
    'channelLabels': channelLabels,
  }

  static DeviceInfoV5? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null
    return DeviceInfoV5(
      name: json['name'] as String? ?? '',
      id: json['id'] as String? ?? '',
      firmware: json['firmware'] as String? ?? '',
      model: json['model'] as String? ?? '',
      sensors: (json['sensors'] as List?)?.map((e) => e as String).toList() ?? [],
      channelCount: (json['channelCount'] as num?)?.toInt() ?? 4,
      channelLabels: (json['channelLabels'] as List?)?.map((e) => e as String).toList() ?? [],
    )
  }
}

/// Individual stream info: enabled + rate.
/// Uses manual JSON serialization to avoid freezed nested class limitations.
class StreamInfo {
  const StreamInfo({
    required this.enabled,
    required this.rateHz,
    this.electrodes,
    this.channels,
    this.sensors,
  })

  final bool enabled
  final int rateHz
  final List<int>? electrodes
  final List<String>? channels
  final List<String>? sensors

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'rateHz': rateHz,
    if (electrodes != null) 'electrodes': electrodes,
    if (channels != null) 'channels': channels,
    if (sensors != null) 'sensors': sensors,
  }

  static StreamInfo? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null
    return StreamInfo(
      enabled: json['enabled'] as bool? ?? false,
      rateHz: (json['rateHz'] as num?)?.toInt() ?? 0,
      electrodes: (json['electrodes'] as List?)?.map((e) => e as int).toList(),
      channels: (json['channels'] as List?)?.map((e) => e as String).toList(),
      sensors: (json['sensors'] as List?)?.map((e) => e as String).toList(),
    )
  }
}

/// Stream configuration: what was recorded and at what rate (v5).
/// Uses manual JSON serialization to avoid freezed nested class limitations.
class StreamsConfig {
  const StreamsConfig({
    required this.eeg,
    required this.bands,
    required this.pulse,
    required this.spo2,
    required this.movement,
    required this.peakAlpha,
    required this.imu,
    required this.ppg,
    required this.telemetry,
    required this.gestures,
  })

  final StreamInfo eeg
  final StreamInfo bands
  final StreamInfo pulse
  final StreamInfo spo2
  final StreamInfo movement
  final StreamInfo peakAlpha
  final StreamInfo imu
  final StreamInfo ppg
  final StreamInfo telemetry
  final StreamInfo gestures

  Map<String, dynamic> toJson() => {
    'eeg': eeg.toJson(),
    'bands': bands.toJson(),
    'pulse': pulse.toJson(),
    'spo2': spo2.toJson(),
    'movement': movement.toJson(),
    'peakAlpha': peakAlpha.toJson(),
    'imu': imu.toJson(),
    'ppg': ppg.toJson(),
    'telemetry': telemetry.toJson(),
    'gestures': gestures.toJson(),
  }

  static StreamsConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null
    return StreamsConfig(
      eeg: StreamInfo.fromJson(json['eeg'] as Map<String, dynamic>?)!,
      bands: StreamInfo.fromJson(json['bands'] as Map<String, dynamic>?)!,
      pulse: StreamInfo.fromJson(json['pulse'] as Map<String, dynamic>?)!,
      spo2: StreamInfo.fromJson(json['spo2'] as Map<String, dynamic>?)!,
      movement: StreamInfo.fromJson(json['movement'] as Map<String, dynamic>?)!,
      peakAlpha: StreamInfo.fromJson(json['peakAlpha'] as Map<String, dynamic>?)!,
      imu: StreamInfo.fromJson(json['imu'] as Map<String, dynamic>?)!,
      ppg: StreamInfo.fromJson(json['ppg'] as Map<String, dynamic>?)!,
      telemetry: StreamInfo.fromJson(json['telemetry'] as Map<String, dynamic>?)!,
      gestures: StreamInfo.fromJson(json['gestures'] as Map<String, dynamic>?)!,
    )
  }
}