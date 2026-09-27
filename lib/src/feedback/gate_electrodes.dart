import 'package:neurofeed/src/rust/api/device_config.dart';

/// Device target pair as names: [DeviceConfig.targetElectrodes]
/// (Muse AF7/AF8, Crown PO3/PO4).
List<String> deviceGateElectrodeNames(DeviceConfig config) => [
  for (final i in config.targetElectrodes.map((e) => e.toInt()))
    if (i < config.electrodeNames.length) config.electrodeNames[i],
];

/// Resolve montage **names** to indices. Unknown names are dropped.
List<int> electrodeIndicesFor(
  List<String> names, {
  required List<String> montageNames,
}) {
  final out = <int>[];
  for (final name in names) {
    final i = montageNames.indexOf(name);
    if (i >= 0) {
      out.add(i);
    }
  }
  return out;
}
