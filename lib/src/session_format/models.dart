/// Snapshot of the guardrail AI model at session time.
class ModelSnapshot {
  const ModelSnapshot({
    required this.engine,
    this.weightsSha256,
    this.configJson,
    this.repoRevision,
    required this.loadedAt,
  });

  final String engine;
  final String? weightsSha256;
  final Map<String, Object?>? configJson;
  final String? repoRevision;
  final DateTime loadedAt;

  Map<String, Object?> toJson() => {
    'engine': engine,
    if (weightsSha256 != null) 'weightsSha256': weightsSha256,
    if (configJson != null) 'configJson': configJson,
    if (repoRevision != null) 'repoRevision': repoRevision,
    'loadedAt': loadedAt.toIso8601String(),
  };

  static ModelSnapshot? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final engine = json['engine'] as String?;
    if (engine == null) return null;
    return ModelSnapshot(
      engine: engine,
      weightsSha256: json['weightsSha256'] as String?,
      configJson: json['configJson'] as Map<String, Object?>?,
      repoRevision: json['repoRevision'] as String?,
      loadedAt: DateTime.tryParse(json['loadedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Full device information (NFED6 container metadata).
class DeviceInfo {
  const DeviceInfo({
    required this.name,
    required this.id,
    required this.firmware,
    required this.model,
    required this.sensors,
    required this.channelCount,
    required this.channelLabels,
    this.rawFiltering,
    this.conditioning,
  });

  final String name;
  final String id;
  final String firmware;
  final String model;
  final List<String> sensors;
  final int channelCount;
  final List<String> channelLabels;

  /// How the stored RAW was filtered (live recordings: stored as received,
  /// no device-side filtering).
  final RawFiltering? rawFiltering;

  /// App conditioning under computed values and charts.
  final SignalConditioning? conditioning;

  Map<String, Object?> toJson() => {
    'name': name,
    'id': id,
    'firmware': firmware,
    'model': model,
    'sensors': sensors,
    'channelCount': channelCount,
    'channelLabels': channelLabels,
    if (rawFiltering != null) 'rawFiltering': rawFiltering!.toJson(),
    if (conditioning != null) 'conditioning': conditioning!.toJson(),
  };

  static DeviceInfo? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return DeviceInfo(
      name: json['name'] as String? ?? '',
      id: json['id'] as String? ?? '',
      firmware: json['firmware'] as String? ?? '',
      model: json['model'] as String? ?? '',
      sensors: (json['sensors'] as List?)?.map((e) => e as String).toList() ?? [],
      channelCount: (json['channelCount'] as num?)?.toInt() ?? 4,
      channelLabels: (json['channelLabels'] as List?)?.map((e) => e as String).toList() ?? [],
      rawFiltering: RawFiltering.fromJson(json['rawFiltering']),
      conditioning: SignalConditioning.fromJson(json['conditioning']),
    );
  }
}

/// `device.rawFiltering`: the stored RAW is the device output as received
/// (`storedAsReceived`, the app never filters it); `highPassHz` / `notchHz`
/// are filters the device itself applied, null = none.
class RawFiltering {
  const RawFiltering({
    this.storedAsReceived = true,
    this.highPassHz,
    this.notchHz,
  });

  /// Unfiltered live device output (Muse Classic / Athena, Crown).
  static const deviceUnfiltered = RawFiltering();

  /// EDF Prefiltering header text, e.g. `HP:DC N:none` (no high-pass, no
  /// notch; a low-pass is not stated because none is documented).
  String get edfPrefiltering {
    String hz(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
    final hp = highPassHz == null ? 'HP:DC' : 'HP:${hz(highPassHz!)}Hz';
    final n = notchHz == null ? 'N:none' : 'N:${hz(notchHz!)}Hz';
    return '$hp $n';
  }

  final bool storedAsReceived;
  final double? highPassHz;
  final double? notchHz;

  Map<String, Object?> toJson() => {
    'storedAsReceived': storedAsReceived,
    'highPassHz': highPassHz,
    'notchHz': notchHz,
  };

  static RawFiltering? fromJson(Object? json) {
    if (json is! Map) return null;
    return RawFiltering(
      storedAsReceived: json['storedAsReceived'] as bool? ?? true,
      highPassHz: (json['highPassHz'] as num?)?.toDouble(),
      notchHz: (json['notchHz'] as num?)?.toDouble(),
    );
  }
}

/// `device.conditioning`: high-pass and mains notch the app applies to the
/// RAW before quality, bands, features and charts. One notch for the whole
/// recording, fixed when it started.
class SignalConditioning {
  const SignalConditioning({
    required this.highPassHz,
    required this.notchQ,
    required this.notchHz,
    required this.notchSource,
  });

  final double highPassHz;
  final double notchQ;

  /// Mains notched, each with its 2nd harmonic: `[50]`, `[60]`, `[]` (no
  /// hum) or `[50, 60]` (undecided).
  final List<double> notchHz;

  /// `detected` | `saved` (the device's last decision) | `undecided`.
  final String notchSource;

  Map<String, Object?> toJson() => {
    'highPassHz': highPassHz,
    'notchQ': notchQ,
    'notchHz': notchHz,
    'notchSource': notchSource,
  };

  static SignalConditioning? fromJson(Object? json) {
    if (json is! Map || json['highPassHz'] is! num || json['notchHz'] is! List) {
      return null;
    }
    return SignalConditioning(
      highPassHz: (json['highPassHz'] as num).toDouble(),
      notchQ: (json['notchQ'] as num?)?.toDouble() ?? 0,
      notchHz: [
        for (final v in json['notchHz'] as List)
          if (v is num) v.toDouble(),
      ],
      notchSource: json['notchSource'] as String? ?? 'undecided',
    );
  }
}

/// Base-metadata `import` block: where an imported recording came from and
/// what was lost on the way. Present only on imported recordings.
class ImportProvenance {
  const ImportProvenance({
    required this.sourceFormat,
    required this.sourceFileName,
    required this.originalChannels,
    required this.originalRateHz,
    this.droppedChannels = const [],
    this.resampled = false,
    required this.rawPresent,
    this.recordingInterval,
    this.intervalCoverage,
    this.reference,
    this.prefiltering = const {},
    required this.lossy,
    this.warnings = const [],
  });

  /// `edf` | `edf+` | `mind_monitor_csv`.
  final String sourceFormat;
  final String sourceFileName;
  final List<String> originalChannels;

  /// EEG rate in the source file (Hz); null when the source had no RAW.
  final double? originalRateHz;
  final List<String> droppedChannels;
  final bool resampled;
  final bool rawPresent;

  /// Mind Monitor recording interval (s); null for Constant / non-CSV.
  final double? recordingInterval;

  /// Share of the session the interval rows cover: min(1, ~1 s band window /
  /// [recordingInterval]). Null when [recordingInterval] is null.
  final double? intervalCoverage;
  final String? reference;

  /// EDF per-signal Prefiltering header (source label → text) where stated.
  final Map<String, String> prefiltering;
  final bool lossy;
  final List<String> warnings;

  Map<String, Object?> toJson() => {
    'sourceFormat': sourceFormat,
    'sourceFileName': sourceFileName,
    'originalChannels': originalChannels,
    'originalRateHz': originalRateHz,
    'droppedChannels': droppedChannels,
    'resampled': resampled,
    'rawPresent': rawPresent,
    'recordingInterval': recordingInterval,
    'intervalCoverage': intervalCoverage,
    if (reference != null) 'reference': reference,
    if (prefiltering.isNotEmpty) 'prefiltering': prefiltering,
    'lossy': lossy,
    'warnings': warnings,
  };

  static ImportProvenance? fromJson(Object? json) {
    if (json is! Map) return null;
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : const [];
    return ImportProvenance(
      sourceFormat: json['sourceFormat'] as String? ?? '',
      sourceFileName: json['sourceFileName'] as String? ?? '',
      originalChannels: strings(json['originalChannels']),
      originalRateHz: (json['originalRateHz'] as num?)?.toDouble(),
      droppedChannels: strings(json['droppedChannels']),
      resampled: json['resampled'] == true,
      rawPresent: json['rawPresent'] == true,
      recordingInterval: (json['recordingInterval'] as num?)?.toDouble(),
      intervalCoverage: (json['intervalCoverage'] as num?)?.toDouble(),
      reference: json['reference'] as String?,
      prefiltering: {
        if (json['prefiltering'] case final Map m)
          for (final e in m.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
      lossy: json['lossy'] == true,
      warnings: strings(json['warnings']),
    );
  }
}

/// Individual stream info: enabled + rate.
class StreamInfo {
  const StreamInfo({
    required this.enabled,
    required this.rateHz,
    this.electrodes,
    this.channels,
    this.sensors,
  });

  final bool enabled;
  final int rateHz;
  final List<int>? electrodes;
  final List<String>? channels;
  final List<String>? sensors;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'rateHz': rateHz,
    if (electrodes != null) 'electrodes': electrodes,
    if (channels != null) 'channels': channels,
    if (sensors != null) 'sensors': sensors,
  };

  static StreamInfo? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return StreamInfo(
      enabled: json['enabled'] as bool? ?? false,
      rateHz: (json['rateHz'] as num?)?.toInt() ?? 0,
      electrodes: (json['electrodes'] as List?)?.map((e) => e as int).toList(),
      channels: (json['channels'] as List?)?.map((e) => e as String).toList(),
      sensors: (json['sensors'] as List?)?.map((e) => e as String).toList(),
    );
  }
}

/// Stream configuration: what was recorded and at what rate.
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
  });

  final StreamInfo eeg;
  final StreamInfo bands;
  final StreamInfo pulse;
  final StreamInfo spo2;
  final StreamInfo movement;
  final StreamInfo peakAlpha;
  final StreamInfo imu;
  final StreamInfo ppg;
  final StreamInfo telemetry;
  final StreamInfo gestures;

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
  };

  static StreamsConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
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
    );
  }
}
