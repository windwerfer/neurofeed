import 'package:muse_ml/src/rust/api/device_config.dart';

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

/// Monitor-only montage. Feedback uses [DeviceConfig.forKind], not this file.
List<String> electrodeNamesForKind(DeviceKind? kind) =>
    kind == DeviceKind.neurosity ? kCrownElectrodeNames : kMuseElectrodeNames;

int channelCountForKind(DeviceKind? kind) => electrodeNamesForKind(kind).length;
