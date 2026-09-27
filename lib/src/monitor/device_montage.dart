import 'package:neurofeed/src/rust/api/device_config.dart';

const List<String> kMuseElectrodeNames = ['TP9', 'AF7', 'AF8', 'TP10'];
const List<String> kCrownElectrodeNames = [
  'CP3',
  'C3',
  'F5',
  'PO3',
  'PO4',
  'F6',
  'C4',
  'CP4',
];

/// Recording montage: electrode index → label. Monitor and feedback
/// recordings write this as `device.channelLabels`.
List<String> electrodeNamesForKind(DeviceKind? kind) =>
    kind == DeviceKind.neurosity ? kCrownElectrodeNames : kMuseElectrodeNames;

/// Channel labels in electrode-index order for a recording that produced
/// data on [electrodes]. Covers the full device montage and any extra
/// electrode index beyond it (`CH<n>`).
List<String> recordedChannelLabels({
  required DeviceKind? kind,
  required Iterable<int> electrodes,
}) {
  final names = electrodeNamesForKind(kind);
  var count = names.length;
  for (final e in electrodes) {
    if (e + 1 > count) count = e + 1;
  }
  return [
    for (var i = 0; i < count; i++) i < names.length ? names[i] : 'CH${i + 1}',
  ];
}

int channelCountForKind(DeviceKind? kind) => electrodeNamesForKind(kind).length;

/// Muse family has PPG; Crown / Notion do not.
bool deviceHasPpg(DeviceKind? kind) => kind != DeviceKind.neurosity;
