import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Settings settings;
  late AppStateNotifier app;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await Settings.load();
    app = AppStateNotifier.forTest(settings);
  });

  tearDown(() {
    app.dispose();
  });

  test(
    'lost connection starts auto-reconnect and keeps lastDeviceId',
    () async {
      await settings.setLastDeviceId('aa:bb');
      app.debugSetConnected(id: 'aa:bb', name: 'Muse 2');

      app.debugAddEvent(const MuseEventDto.disconnected());

      expect(app.state.status.connected, isFalse);
      expect(app.state.scanMessage, 'Reconnecting…');
      expect(app.state.connectWindowOpen, isTrue);
      expect(app.debugReconnectCalls, 1);
      expect(app.allowAutoReconnect, isTrue);
      expect(settings.lastDeviceId, 'aa:bb');
    },
  );

  test('duplicate Disconnected during reconnect is ignored', () async {
    await settings.setLastDeviceId('aa:bb');
    app.debugSetConnected(id: 'aa:bb', name: 'Muse 2');
    app.debugAddEvent(const MuseEventDto.disconnected());
    expect(app.debugReconnectCalls, 1);

    app.debugAddEvent(const MuseEventDto.disconnected());
    expect(app.debugReconnectCalls, 1);
    expect(app.state.scanMessage, 'Reconnecting…');
  });

  test('user disconnect stays down and keeps lastDeviceId', () async {
    await settings.setLastDeviceId('aa:bb');
    app.debugSetConnected(id: 'aa:bb', name: 'Muse 2');
    app.debugMarkUserDisconnected();

    app.debugAddEvent(const MuseEventDto.disconnected());

    expect(app.state.status.connected, isFalse);
    expect(app.state.scanMessage, isNull);
    expect(app.state.connectWindowOpen, isFalse);
    expect(app.state.disconnecting, isFalse);
    expect(app.debugReconnectCalls, 0);
    expect(app.allowAutoReconnect, isFalse);
    expect(settings.lastDeviceId, 'aa:bb');

    app.debugAddEvent(const MuseEventDto.disconnected());
    expect(app.debugReconnectCalls, 0);
    expect(app.state.connectWindowOpen, isFalse);
  });

  test('connect again re-enables lost-link auto-reconnect', () async {
    await settings.setLastDeviceId('aa:bb');
    app.debugSetConnected(id: 'aa:bb', name: 'Muse 2');
    app.debugMarkUserDisconnected();
    app.debugAddEvent(const MuseEventDto.disconnected());
    expect(app.debugReconnectCalls, 0);

    app.debugSetConnected(id: 'aa:bb', name: 'Muse 2');
    expect(app.allowAutoReconnect, isTrue);

    app.debugAddEvent(const MuseEventDto.disconnected());
    expect(app.debugReconnectCalls, 1);
    expect(app.state.scanMessage, 'Reconnecting…');
  });

  test('Disconnected while already idle does not auto-reconnect', () {
    app.debugAddEvent(const MuseEventDto.disconnected());
    expect(app.state.status.connected, isFalse);
    expect(app.debugReconnectCalls, 0);
    expect(app.state.connectWindowOpen, isFalse);
    expect(app.state.scanMessage, isNull);
  });
}
