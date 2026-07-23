import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/app.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:muse_ml/src/charts/live_cache.dart';
import 'package:muse_ml/src/charts/session_recorder.dart';

/// Duration of each scan chunk when scanning continuously.
const _scanChunkSecs = 3;

/// Holds all connection + UI state for the app.
class AppStateNotifier extends StateNotifier<AppUiState> {
  AppStateNotifier(this._settings)
      : super(AppUiState(
          status: const ConnectionStatus(
            connected: false,
            name: '',
            id: '',
            firmware: '',
          ),
          currentView: _settings.lastView,
          sidebarOpen: false,
          connectWindowOpen: false,
          scanning: false,
          devices: const [],
          batteryLevel: 0,
          scanMessage: null,
          telemetry: const TelemetrySnapshot(
            batteryLevel: 0,
            fuelGaugeVoltage: 0,
            temperature: 0,
          ),
        )) {
    _init();
  }

  final Settings _settings;
  StreamSubscription<MuseEventDto>? _eventSub;
  bool _scanEnabled = false;
  final StreamController<MuseEventDto> _eventController =
      StreamController<MuseEventDto>.broadcast();
  final LiveCache liveCache = LiveCache();
  final SessionRecorder sessionRecorder = SessionRecorder();

  Stream<MuseEventDto> get eventStream => _eventController.stream;

  Future<void> _init() async {
    try {
      final stream = subscribeEvents();
      _eventSub = stream.listen((event) {
        _eventController.add(event);
        _onEvent(event);
      });

      final status = await getStatus();
      if (status.connected) {
        state = state.copyWith(status: status);
        return;
      }

      final lastId = _settings.lastDeviceId;
      if (lastId != null && lastId.isNotEmpty) {
        final found = await _tryAutoconnect(lastId);
        if (found) return;
      }

      _startContinuousScan();
    } catch (e) {
      debugPrint('[muse] init error: $e');
      state = state.copyWith(scanMessage: 'Init error: $e');
    }
  }

  /// Scan in short chunks looking for [lastId].  Returns `true` and connects
  /// if found, `false` otherwise.
  Future<bool> _tryAutoconnect(String lastId) async {
    debugPrint('[muse] autoconnect: looking for $lastId');
    state = state.copyWith(
      connectWindowOpen: true,
      scanning: true,
      scanMessage: 'Looking for last device…',
    );
    try {
      if (!await requestBlePermissions()) {
        debugPrint('[muse] autoconnect: BLE permissions not granted');
        state = state.copyWith(
          scanning: false,
          scanMessage: 'BLE permissions not granted',
        );
        return false;
      }
      for (var i = 0; i < 5; i++) {
        final devices = await scan(timeoutSecs: BigInt.from(_scanChunkSecs));
        final match = devices.where((d) => d.id == lastId).firstOrNull ??
            devices.where((d) => d.name == lastId).firstOrNull;
        if (match != null) {
          debugPrint('[muse] autoconnect: found ${match.name}, connecting');
          await connectTo(match);
          return true;
        }
        state = state.copyWith(
          scanMessage: 'Searching… (${(i + 1) * _scanChunkSecs}s)',
        );
      }
      debugPrint('[muse] autoconnect: last device not found after 5 chunks');
      state = state.copyWith(
        scanning: false,
        scanMessage: 'Last device not found',
      );
    } catch (e) {
      debugPrint('[muse] autoconnect error: $e');
      state = state.copyWith(scanning: false, scanMessage: 'Scan error: $e');
    }
    return false;
  }

  /// Start a continuous scan loop that runs until a device is connected or
  /// the connect window is closed.  Each chunk is a short BLE scan whose
  /// results are merged into the UI list as they arrive.
  Future<void> _startContinuousScan() async {
    _scanEnabled = true;
    debugPrint('[muse] continuous scan starting');
    state = state.copyWith(
      connectWindowOpen: true,
      scanning: true,
      scanMessage: 'Scanning…',
    );

    try {
      if (!await requestBlePermissions()) {
        debugPrint('[muse] continuous scan: BLE permissions not granted');
        state = state.copyWith(
          scanning: false,
          scanMessage: 'BLE permissions not granted',
        );
        return;
      }

      var allDevices = <DeviceInfo>[];

      while (_scanEnabled && !state.status.connected) {
        final devices = await scan(timeoutSecs: BigInt.from(_scanChunkSecs));
        if (!_scanEnabled || state.status.connected) break;

        for (final d in devices) {
          if (!allDevices.any((x) => x.id == d.id)) {
            allDevices = [...allDevices, d];
          }
        }
        debugPrint(
          '[muse] scan chunk: ${devices.length} device(s) from rust, '
          '${allDevices.length} unique total',
        );
        state = state.copyWith(
          devices: allDevices,
          scanMessage: '${allDevices.length} device(s) found',
        );
      }

      if (!state.status.connected) {
        debugPrint('[muse] continuous scan stopped (no connection)');
        state = state.copyWith(scanning: false);
      } else {
        debugPrint('[muse] continuous scan stopped (connected)');
      }
    } catch (e) {
      debugPrint('[muse] continuous scan error: $e');
      state = state.copyWith(scanning: false, scanMessage: 'Scan error: $e');
    }
  }

  void _onEvent(MuseEventDto event) {
    sessionRecorder.writeEvent(event);
    switch (event) {
      case MuseEventDto_Connected():
        debugPrint('[muse] event: connected ${event.field0}');
        _scanEnabled = false;
        sessionRecorder.start();
        state = state.copyWith(
          status: state.status.copyWith(connected: true, name: event.field0),
          connectWindowOpen: false,
          scanning: false,
          connectingTo: null,
        );
      case MuseEventDto_Disconnected():
        debugPrint('[muse] event: disconnected');
        sessionRecorder.stop();
        state = state.copyWith(
          status: const ConnectionStatus(
            connected: false,
            name: '',
            id: '',
            firmware: '',
          ),
          batteryLevel: 0,
          telemetry: const TelemetrySnapshot(
            batteryLevel: 0,
            fuelGaugeVoltage: 0,
            temperature: 0,
          ),
          connectWindowOpen: true,
          connectingTo: null,
          scanning: false,
          scanMessage: null,
          disconnecting: false,
        );
        _startContinuousScan();
      case MuseEventDto_Eeg():
        liveCache.appendEeg(event.field0);
      case MuseEventDto_Telemetry():
        state = state.copyWith(
          telemetry: event.field0,
          batteryLevel: event.field0.batteryLevel,
        );
      default:
        break;
    }
  }

  Future<void> connectTo(DeviceInfo device) async {
    if (state.connectingTo != null) return;
    _scanEnabled = false;
    debugPrint('[muse] connecting to ${device.name} (${device.id})');
    state = state.copyWith(
      connectWindowOpen: false,
      scanning: false,
      connectingTo: device.name,
      scanMessage: null,
    );
    try {
      final status = await connect(deviceId: device.id);
      debugPrint('[muse] connect returned: connected=${status.connected}');
      await _settings.setLastDeviceId(device.id);
      state = state.copyWith(
        status: status,
        connectingTo: null,
      );
    } catch (e) {
      debugPrint('[muse] connect failed: $e');
      state = state.copyWith(
        connectingTo: null,
        connectWindowOpen: true,
        scanMessage: 'Connection failed: $e',
      );
    }
  }

  Future<void> disconnectDevice() async {
    _scanEnabled = false;
    await disconnect();
    await _settings.setLastDeviceId('');
  }

  /// Disconnect without clearing [lastDeviceId] — called when the app is
  /// closing (e.g. close button on Linux).  On the next launch the saved
  /// device ID will trigger an autoconnect attempt.
  Future<void> disconnectOnClose() async {
    if (!state.status.connected) return;
    state = state.copyWith(disconnecting: true);
    try {
      await disconnect().timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<void> openConnectWindowAndScan() async {
    _scanEnabled = false;
    _startContinuousScan();
  }

  void toggleSidebar() =>
      state = state.copyWith(sidebarOpen: !state.sidebarOpen);

  void setSidebar(bool open) => state = state.copyWith(sidebarOpen: open);

  void setCurrentView(AppView view) {
    state = state.copyWith(currentView: view);
    _settings.setLastView(view);
  }

  void toggleConnectWindow() {
    if (state.connectWindowOpen) {
      _scanEnabled = false;
      state = state.copyWith(
        connectWindowOpen: false,
        scanning: false,
        scanMessage: null,
      );
    } else {
      _startContinuousScan();
    }
  }

  @override
  void dispose() {
    _scanEnabled = false;
    _eventSub?.cancel();
    _eventController.close();
    super.dispose();
  }
}

/// Immutable UI state snapshot.
class AppUiState {
  const AppUiState({
    required this.status,
    required this.currentView,
    required this.sidebarOpen,
    required this.connectWindowOpen,
    required this.scanning,
    required this.devices,
    required this.batteryLevel,
    required this.telemetry,
    this.scanMessage,
    this.connectingTo,
    this.disconnecting = false,
  });

  final ConnectionStatus status;
  final AppView currentView;
  final bool sidebarOpen;
  final bool connectWindowOpen;
  final bool scanning;
  final List<DeviceInfo> devices;
  final double batteryLevel;
  final TelemetrySnapshot telemetry;
  final String? scanMessage;
  final String? connectingTo;
  final bool disconnecting;

  static const _sentinel = Object();

  AppUiState copyWith({
    ConnectionStatus? status,
    AppView? currentView,
    bool? sidebarOpen,
    bool? connectWindowOpen,
    bool? scanning,
    List<DeviceInfo>? devices,
    double? batteryLevel,
    TelemetrySnapshot? telemetry,
    Object? scanMessage = _sentinel,
    Object? connectingTo = _sentinel,
    bool? disconnecting,
  }) =>
      AppUiState(
        status: status ?? this.status,
        currentView: currentView ?? this.currentView,
        sidebarOpen: sidebarOpen ?? this.sidebarOpen,
        connectWindowOpen: connectWindowOpen ?? this.connectWindowOpen,
        scanning: scanning ?? this.scanning,
        devices: devices ?? this.devices,
        batteryLevel: batteryLevel ?? this.batteryLevel,
        telemetry: telemetry ?? this.telemetry,
        scanMessage: switch (scanMessage) {
          Object() when identical(scanMessage, _sentinel) => this.scanMessage,
          _ => scanMessage as String?,
        },
        connectingTo: switch (connectingTo) {
          Object() when identical(connectingTo, _sentinel) => this.connectingTo,
          _ => connectingTo as String?,
        },
        disconnecting: disconnecting ?? this.disconnecting,
      );
}

final appStateProvider =
    StateNotifierProvider<AppStateNotifier, AppUiState>((ref) {
  throw UnimplementedError('Initialize with settings before use');
});
