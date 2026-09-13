import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/agent/agent_protocol.dart';
import 'package:muse_ml/src/connect_source.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/settings.dart';

void main() {
  test('parseAppView matches enum names', () {
    for (final view in AppView.values) {
      expect(parseAppView(view.name), view);
    }
    expect(parseAppView('rawEeg'), AppView.rawEeg);
    expect(parseAppView('bands'), AppView.bands);
    expect(parseAppView('histogram'), AppView.histogram);
    expect(parseAppView('spectrogram'), AppView.spectrogram);
    expect(parseAppView('psd'), AppView.psd);
    expect(parseAppView('waterfall'), isNull);
    expect(parseAppView('nope'), isNull);
    expect(parseAppView(null), isNull);
  });

  test('parseConnectSource matches enum names', () {
    expect(parseConnectSource('simulator'), ConnectSource.simulator);
    expect(parseConnectSource('muse'), ConnectSource.muse);
    expect(parseConnectSource('x'), isNull);
  });

  test('resolveAgentDevice prefers simulator catalog then scanned list', () {
    final sim = resolveAgentDevice('sim:muse-2', const []);
    expect(sim, isNotNull);
    expect(sim!.name, 'Muse 2');
    expect(resolveAgentDevice('sim:muse-s', const [])?.name, 'Muse S');

    expect(resolveAgentDevice('sim:nope', const []), isNull);

    const scanned = DeviceInfo(
      id: 'aa:bb:cc',
      name: 'Muse 2',
      kind: DeviceKind.muse,
    );
    expect(resolveAgentDevice('aa:bb:cc', [scanned])?.id, 'aa:bb:cc');
  });
}
