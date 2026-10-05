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

/// Muse AUX inputs follow the four head electrodes: electrode 4 = AUX1 …
/// electrode 7 = AUX4 (Classic streams AUX1 only; Athena AUX1–AUX4).
const List<String> kMuseAuxElectrodeNames = ['AUX1', 'AUX2', 'AUX3', 'AUX4'];

/// True for auxiliary (non-head) inputs. AUX channels are recorded with raw
/// + bands but never count toward quality aggregates or feature selection.
bool isAuxChannelLabel(String label) => label.startsWith('AUX');

/// AUX dots and monitor channels while [museAuxEnabled] is on.
///
/// [hardwareAux] is [ConnectionStatus.auxChannels]: Classic 1, Athena 4,
/// Crown 0. A simulated Muse reports the same Classic or Athena count.
/// The stream is already running; the switch only shows or hides it.
int displayedAuxChannels({
  required DeviceKind? kind,
  required int hardwareAux,
  required bool museAuxEnabled,
}) {
  if (kind == DeviceKind.neurosity || !museAuxEnabled || hardwareAux <= 0) {
    return 0;
  }
  final cap = kMuseAuxElectrodeNames.length;
  return hardwareAux > cap ? cap : hardwareAux;
}

/// AUX channels written into a recording or feedback file. Both switches
/// have to be on. Latched when the capture starts.
int recordedAuxChannels({
  required DeviceKind? kind,
  required int hardwareAux,
  required bool museAuxEnabled,
  required bool recordAux,
}) {
  if (!recordAux) return 0;
  return displayedAuxChannels(
    kind: kind,
    hardwareAux: hardwareAux,
    museAuxEnabled: museAuxEnabled,
  );
}

/// Recording montage: electrode index → label. Monitor and feedback
/// recordings write this as `device.channelLabels`. [auxChannels] is the
/// Muse AUX count streamed on the connection (`ConnectionStatus.auxChannels`).
List<String> electrodeNamesForKind(DeviceKind? kind, {int auxChannels = 0}) {
  if (kind == DeviceKind.neurosity) return kCrownElectrodeNames;
  if (auxChannels <= 0) return kMuseElectrodeNames;
  return [
    ...kMuseElectrodeNames,
    ...kMuseAuxElectrodeNames.take(auxChannels),
  ];
}

/// Channel labels in electrode-index order for a recording that produced
/// data on [electrodes]. Covers the full device montage; Muse electrodes
/// past the head four are AUX, anything else unknown is `CH<n>`.
List<String> recordedChannelLabels({
  required DeviceKind? kind,
  required Iterable<int> electrodes,
  int auxChannels = 0,
}) {
  final names = kind == DeviceKind.neurosity
      ? kCrownElectrodeNames
      : [...kMuseElectrodeNames, ...kMuseAuxElectrodeNames];
  var count = electrodeNamesForKind(kind, auxChannels: auxChannels).length;
  for (final e in electrodes) {
    if (e + 1 > count) count = e + 1;
  }
  return [
    for (var i = 0; i < count; i++) i < names.length ? names[i] : 'CH${i + 1}',
  ];
}

/// Indices of head (non-AUX) channels in [labels].
List<int> headChannelIndices(List<String> labels) => [
  for (var i = 0; i < labels.length; i++)
    if (!isAuxChannelLabel(labels[i])) i,
];

int channelCountForKind(DeviceKind? kind) => electrodeNamesForKind(kind).length;

/// Muse family has PPG; Crown / Notion do not.
bool deviceHasPpg(DeviceKind? kind) => kind != DeviceKind.neurosity;
