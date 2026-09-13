import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/agent/agent_flags.dart';
import 'package:muse_ml/src/app.dart';
import 'package:muse_ml/src/connect_source.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';
import 'package:muse_ml/src/settings.dart';

/// Duration of each scan chunk when scanning continuously.
const _scanChunkSecs = 3;

/// Number of connect attempts before giving up.  The first BLE connect after
/// a cold start / recent re-connect often times out even when the scan just
/// saw the device; a fresh attempt (with a re-scan for a new session) almost
/// always succeeds.
const _maxConnectAttempts = 3;

/// Global completer for btleplug initialization on Android.
/// Completes once the native btleplug context is guaranteed ready.
final _btleplugReady = Completer<void>();

/// Ensures btleplug is initialized on Android before any BLE operation.
/// On non-Android platforms, completes immediately.
Future<void> ensureBtleplugReady() async {
  if (_btleplugReady.isCompleted) return;

  if (defaultTargetPlatform == TargetPlatform.android) {
    const channel = MethodChannel('muse_ml/init');
    await channel.invokeMethod('ensureInitialized');
  }

  if (!_btleplugReady.isCompleted) {
    _btleplugReady.complete();
  }
}

/// Holds all connection + UI state for the app.
class AppStateNotifier extends StateNotifier<AppUiState> {
  AppStateNotifier(this._settings, {bool initialize = true})
    : _testMode = !initialize,
      super(
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
          connectSource: museAgentEnabled
              ? ConnectSource.simulator
              : ConnectSource.muse,
          lastConnectedKind: null,
        ),
      ) {
    if (initialize) {
      _init();
    } else if (!_initDone.isCompleted) {
      _initDone.complete();
    }
  }

  @visibleForTesting
  AppStateNotifier.forTest(Settings settings)
    : this(settings, initialize: false);

  final Settings _settings;
  final bool _testMode;
  StreamSubscription<MuseEventDto>? _eventSub;
  bool _scanEnabled = false;
  bool _allowAutoReconnect = true;
  bool _reconnectInFlight = false;
  final Completer<void> _initDone = Completer<void>();
  final StreamController<MuseEventDto> _eventController =
      StreamController<MuseEventDto>.broadcast();
  double _lastQualityCheck = 0;

  /// Lost-link and launch auto-reconnect. Cleared by a user disconnect
  /// (status bar / agent) until the next [connectTo].
  bool get allowAutoReconnect => _allowAutoReconnect;

  @visibleForTesting
  int debugReconnectCalls = 0;

  /// Latest 50/60 Hz line-noise ratio per electrode from Bands events.
  /// -1 means no data yet for that pad.
  final List<double> _lineNoise = List.filled(4, -1);
  final _PadQualityRing _padQuality = _PadQualityRing();

  Stream<MuseEventDto> get eventStream => _eventController.stream;

  Future<void> get initDone => _initDone.future;

  Future<void> _init() async {
    try {
      await ensureBtleplugReady();
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

      if (museAgentEnabled) {
        state = state.copyWith(
          connectSource: ConnectSource.simulator,
          devices: simulatorCatalog,
          connectWindowOpen: false,
          scanning: false,
        );
        return;
      }

      final lastId = _settings.lastDeviceId;
      if (!shouldIgnoreLastDevice(
        lastId,
        debug: _settings.enableSimulatedDevices,
      )) {
        if (isSimDeviceId(lastId!)) {
          final found = await _tryAutoconnectSim(lastId);
          if (found) return;
        } else {
          // Unbounded scan for lastDeviceId; do not block initDone on it.
          unawaited(_tryAutoconnect(lastId));
          return;
        }
      }

      _startDiscoveryForCurrentSource();
    } catch (e) {
      debugPrint('[muse] init error: $e');
      state = state.copyWith(scanMessage: 'Init error: $e');
    } finally {
      if (!_initDone.isCompleted) _initDone.complete();
    }
  }

  /// Connect a `sim:*` catalog row without BLE. Debug mode only.
  Future<bool> _tryAutoconnectSim(String lastId) async {
    final row = simulatorCatalogRow(lastId);
    if (row == null) return false;
    debugPrint('[muse] autoconnect: simulator $lastId');
    state = state.copyWith(
      connectSource: ConnectSource.simulator,
      devices: simulatorCatalog,
      connectWindowOpen: true,
      scanning: false,
      scanMessage: 'Connecting simulator…',
    );
    await connectTo(row);
    return state.status.connected;
  }

  /// Scan in short chunks looking for [lastId] until it appears, the user
  /// cancels, or auto-reconnect is disabled. Returns `true` if connected.
  Future<bool> _tryAutoconnect(String lastId) async {
    if (isSimDeviceId(lastId)) return false;
    debugPrint('[muse] autoconnect: looking for $lastId');
    _scanEnabled = true;
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
      var chunks = 0;
      while (_scanEnabled && _allowAutoReconnect && !state.status.connected) {
        await ensureBtleplugReady();
        if (!_scanEnabled || !_allowAutoReconnect || state.status.connected) {
          break;
        }
        final devices = await scan(timeoutSecs: BigInt.from(_scanChunkSecs));
        if (!_scanEnabled || !_allowAutoReconnect || state.status.connected) {
          break;
        }
        final match =
            devices.where((d) => d.id == lastId).firstOrNull ??
            devices.where((d) => d.name == lastId).firstOrNull;
        if (match != null) {
          debugPrint('[muse] autoconnect: found ${match.name}, connecting');
          await connectTo(match);
          if (state.status.connected) return true;
          if (!_allowAutoReconnect) return false;
          _scanEnabled = true;
          state = state.copyWith(
            connectWindowOpen: true,
            scanning: true,
            scanMessage: 'Looking for last device…',
          );
          continue;
        }
        chunks++;
        state = state.copyWith(
          scanMessage: 'Searching… (${chunks * _scanChunkSecs}s)',
        );
      }
    } catch (e) {
      debugPrint('[muse] autoconnect error: $e');
      if (_scanEnabled && _allowAutoReconnect) {
        state = state.copyWith(scanning: false, scanMessage: 'Scan error: $e');
      }
    }
    return state.status.connected;
  }

  /// Open the connect window and start discovery for [state.connectSource].
  void _startDiscoveryForCurrentSource() {
    switch (state.connectSource) {
      case ConnectSource.muse:
        unawaited(_startContinuousScan());
      case ConnectSource.neurosity:
        _scanEnabled = false;
        state = state.copyWith(
          connectWindowOpen: true,
          scanning: false,
          devices: const [],
          scanMessage: null,
        );
      case ConnectSource.simulator:
        _scanEnabled = false;
        state = state.copyWith(
          connectWindowOpen: true,
          scanning: false,
          devices: simulatorCatalog,
          scanMessage: null,
        );
    }
  }

  /// Start a continuous scan loop that runs until a device is connected or
  /// the connect window is closed.  Each chunk is a short BLE scan whose
  /// results are merged into the UI list as they arrive. Muse source only.
  Future<void> _startContinuousScan() async {
    if (state.connectSource != ConnectSource.muse) {
      _startDiscoveryForCurrentSource();
      return;
    }
    _scanEnabled = true;
    debugPrint('[muse] continuous scan starting');
    state = state.copyWith(
      connectWindowOpen: true,
      scanning: true,
      devices: const [],
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
        if (state.connectSource != ConnectSource.muse) break;
        await ensureBtleplugReady();
        final devices = await scan(timeoutSecs: BigInt.from(_scanChunkSecs));
        if (!_scanEnabled || state.status.connected) break;
        if (state.connectSource != ConnectSource.muse) break;

        final museOnly = keepMuseBleDevices(devices);
        for (final d in museOnly) {
          if (!allDevices.any((x) => x.id == d.id)) {
            allDevices = [...allDevices, d];
          }
        }
        debugPrint(
          '[muse] scan chunk: ${devices.length} device(s) from rust, '
          '${museOnly.length} muse, ${allDevices.length} unique total',
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
    switch (event) {
      case MuseEventDto_Connected():
        debugPrint('[muse] event: connected ${event.field0}');
        _scanEnabled = false;
        state = state.copyWith(
          status: state.status.copyWith(connected: true, name: event.field0),
          connectWindowOpen: false,
          scanning: false,
          connectingTo: null,
        );
      case MuseEventDto_Disconnected():
        debugPrint('[muse] event: disconnected');
        _onDisconnected();
      case MuseEventDto_Eeg():
        _padQuality.appendEeg(event.field0);
        _maybeComputeSignalQuality();
      case MuseEventDto_Bands():
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

  void _onDisconnected() {
    // A second Disconnected (muse-rs watcher after our own sink event) must
    // not abort an in-flight reconnect or restart one the user already
    // cancelled.
    if (!state.status.connected && !state.disconnecting) {
      return;
    }
    _lineNoise.fillRange(0, _lineNoise.length, -1);
    _padQuality.clear();
    _lastQualityCheck = 0;
    const idle = ConnectionStatus(
      connected: false,
      name: '',
      id: '',
      firmware: '',
    );
    const telemetry = TelemetrySnapshot(
      batteryLevel: 0,
      fuelGaugeVoltage: 0,
      temperature: 0,
    );
    if (!_allowAutoReconnect) {
      state = state.copyWith(
        status: idle,
        batteryLevel: 0,
        signalQuality: null,
        gestures: null,
        telemetry: telemetry,
        connectWindowOpen: false,
        connectingTo: null,
        scanning: false,
        scanMessage: null,
        disconnecting: false,
      );
      return;
    }
    state = state.copyWith(
      status: idle,
      batteryLevel: 0,
      signalQuality: null,
      gestures: null,
      telemetry: telemetry,
      connectWindowOpen: true,
      connectingTo: null,
      scanning: false,
      scanMessage: 'Reconnecting…',
      disconnecting: false,
    );
    unawaited(_tryReconnect());
  }

  /// Keep in sync with Rust `features::pad_quality_from_std_and_noise` until
  /// the Crown-run series deletes this Dart copy.
  void _maybeComputeSignalQuality() {
    final now = _padQuality.latestTimestamp;
    if (now - _lastQualityCheck < 0.9) return;
    _lastQualityCheck = now;

    const window = 1.0;
    final quals = List.filled(4, 0.0);

    for (final ch in _padQuality.channels) {
      if (ch < 0 || ch > 3) continue;
      final samples = _padQuality.valuesIn(ch, now - window, now);
      if (samples.length < 10) continue;

      final n = samples.length;
      double sum = 0;
      for (final v in samples) {
        sum += v;
      }
      final mean = sum / n;

      double sumSq = 0;
      for (final v in samples) {
        sumSq += (v - mean) * (v - mean);
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

  Future<void> connectTo(DeviceInfo device, {bool persist = true}) async {
    if (state.connectingTo != null) return;
    _allowAutoReconnect = true;
    _scanEnabled = false;
    final id = device.id;
    final name = device.name;
    final kind = device.kind;
    final simulate = isSimDeviceId(id);
    final attempts = simulate ? 1 : _maxConnectAttempts;
    state = state.copyWith(
      connectWindowOpen: false,
      scanning: false,
      connectingTo: name,
      scanMessage: null,
    );
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      debugPrint(
        '[muse] connect attempt $attempt/$attempts — '
        '$name ($id) kind=$kind simulate=$simulate',
      );
      state = state.copyWith(scanMessage: 'Connecting… (attempt $attempt)');
      try {
        final status = await connectWithOptions(
          deviceId: id,
          kind: kind,
          simulate: simulate,
        );
        debugPrint('[muse] connect returned: connected=${status.connected}');
        if (persist) await _settings.setLastDeviceId(id);
        state = state.copyWith(
          status: status,
          connectingTo: null,
          lastConnectedKind: kind,
          scanMessage: status.connected ? null : state.scanMessage,
        );
        return;
      } catch (e) {
        lastError = e;
        debugPrint('[muse] connect attempt $attempt failed: $e');
        if (!simulate && attempt < attempts) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          await _refreshDevice(id);
        }
      }
    }
    debugPrint(
      '[muse] connect failed after $_maxConnectAttempts attempts: '
      '$lastError',
    );
    state = state.copyWith(
      connectingTo: null,
      connectWindowOpen: true,
      scanMessage:
          'Could not connect to $name. Check that it is turned on '
          'and nearby, then try again.',
    );
  }

  /// Run a short scan for [id] so the Rust-side device cache is refreshed with
  /// a fresh peripheral (new adapter/session).  Best-effort: if the device is
  /// not advertising the old cached entry is kept and the next connect attempt
  /// simply reuses it.
  Future<void> _refreshDevice(String id) async {
    try {
      await ensureBtleplugReady();
      await scan(timeoutSecs: BigInt.from(_scanChunkSecs));
    } catch (e) {
      debugPrint('[muse] refresh scan error: $e');
    }
  }

  /// Attempt to reconnect to the last known device; fall back to continuous
  /// scan if the last device ID is missing. Does not auto-connect a different
  /// headset.
  Future<void> _tryReconnect() async {
    debugReconnectCalls++;
    if (_testMode) return;
    if (_reconnectInFlight) return;
    if (!_allowAutoReconnect) return;
    _reconnectInFlight = true;
    try {
      final lastId = _settings.lastDeviceId;
      if (!shouldIgnoreLastDevice(
        lastId,
        debug: _settings.enableSimulatedDevices,
      )) {
        if (isSimDeviceId(lastId!)) {
          final ok = await _tryAutoconnectSim(lastId);
          if (ok || !_allowAutoReconnect) return;
        } else {
          final ok = await _tryAutoconnect(lastId);
          if (ok || !_allowAutoReconnect) return;
        }
      }
      if (_allowAutoReconnect && !state.status.connected) {
        _startDiscoveryForCurrentSource();
      }
    } finally {
      _reconnectInFlight = false;
    }
  }

  /// User / agent disconnect. Stays down for this process; keeps
  /// [Settings.lastDeviceId] so the next launch can auto-connect.
  ///
  /// [persist] is kept for call-site compatibility (agent passes `false`)
  /// and no longer clears the saved id.
  Future<void> disconnectDevice({bool persist = true}) async {
    _allowAutoReconnect = false;
    _scanEnabled = false;
    state = state.copyWith(disconnecting: true);
    try {
      await disconnect();
    } catch (e) {
      debugPrint('[muse] disconnect error: $e');
      _onDisconnected();
    }
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
    _startDiscoveryForCurrentSource();
  }

  void toggleSidebar() =>
      state = state.copyWith(sidebarOpen: !state.sidebarOpen);

  void setSidebar(bool open) => state = state.copyWith(sidebarOpen: open);

  void setCurrentView(AppView view, {bool persist = true}) {
    state = state.copyWith(currentView: view);
    if (persist) _settings.setLastView(view);
  }

  void setConnectWindow({required bool open, ConnectSource? source}) {
    if (source != null) {
      setConnectSource(source);
      if (!open) {
        _scanEnabled = false;
        state = state.copyWith(
          connectWindowOpen: false,
          scanning: false,
          scanMessage: null,
        );
      }
      return;
    }
    if (open) {
      _startDiscoveryForCurrentSource();
    } else {
      _scanEnabled = false;
      state = state.copyWith(
        connectWindowOpen: false,
        scanning: false,
        scanMessage: null,
      );
    }
  }

  void setConnectSource(ConnectSource source) {
    final resolved = resolveConnectSource(
      source,
      debug: _settings.enableSimulatedDevices,
    );
    _scanEnabled = false;
    state = state.copyWith(connectSource: resolved);
    _startDiscoveryForCurrentSource();
  }

  /// Debug mode turned off while Simulator is selected → Muse.
  void onDebugModeChanged(bool enabled) {
    if (!enabled && state.connectSource == ConnectSource.simulator) {
      setConnectSource(ConnectSource.muse);
    }
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
      _startDiscoveryForCurrentSource();
    }
  }

  @visibleForTesting
  void debugSetConnected({
    bool connected = true,
    DeviceKind kind = DeviceKind.muse,
    String name = 'Muse 2',
    String id = 'sim:muse-2',
    String firmware = 'Classic',
  }) {
    if (connected) {
      _allowAutoReconnect = true;
      state = state.copyWith(
        status: ConnectionStatus(
          connected: true,
          name: name,
          id: id,
          firmware: firmware,
        ),
        lastConnectedKind: kind,
      );
    } else {
      state = state.copyWith(
        status: const ConnectionStatus(
          connected: false,
          name: '',
          id: '',
          firmware: '',
        ),
      );
    }
  }

  @visibleForTesting
  void debugAddEvent(MuseEventDto event) {
    _eventController.add(event);
    _onEvent(event);
  }

  @visibleForTesting
  void debugMarkUserDisconnected() {
    _allowAutoReconnect = false;
    _scanEnabled = false;
  }

  @override
  void dispose() {
    _scanEnabled = false;
    _eventSub?.cancel();
    _eventController.close();
    super.dispose();
  }
}

/// Width of the collapsible sidebar (also used as the phone/tablet breakpoint
/// base: wide screens are `>= 3 * kSidebarWidth`).
const double kSidebarWidth = 220.0;

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
    this.connectSource = ConnectSource.muse,
    this.lastConnectedKind,
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

  /// Selected connect-window source (Muse / Neurosity / Simulator).
  final ConnectSource connectSource;

  /// Kind of the last successful connect this process. Null until a device
  /// has been connected. Distinct from [connectSource], which defaults
  /// to Muse even when nothing has been connected.
  final DeviceKind? lastConnectedKind;

  /// Kind used to filter the protocol list: last connected this process.
  /// Null when no device has been connected.
  DeviceKind? get listingDeviceKind => lastConnectedKind;

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
    ConnectSource? connectSource,
    Object? lastConnectedKind = _sentinel,
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
    connectSource: connectSource ?? this.connectSource,
    lastConnectedKind: identical(lastConnectedKind, _sentinel)
        ? this.lastConnectedKind
        : lastConnectedKind as DeviceKind?,
  );
}

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppUiState>((
  ref,
) {
  throw UnimplementedError('Initialize with settings before use');
});

/// 4-ch, 1 s EEG ring for status-bar pad quality. Not the 5 min live cache.
class _PadQualityRing {
  static const _sampleRate = 256.0;
  static const _capacity = 256;
  static const _channelCount = 4;

  final List<_PadChannel?> _channels = List<_PadChannel?>.filled(
    _channelCount,
    null,
  );

  void appendEeg(EegDto dto) {
    final ch = dto.electrode;
    if (ch < 0 || ch > 3) return;
    final buf = _channels[ch] ??= _PadChannel(_capacity);
    final dt = 1.0 / _sampleRate;
    final baseSecs = dto.timestamp / 1000.0;
    for (var i = 0; i < dto.samples.length; i++) {
      buf.add(baseSecs + i * dt, dto.samples[i]);
    }
  }

  Iterable<int> get channels sync* {
    for (var i = 0; i < _channelCount; i++) {
      if (_channels[i] != null) yield i;
    }
  }

  double get latestTimestamp {
    var latest = 0.0;
    for (final buf in _channels) {
      if (buf != null &&
          buf.length > 0 &&
          buf.timestampAt(buf.length - 1) > latest) {
        latest = buf.timestampAt(buf.length - 1);
      }
    }
    return latest;
  }

  List<double> valuesIn(int channel, double startT, double endT) {
    if (channel < 0 || channel > 3) return const [];
    final buf = _channels[channel];
    if (buf == null || buf.length == 0) return const [];
    final lo = buf.lowerBound(startT);
    final hi = buf.upperBound(endT);
    if (lo >= hi) return const [];
    return List<double>.generate(hi - lo, (i) => buf.valueAt(lo + i));
  }

  void clear() {
    _channels.fillRange(0, _channelCount, null);
  }
}

class _PadChannel {
  _PadChannel(int capacity)
    : timestamps = Float64List(capacity),
      values = Float64List(capacity);

  final Float64List timestamps;
  final Float64List values;
  int _head = 0;
  int _count = 0;

  int get length => _count;

  void add(double t, double v) {
    timestamps[_head] = t;
    values[_head] = v;
    _head = (_head + 1) % timestamps.length;
    if (_count < timestamps.length) _count++;
  }

  int _physicalIndex(int i) =>
      (_head - _count + i + timestamps.length) % timestamps.length;

  double timestampAt(int i) => timestamps[_physicalIndex(i)];
  double valueAt(int i) => values[_physicalIndex(i)];

  int lowerBound(double t) {
    var lo = 0, hi = _count;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (timestampAt(mid) < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  int upperBound(double t) {
    var lo = 0, hi = _count;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (timestampAt(mid) <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
