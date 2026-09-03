import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/connect_source.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

void main() {
  test('catalog ids and labels match the frozen spec', () {
    expect(simulatorCatalog.map((d) => d.id).toList(), [
      'sim:muse-2',
      'sim:muse-s',
      'sim:muse-s-athena',
      'sim:crown-osc',
      'sim:notion-osc',
    ]);
    expect(simulatorCatalog.map((d) => d.name).toList(), [
      'Muse 2',
      'Muse S',
      'Muse S Athena',
      'Crown (OSC)',
      'Notion (OSC)',
    ]);
    expect(simulatorCatalog[0].kind, DeviceKind.muse);
    expect(simulatorCatalog[1].kind, DeviceKind.muse);
    expect(simulatorCatalog[2].kind, DeviceKind.muse);
    expect(simulatorCatalog[3].kind, DeviceKind.neurosity);
    expect(simulatorCatalog[4].kind, DeviceKind.neurosity);
  });

  test('simulator includes Crown (OSC) and Notion (OSC)', () {
    expect(
      simulatorCatalog.any(
        (d) => d.name == 'Crown (OSC)' && d.id == 'sim:crown-osc',
      ),
      isTrue,
    );
    expect(
      simulatorCatalog.any(
        (d) => d.name == 'Notion (OSC)' && d.id == 'sim:notion-osc',
      ),
      isTrue,
    );
  });

  test('dropdown sources with debug on and off', () {
    expect(visibleConnectSources(debug: false), [
      ConnectSource.muse,
      ConnectSource.neurosity,
    ]);
    expect(visibleConnectSources(debug: true), ConnectSource.values);
    expect(
      visibleConnectSources(debug: false),
      isNot(contains(ConnectSource.simulator)),
    );
    expect(
      resolveConnectSource(ConnectSource.simulator, debug: false),
      ConnectSource.muse,
    );
    expect(
      resolveConnectSource(ConnectSource.simulator, debug: true),
      ConnectSource.simulator,
    );
  });

  test('Muse list never includes Crown/Notion BLE names', () {
    final devices = [
      const DeviceInfo(id: 'aa', name: 'Muse-2A3B', kind: DeviceKind.muse),
      const DeviceInfo(id: 'bb', name: 'Crown-ABC', kind: DeviceKind.muse),
      const DeviceInfo(id: 'cc', name: 'Notion 2', kind: DeviceKind.muse),
      const DeviceInfo(id: 'dd', name: 'Crown', kind: DeviceKind.neurosity),
    ];
    expect(keepMuseBleDevices(devices).map((d) => d.id).toList(), ['aa']);
  });

  test('debug-off ignores sim:* last-device', () {
    expect(shouldIgnoreLastDevice('sim:muse-s', debug: false), isTrue);
    expect(shouldIgnoreLastDevice('sim:crown-osc', debug: true), isFalse);
    expect(shouldIgnoreLastDevice('real-ble-id', debug: false), isFalse);
    expect(shouldIgnoreLastDevice('', debug: true), isTrue);
    expect(shouldIgnoreLastDevice(null, debug: true), isTrue);
  });

  test('Neurosity empty copy does not mention Bluetooth', () {
    expect(
      emptyDevicesCopy(ConnectSource.neurosity).toLowerCase(),
      isNot(contains('bluetooth')),
    );
    expect(
      emptyDevicesCopy(ConnectSource.neurosity).toLowerCase(),
      isNot(contains('ble')),
    );
  });
}
