import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('last device keeps its kind so a Crown reconnects over OSC', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    expect(settings.lastDeviceId, isNull);
    expect(settings.lastDeviceKind, DeviceKind.muse);

    await settings.setLastDevice(
      'local7cca794fb5f4675a69371e949b2',
      DeviceKind.neurosity,
    );
    expect(settings.lastDeviceId, 'local7cca794fb5f4675a69371e949b2');
    expect(settings.lastDeviceKind, DeviceKind.neurosity);

    await settings.setLastDevice('aa:bb', DeviceKind.muse);
    expect(settings.lastDeviceKind, DeviceKind.muse);
  });
}
