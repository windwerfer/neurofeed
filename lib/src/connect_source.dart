import 'package:muse_ml/src/rust/api/device_config.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

/// Connect-window dropdown. Distinct from [DeviceKind] (headset family).
enum ConnectSource { muse, neurosity, simulator }

extension ConnectSourceDisplay on ConnectSource {
  String get displayName => switch (this) {
    ConnectSource.muse => 'Muse',
    ConnectSource.neurosity => 'Neurosity',
    ConnectSource.simulator => 'Simulator',
  };
}

/// Static simulator rows. Labels are exact per the frozen spec.
const List<DeviceInfo> simulatorCatalog = [
  DeviceInfo(id: 'sim:muse-2', name: 'Muse 2', kind: DeviceKind.muse),
  DeviceInfo(id: 'sim:muse-s', name: 'Muse S', kind: DeviceKind.muse),
  DeviceInfo(
    id: 'sim:muse-s-athena',
    name: 'Muse S Athena',
    kind: DeviceKind.muse,
  ),
  DeviceInfo(
    id: 'sim:crown-osc',
    name: 'Crown (OSC)',
    kind: DeviceKind.neurosity,
  ),
  DeviceInfo(
    id: 'sim:notion-osc',
    name: 'Notion (OSC)',
    kind: DeviceKind.neurosity,
  ),
];

List<ConnectSource> visibleConnectSources({required bool debug}) => debug
    ? ConnectSource.values
    : const [ConnectSource.muse, ConnectSource.neurosity];

ConnectSource resolveConnectSource(
  ConnectSource source, {
  required bool debug,
}) {
  if (source == ConnectSource.simulator && !debug) {
    return ConnectSource.muse;
  }
  return source;
}

bool isSimDeviceId(String id) => id.startsWith('sim:');

/// True when [id] should not drive autoconnect / reconnect.
bool shouldIgnoreLastDevice(String? id, {required bool debug}) {
  if (id == null || id.isEmpty) return true;
  if (isSimDeviceId(id)) return !debug;
  return false;
}

bool isNeurosityHeadsetName(String name) {
  final lower = name.toLowerCase();
  return lower.contains('crown') || lower.contains('notion');
}

List<DeviceInfo> keepMuseBleDevices(List<DeviceInfo> devices) => [
  for (final d in devices)
    if (d.kind == DeviceKind.muse && !isNeurosityHeadsetName(d.name)) d,
];

DeviceInfo? simulatorCatalogRow(String id) {
  for (final d in simulatorCatalog) {
    if (d.id == id) return d;
  }
  return null;
}

String emptyDevicesCopy(ConnectSource source) => switch (source) {
  ConnectSource.muse => 'No Muse devices found. Make sure the headset is on.',
  ConnectSource.neurosity => 'No Neurosity devices found.',
  ConnectSource.simulator => 'No simulator devices.',
};
