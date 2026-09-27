import 'package:neurofeed/src/rust/api/device_config.dart';

/// Device target pair as names: [DeviceConfig.targetElectrodes]
/// (Muse AF7/AF8, Crown PO3/PO4).
List<String> deviceGateElectrodeNames(DeviceConfig config) => [
  for (final i in config.targetElectrodes.map((e) => e.toInt()))
    if (i < config.electrodeNames.length) config.electrodeNames[i],
];

/// Device frontal pair as montage indices: [DeviceConfig.frontalElectrodes]
/// (Muse AF7/AF8, Crown F5/F6). The band-math drowsiness guard reads delta here.
List<int> deviceFrontalElectrodes(DeviceConfig config) => [
  for (final i in config.frontalElectrodes.map((e) => e.toInt()))
    if (i < config.electrodeNames.length) i,
];
