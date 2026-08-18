import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/settings.dart';

/// Network streaming protocols offered by the Streaming view. Only one is
/// active at a time; the chosen protocol can be enabled/disabled.
enum StreamProtocol {
  osc(
    'OSC',
    'Open Sound Control: raw samples as unicast UDP to a PC tool '
    '(OpenViBE, Max/MSP, TouchDesigner, custom scripts).',
  ),
  lsl(
    'LSL',
    'Lab Streaming Layer: auto-discovered streams received by LabRecorder, '
    'OpenViBE, EEGLAB and other LSL clients on the local network.',
  ),
  brainflow(
    'BrainFlow',
    'BrainFlow Streaming Board format (multicast UDP): EEG default preset, '
    'plus IMU (auxiliary) and PPG (ancillary) presets when separate groups '
    'is on. Receive on the PC with BoardShim(STREAMING_BOARD) using '
    'master_board MUSE_2_BOARD / MUSE_S_BOARD.',
  );

  const StreamProtocol(this.label, this.description);

  final String label;
  final String description;

  static StreamProtocol fromName(String? name) =>
      StreamProtocol.values.where((p) => p.name == name).firstOrNull ??
      StreamProtocol.osc;
}

/// One streamable sensor group: an LSL/OSC stream with a fixed channel count
/// and nominal sample rate, fed by one or more `MuseEventDto` types.
@immutable
class StreamGroupDef {
  const StreamGroupDef({
    required this.id,
    required this.name,
    required this.streamType,
    required this.channelCount,
    required this.nominalRate,
    required this.channelNames,
  });

  final String id;
  final String name;
  final String streamType;
  final int channelCount;
  final double nominalRate;
  final List<String> channelNames;
}

/// The streamable groups. EEG is always available; PPG/IMU/Bands are only
/// streamed when the "separate channels per group" setting is on.
class StreamGroups {
  static const eeg = StreamGroupDef(
    id: 'eeg',
    name: 'EEG',
    streamType: 'EEG',
    channelCount: 4,
    nominalRate: 256,
    channelNames: ['TP9', 'AF7', 'AF8', 'TP10'],
  );

  static const ppg = StreamGroupDef(
    id: 'ppg',
    name: 'PPG',
    streamType: 'PPG',
    channelCount: 3,
    nominalRate: 64,
    channelNames: ['ambient', 'infrared', 'red'],
  );

  static const imu = StreamGroupDef(
    id: 'imu',
    name: 'IMU',
    streamType: 'IMU',
    channelCount: 6,
    nominalRate: 52,
    channelNames: [
      'accel_x',
      'accel_y',
      'accel_z',
      'gyro_x',
      'gyro_y',
      'gyro_z',
    ],
  );

  static const bands = StreamGroupDef(
    id: 'bands',
    name: 'Bands',
    streamType: 'Bands',
    channelCount: 20,
    nominalRate: 1,
    channelNames: [
      'TP9_delta', 'TP9_theta', 'TP9_alpha', 'TP9_beta', 'TP9_gamma',
      'AF7_delta', 'AF7_theta', 'AF7_alpha', 'AF7_beta', 'AF7_gamma',
      'AF8_delta', 'AF8_theta', 'AF8_alpha', 'AF8_beta', 'AF8_gamma',
      'TP10_delta', 'TP10_theta', 'TP10_alpha', 'TP10_beta', 'TP10_gamma',
    ],
  );

  static const all = [eeg, ppg, imu, bands];

  static StreamGroupDef byId(String id) =>
      all.firstWhere((g) => g.id == id, orElse: () => eeg);
}

/// Transport-agnostic streaming configuration, built from [Settings].
@immutable
class StreamingConfig {
  const StreamingConfig({
    required this.protocol,
    required this.enabled,
    required this.oscIp,
    required this.oscPort,
    required this.prefix,
    required this.separateGroups,
    this.brainflowIp,
    this.brainflowPort,
  });

  final StreamProtocol protocol;
  final bool enabled;
  final String? oscIp;
  final int? oscPort;
  final String prefix;
  final bool separateGroups;

  /// Multicast group + port for the BrainFlow Streaming Board streamer.
  final String? brainflowIp;
  final int? brainflowPort;

  static StreamingConfig fromSettings(Settings settings) {
    final protocol = StreamProtocol.fromName(settings.streamProtocolName);
    final ip = settings.oscIp;
    final ipOk = Uri.tryParse('http://$ip')?.host.isNotEmpty ?? false;
    final enabled = switch (protocol) {
      StreamProtocol.osc => settings.oscEnabled,
      StreamProtocol.lsl => settings.lslEnabled,
      StreamProtocol.brainflow => settings.brainflowEnabled,
    };
    return StreamingConfig(
      protocol: protocol,
      enabled: enabled,
      oscIp: ipOk ? ip : null,
      oscPort: settings.oscPort,
      prefix: switch (protocol) {
        StreamProtocol.osc => settings.oscPrefix,
        StreamProtocol.lsl => settings.lslPrefix,
        StreamProtocol.brainflow => '',
      },
      separateGroups: switch (protocol) {
        StreamProtocol.osc => settings.oscSeparateGroups,
        StreamProtocol.lsl => settings.lslSeparateGroups,
        // When on, BrainFlow streams the IMU (auxiliary preset) and PPG
        // (ancillary preset) streams in addition to the EEG default preset.
        StreamProtocol.brainflow => settings.brainflowSeparateGroups,
      },
      brainflowIp: protocol == StreamProtocol.brainflow
          ? settings.brainflowIp
          : null,
      brainflowPort: protocol == StreamProtocol.brainflow
          ? settings.brainflowPort
          : null,
    );
  }

  /// Effective group set: everything when separate groups are on, EEG only
  /// otherwise (mixed sample rates cannot share one stream).
  List<StreamGroupDef> get groups =>
      separateGroups ? StreamGroups.all : const [StreamGroups.eeg];
}