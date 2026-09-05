import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/settings.dart';

AppUiState _state({String? scanMessage}) => AppUiState(
  status: const ConnectionStatus(
    connected: false,
    name: '',
    id: '',
    firmware: '',
  ),
  currentView: AppView.feedback,
  sidebarOpen: false,
  connectWindowOpen: false,
  scanning: false,
  devices: const [],
  batteryLevel: 0,
  telemetry: const TelemetrySnapshot(
    batteryLevel: 0,
    fuelGaugeVoltage: 0,
    temperature: 0,
  ),
  scanMessage: scanMessage,
);

void main() {
  test('copyWith(scanMessage: null) clears leftover connecting copy', () {
    final before = _state(scanMessage: 'Connecting… (attempt 1)');
    expect(before.copyWith().scanMessage, 'Connecting… (attempt 1)');
    expect(before.copyWith(scanMessage: null).scanMessage, isNull);
  });
}
