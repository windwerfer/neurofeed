import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/app.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:muse_ml/src/charts/live_cache.dart';
import 'package:muse_ml/src/charts/band_cache.dart';
import 'package:muse_ml/src/charts/session_recorder.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';

/// Duration of each scan chunk when scanning continuously.
const _scanChunkSecs = 3;

/// Number of connect attempts before giving up.  The first BLE connect after
/// a cold start / recent re-connect often times out even when the scan just
/// saw the device; a fresh attempt (with a re-scan for a new session) almost
/// always succeeds.
const _maxConnectAttempts = 3;

/// Holds all connection + UI state for the app.
class AppStateNotifier extends StateNotifier<AppUiState> {
  AppStateNotifier(this._settings)
    : super(
        AppUiState(
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
        ),
      ) {
    _init();
  }

  final Settings _settings;
  StreamSubscription<MuseEventDto>? _eventSub;
  bool _scanEnabled = false;
  final StreamController<MuseEventDto> _eventController =
      StreamController<MuseEventDto>.broadcast();
  double _lastQualityCheck = 0;

  /// Latest 50/60 Hz line-noise ratio per electrode from Bands events.
  /// -1 means no data yet for that pad.
  final List<double> _lineNoise = List.filled(4, -1);
  final LiveCache liveCache = LiveCache();
  final BandCache bandCache = BandCache();
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
        final match =
            devices.where((d) => d.id == lastId).firstOrNull ??
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

  Future<void> _startContinuousRecorder() async {
    try {
      final storage = await resolveSessionStorage(_settings);
      await storage.ensureDir();
      final dir = scratchDirectory(storage);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await sessionRecorder.start(dir);
    } catch (e) {
      debugPrint('[muse] continuous recorder start failed: $e');
    }
  }

  void _onEvent(MuseEventDto event) {
    sessionRecorder.writeEvent(event);
    switch (event) {
      case MuseEventDto_Connected():
        debugPrint('[muse] event: connected ${event.field0}');
        _scanEnabled = false;
        unawaited(_startContinuousRecorder());
        state = state.copyWith(
          status: state.status.copyWith(connected: true, name: event.field0),
          connectWindowOpen: false,
          scanning: false,
          connectingTo: null,
        );
      case MuseEventDto_Disconnected():
        debugPrint('[muse] event: disconnected');
        sessionRecorder.stop();
        _lineNoise.fillRange(0, _lineNoise.length, -1);
        state = state.copyWith(
          status: const ConnectionStatus(
            connected: false,
            name: '',
            id: '',
            firmware: '',
          ),
          batteryLevel: 0,
          signalQuality: null,
          gestures: null,
          telemetry: const TelemetrySnapshot(
            batteryLevel: 0,
            fuelGaugeVoltage: 0,
            temperature: 0,
          ),
          connectWindowOpen: true,
          connectingTo: null,
          scanning: false,
          scanMessage: 'Reconnecting…',
        );
        _tryReconnect();
      case MuseEventDto_Eeg():
        final eeg = event.field0;
        liveCache.appendEeg(eeg);
        _maybeComputeSignalQuality();
      case MuseEventDto_Bands():
        bandCache.appendBands(event.field0);
        final idx = event.field0.electrode;
        if (idx >= 0 && idx < _lineNoise.length) {
          _lineNoise[idx] = event.field0.lineNoiseRatio;
        }
      case MuseEventDto_Gestures():
        state = state.copyWith(gestures: event.field0);
      case MuseEventDto_Telemetry():
        // debugPrint('[muse] telemetry: battery=${event.field0.batteryLevel} '
        //     'fuel=${event.field0.fuelGaugeVoltage} temp=${event.field0.temperature}');
        state = state.copyWith(
          telemetry: event.field0,
          batteryLevel: event.field0.batteryLevel,
        );
      default:
        break;
    }
  }

  void _maybeComputeSignalQuality() {
    final now = liveCache.latestTimestamp;
    if (now - _lastQualityCheck < 0.9) return;
    _lastQualityCheck = now;

    const window = 1.0;
    final quals = List.filled(4, 0.0);

    for (final ch in liveCache.channels) {
      if (ch < 0 || ch > 3) continue;
      final samples = liveCache.getRange(ch, now - window, now);
      if (samples.length < 10) continue;

      final n = samples.length;
      double sum = 0;
      for (final s in samples) {
        sum += s.v;
      }
      final mean = sum / n;

      double sumSq = 0;
      for (final s in samples) {
        sumSq += (s.v - mean) * (s.v - mean);
      }
      final variance = sumSq / n;
      final std = sqrt(variance);

      double score;
      if (std < 1.0 || std > 100.0) {
        score = 0;
      } else if (std < 15.0) {
        score = 80.0 + (15.0 - std) / 15.0 * 20.0;
      } else if (std < 40.0) {
        score = 50.0 + (40.0 - std) / 25.0 * 25.0;
      } else {
        score = 40.0 * (100.0 - std) / 60.0;
        if (score < 0) score = 0;
      }

      // Line-noise (impedance) penalty: ratios above ~0.2 start to hurt a
      // pad's fit, ~0.5 is severe (mains power is half the total spectrum).
      final noise = _lineNoise[ch];
      if (noise >= 0) {
        final penalty = ((noise - 0.2) / 0.3).clamp(0.0, 1.0);
        score = score * (1.0 - 0.6 * penalty);
      }
      quals[ch] = score;
    }

    state = state.copyWith(signalQuality: quals);
  }

  Future<void> connectTo(DeviceInfo device) async {
    if (state.connectingTo != null) return;
    _scanEnabled = false;
    final id = device.id;
    final name = device.name;
    state = state.copyWith(
      connectWindowOpen: false,
      scanning: false,
      connectingTo: name,
      scanMessage: null,
    );
    Object? lastError;
    for (var attempt = 1; attempt <= _maxConnectAttempts; attempt++) {
      debugPrint('[muse] connect attempt $attempt/$_maxConnectAttempts — '
          '$name ($id)');
      state = state.copyWith(
        scanMessage: 'Connecting… (attempt $attempt)',
      );
      try {
        final status = await connect(deviceId: id);
        debugPrint('[muse] connect returned: connected=${status.connected}');
        await _settings.setLastDeviceId(id);
        state = state.copyWith(status: status, connectingTo: null);
        return;
      } catch (e) {
        lastError = e;
        debugPrint('[muse] connect attempt $attempt failed: $e');
        if (attempt < _maxConnectAttempts) {
          // The first BLE connect right after a cold start or a recent
          // re-connect sometimes times out even though the scan just saw the
          // device (the headset isn't accepting a new connection yet).
          // Re-scanning replaces the cached peripheral with a fresh
          // adapter/session — mirroring the manual "turn it off and on"
          // flow that reliably works the second time.
          await Future<void>.delayed(const Duration(milliseconds: 800));
          await _refreshDevice(id);
        }
      }
    }
    debugPrint('[muse] connect failed after $_maxConnectAttempts attempts: '
        '$lastError');
    state = state.copyWith(
      connectingTo: null,
      connectWindowOpen: true,
      scanMessage: 'Could not connect to $name. Check that it is turned on '
          'and nearby, then try again.',
    );
  }

  /// Run a short scan for [id] so the Rust-side device cache is refreshed with
  /// a fresh peripheral (new adapter/session).  Best-effort: if the device is
  /// not advertising the old cached entry is kept and the next connect attempt
  /// simply reuses it.
  Future<void> _refreshDevice(String id) async {
    try {
      await scan(timeoutSecs: BigInt.from(_scanChunkSecs));
    } catch (e) {
      debugPrint('[muse] refresh scan error: $e');
    }
  }

  /// Attempt to reconnect to the last known device; fall back to continuous
  /// scan if the last device ID is missing or the device is not found.
  Future<void> _tryReconnect() async {
    final lastId = _settings.lastDeviceId;
    if (lastId != null && lastId.isNotEmpty) {
      final ok = await _tryAutoconnect(lastId);
      if (ok) return;
    }
    _startContinuousScan();
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
    this.signalQuality,
    this.gestures,
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
  final List<double>? signalQuality;

  /// Latest 1 Hz gesture report (blinks / clench / eye position).
  final GestureDto? gestures;
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
    Object? signalQuality = _sentinel,
    Object? gestures = _sentinel,
    Object? scanMessage = _sentinel,
    Object? connectingTo = _sentinel,
    bool? disconnecting,
  }) => AppUiState(
    status: status ?? this.status,
    currentView: currentView ?? this.currentView,
    sidebarOpen: sidebarOpen ?? this.sidebarOpen,
    connectWindowOpen: connectWindowOpen ?? this.connectWindowOpen,
    scanning: scanning ?? this.scanning,
    devices: devices ?? this.devices,
    batteryLevel: batteryLevel ?? this.batteryLevel,
    telemetry: telemetry ?? this.telemetry,
    signalQuality: identical(signalQuality, _sentinel)
        ? this.signalQuality
        : signalQuality as List<double>?,
    gestures: identical(gestures, _sentinel)
        ? this.gestures
        : gestures as GestureDto?,
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

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppUiState>((
  ref,
) {
  throw UnimplementedError('Initialize with settings before use');
});
