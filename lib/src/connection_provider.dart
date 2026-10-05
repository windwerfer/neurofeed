import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/agent/agent_flags.dart';
import 'package:neurofeed/src/app.dart';
import 'package:neurofeed/src/connect_source.dart';
import 'package:neurofeed/src/lan_multicast_lock.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';
import 'package:neurofeed/src/rust/api/eeg_conditioning.dart';
import 'package:neurofeed/src/rust/api/neurosity_osc.dart';
import 'package:neurofeed/src/settings.dart';

/// Duration of each scan chunk when scanning continuously.
const _scanChunkSecs = 3;

/// Crown LAN list refresh while the connect window is open.
const _crownPollInterval = Duration(seconds: 1);

/// Show the spinner this long before the empty-list copy. Crowns send
/// `/info` every second.
const _crownListenGrace = Duration(seconds: 3);

/// Number of connect attempts before giving up.  The first BLE connect after
/// a cold start / recent re-connect often times out even when the scan just
/// saw the device; a fresh attempt (with a re-scan for a new session) almost
/// always succeeds.
const _maxConnectAttempts = 3;

/// Wait for an in-flight connect to finish before dropping its link.
/// Three BLE attempts are about 18 s each.
const _linkReleaseTimeout = Duration(seconds: 70);

/// Global completer for btleplug initialization on Android.
/// Completes once the native btleplug context is guaranteed ready.
final _btleplugReady = Completer<void>();

/// Ensures btleplug is initialized on Android before any BLE operation.
/// On non-Android platforms, completes immediately.
Future<void> ensureBtleplugReady() async {
  if (_btleplugReady.isCompleted) return;

  if (defaultTargetPlatform == TargetPlatform.android) {
    const channel = MethodChannel('neurofeed/init');
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
            auxChannels: 0,
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
          connectSource: neurofeedAgentEnabled
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
  int _crownDiscoveryGeneration = 0;

  /// Bumped on device-type change and user disconnect. [connectTo] drops a
  /// result whose epoch is older than this, so a connect already in flight
  /// cannot publish over the new choice.
  int _linkEpoch = 0;

  /// Epoch of the connect attempt allowed to publish a Connected event.
  /// A device-type change bumps [_linkEpoch] so a late event cannot mark the
  /// new scan as connected.
  int _acceptConnectedEpoch = 0;

  /// User disconnect during a device-type change keeps the connect window
  /// open; the new category then scans in that same window.
  bool _holdConnectWindow = false;

  /// Status-bar / agent disconnect closes the window even if a device-type
  /// change is holding it open.
  bool _closeWindowOnDisconnect = false;

  int _museScanGeneration = 0;
  Future<void>? _crownLoop;
  Future<void>? _connectInFlight;
  Future<void>? _switchChain;
  bool _debugDisconnectFails = false;
  bool _crownDiscoveryActive = false;
  bool _multicastLockHeld = false;
  final Completer<void> _initDone = Completer<void>();
  final StreamController<MuseEventDto> _eventController =
      StreamController<MuseEventDto>.broadcast();

  /// Lost-link and launch auto-reconnect. Cleared by a user disconnect
  /// (status bar / agent) until the next [connectTo].
  bool get allowAutoReconnect => _allowAutoReconnect;

  @visibleForTesting
  int debugReconnectCalls = 0;

  Stream<MuseEventDto> get eventStream => _eventController.stream;

  Future<void> get initDone => _initDone.future;

  Future<void> _init() async {
    try {
      await ensureBtleplugReady();
      final stream = subscribeEvents();
      _eventSub = stream.listen((event) {
        if (_dropStaleConnected(event)) return;
        _eventController.add(event);
        _onEvent(event);
        if (event is MuseEventDto_Bands) _saveMainsDecision();
      });

      final status = await getStatus();
      if (status.connected) {
        state = state.copyWith(status: status);
        return;
      }

      if (neurofeedAgentEnabled) {
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
        } else if (_settings.lastDeviceKind == DeviceKind.neurosity) {
          unawaited(_runCrownDiscovery(lookFor: lastId));
          return;
        } else {
          // Unbounded scan for lastDeviceId; do not block initDone on it.
          unawaited(_tryAutoconnect(lastId));
          return;
        }
      }

      _startDiscoveryForCurrentSource();
    } catch (e) {
      debugPrint('[neurofeed] init error: $e');
      state = state.copyWith(scanMessage: 'Init error: $e');
    } finally {
      if (!_initDone.isCompleted) _initDone.complete();
    }
  }

  /// Connect a `sim:*` catalog row without BLE. Debug mode only.
  Future<bool> _tryAutoconnectSim(String lastId) async {
    final row = simulatorCatalogRow(lastId);
    if (row == null) return false;
    debugPrint('[neurofeed] autoconnect: simulator $lastId');
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
    debugPrint('[neurofeed] autoconnect: looking for $lastId');
    _scanEnabled = true;
    state = state.copyWith(
      connectWindowOpen: true,
      scanning: true,
      scanMessage: 'Looking for last device…',
    );
    try {
      if (!await requestBlePermissions()) {
        debugPrint('[neurofeed] autoconnect: BLE permissions not granted');
        state = state.copyWith(
          scanning: false,
          scanMessage: 'BLE permissions not granted',
        );
        return false;
      }
      var chunks = 0;
      while (_scanEnabled &&
          _allowAutoReconnect &&
          !state.status.connected &&
          state.connectSource == ConnectSource.muse) {
        await ensureBtleplugReady();
        if (!_scanEnabled ||
            !_allowAutoReconnect ||
            state.status.connected ||
            state.connectSource != ConnectSource.muse) {
          break;
        }
        final devices = await scan(timeoutSecs: BigInt.from(_scanChunkSecs));
        if (!_scanEnabled ||
            !_allowAutoReconnect ||
            state.status.connected ||
            state.connectSource != ConnectSource.muse) {
          break;
        }
        final match =
            devices.where((d) => d.id == lastId).firstOrNull ??
            devices.where((d) => d.name == lastId).firstOrNull;
        if (match != null) {
          if (state.connectSource != ConnectSource.muse) return false;
          debugPrint(
            '[neurofeed] autoconnect: found ${match.name}, connecting',
          );
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
      debugPrint('[neurofeed] autoconnect error: $e');
      if (_scanEnabled && _allowAutoReconnect) {
        state = state.copyWith(scanning: false, scanMessage: 'Scan error: $e');
      }
    }
    return state.status.connected;
  }

  /// Open the connect window and start discovery for [state.connectSource].
  /// A live link skips the scan: BLE / OSC / the simulator catalog must not
  /// run under a headset that is still connected.
  void _startDiscoveryForCurrentSource() {
    if (state.status.connected || state.connectingTo != null) {
      state = state.copyWith(connectWindowOpen: true);
      return;
    }
    if (_testMode && state.connectSource != ConnectSource.simulator) {
      _scanEnabled = true;
      state = state.copyWith(
        connectWindowOpen: true,
        scanning: true,
        devices: const [],
        scanMessage: null,
      );
      return;
    }
    switch (state.connectSource) {
      case ConnectSource.muse:
        unawaited(_startContinuousScan());
      case ConnectSource.neurosity:
        unawaited(_runCrownDiscovery());
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
    if (state.status.connected || state.connectingTo != null) return;
    final generation = ++_museScanGeneration;
    bool ownScan() =>
        generation == _museScanGeneration &&
        state.connectSource == ConnectSource.muse;
    _scanEnabled = true;
    debugPrint('[neurofeed] continuous scan starting');
    state = state.copyWith(
      connectWindowOpen: true,
      scanning: true,
      devices: const [],
      scanMessage: 'Scanning…',
    );

    try {
      if (!await requestBlePermissions()) {
        debugPrint('[neurofeed] continuous scan: BLE permissions not granted');
        if (ownScan()) {
          state = state.copyWith(
            scanning: false,
            scanMessage: 'BLE permissions not granted',
          );
        }
        return;
      }

      var allDevices = <DeviceInfo>[];

      while (_scanEnabled && !state.status.connected && ownScan()) {
        await ensureBtleplugReady();
        if (!_scanEnabled || state.status.connected || !ownScan()) break;
        final devices = await scan(timeoutSecs: BigInt.from(_scanChunkSecs));
        if (!_scanEnabled || state.status.connected || !ownScan()) break;

        final museOnly = keepMuseBleDevices(devices);
        for (final d in museOnly) {
          if (!allDevices.any((x) => x.id == d.id)) {
            allDevices = [...allDevices, d];
          }
        }
        debugPrint(
          '[neurofeed] scan chunk: ${devices.length} device(s) from rust, '
          '${museOnly.length} muse, ${allDevices.length} unique total',
        );
        state = state.copyWith(
          devices: allDevices,
          scanMessage: '${allDevices.length} device(s) found',
        );
      }

      if (state.status.connected) {
        debugPrint('[neurofeed] continuous scan stopped (connected)');
      } else if (ownScan()) {
        debugPrint('[neurofeed] continuous scan stopped (no connection)');
        state = state.copyWith(scanning: false);
      }
    } catch (e) {
      debugPrint('[neurofeed] continuous scan error: $e');
      if (ownScan()) {
        state = state.copyWith(scanning: false, scanMessage: 'Scan error: $e');
      }
    }
  }

  /// OSC LAN discovery for the Neurosity source. Lists Crowns seen on the
  /// network until the window closes, the source changes, or a device
  /// connects. With [lookFor], connects that Crown id when it appears.
  Future<bool> _runCrownDiscovery({String? lookFor}) async {
    if (state.status.connected || state.connectingTo != null) {
      return state.status.connected;
    }
    final generation = ++_crownDiscoveryGeneration;
    final done = Completer<void>();
    _crownLoop = done.future;
    try {
      return await _runCrownDiscoveryBody(generation, lookFor: lookFor);
    } finally {
      if (!done.isCompleted) done.complete();
      if (identical(_crownLoop, done.future)) _crownLoop = null;
    }
  }

  Future<bool> _runCrownDiscoveryBody(int generation, {String? lookFor}) async {
    _scanEnabled = true;
    state = state.copyWith(
      connectSource: ConnectSource.neurosity,
      connectWindowOpen: true,
      scanning: true,
      devices: const [],
      scanMessage: lookFor == null ? null : 'Looking for last device…',
    );
    bool active() =>
        _scanEnabled &&
        generation == _crownDiscoveryGeneration &&
        state.connectSource == ConnectSource.neurosity &&
        !state.status.connected &&
        (lookFor == null || _allowAutoReconnect);
    final started = DateTime.now();
    try {
      if (!active()) return false;
      _setCrownDiscoveryActive(true);
      await startCrownDiscovery();
      if (!active()) return false;
      while (active()) {
        final crowns = await discoveredCrowns();
        if (!active()) break;
        final match = crowns.where((d) => d.id == lookFor).firstOrNull;
        if (match != null) {
          await connectTo(match);
          if (state.status.connected || !_allowAutoReconnect) break;
          _scanEnabled = true;
        }
        final elapsed = DateTime.now().difference(started);
        state = state.copyWith(
          devices: crowns,
          scanning:
              lookFor != null ||
              (crowns.isEmpty && elapsed < _crownListenGrace),
          scanMessage: lookFor == null
              ? state.scanMessage
              : 'Searching… (${elapsed.inSeconds}s)',
        );
        await Future<void>.delayed(_crownPollInterval);
      }
    } catch (e) {
      debugPrint('[neurofeed] crown discovery error: $e');
      if (generation == _crownDiscoveryGeneration) {
        state = state.copyWith(
          scanning: false,
          scanMessage: 'Discovery error: $e',
        );
      }
    } finally {
      if (generation == _crownDiscoveryGeneration) {
        _setCrownDiscoveryActive(false);
        try {
          await stopCrownDiscovery();
        } catch (e) {
          debugPrint('[neurofeed] stop crown discovery: $e');
        }
        if (!state.status.connected &&
            state.connectSource == ConnectSource.neurosity) {
          state = state.copyWith(scanning: false);
        }
      }
    }
    return state.status.connected;
  }

  /// Stop OSC discovery before a new category starts its own scan.
  /// The in-flight loop is the only caller of [stopCrownDiscovery] when it
  /// still owns the generation; after it exits, this stops a start that
  /// already passed that check.
  Future<void> _abandonCrownDiscovery() async {
    _crownDiscoveryGeneration++;
    final pending = _crownLoop;
    if (pending != null) {
      await pending.timeout(_linkReleaseTimeout, onTimeout: () {});
    }
    if (!_crownDiscoveryActive && pending == null) return;
    _setCrownDiscoveryActive(false);
    if (_testMode) return;
    try {
      await stopCrownDiscovery();
    } catch (e) {
      debugPrint('[neurofeed] stop crown discovery: $e');
    }
  }

  void _setCrownDiscoveryActive(bool active) {
    _crownDiscoveryActive = active;
    _syncMulticastLock();
  }

  /// Hold the Android multicast lock while Crown OSC is being received:
  /// during LAN discovery and while a real Crown is connected.
  void _syncMulticastLock() {
    final crownStreaming =
        state.status.connected &&
        state.lastConnectedKind == DeviceKind.neurosity &&
        !isSimDeviceId(state.status.id);
    final want = _crownDiscoveryActive || crownStreaming;
    if (want == _multicastLockHeld) return;
    _multicastLockHeld = want;
    unawaited(setMulticastLock(held: want));
  }

  bool _dropStaleConnected(MuseEventDto event) {
    if (event is! MuseEventDto_Connected) return false;
    if (_acceptConnectedEpoch == _linkEpoch) return false;
    debugPrint('[neurofeed] ignored stale connected event');
    return true;
  }

  void _onEvent(MuseEventDto event) {
    switch (event) {
      case MuseEventDto_Connected():
        debugPrint('[neurofeed] event: connected ${event.field0}');
        _scanEnabled = false;
        state = state.copyWith(
          status: state.status.copyWith(connected: true, name: event.field0),
          connectWindowOpen: false,
          scanning: false,
          connectingTo: null,
        );
      case MuseEventDto_Disconnected():
        debugPrint('[neurofeed] event: disconnected');
        _onDisconnected();
      case MuseEventDto_PadQuality():
        final q = event.field0;
        final recordSource = state.lastConnectedKind == DeviceKind.neurosity;
        state = state.copyWith(
          signalQuality: q.values.toList(),
          signalQualitySource: recordSource ? q.source : null,
          crownSignalQuality: recordSource ? q.crown?.toList() : null,
        );
      case MuseEventDto_Gestures():
        state = state.copyWith(gestures: event.field0);
      case MuseEventDto_Telemetry():
        state = state.copyWith(
          telemetry: event.field0,
          batteryLevel: event.field0.batteryLevel,
        );
      default:
        break;
    }
  }

  /// Save live mains detection per device (settings) whenever it decides
  /// or changes; also while a recording keeps its own notch frozen.
  void _saveMainsDecision() {
    final id = state.status.id;
    if (id.isEmpty) return;
    final decision = liveMainsDecision()?.toList();
    if (decision == null) return;
    final key = '$id $decision';
    if (key == _mainsSavedKey) return;
    _mainsSavedKey = key;
    if (listEquals(_settings.savedMainsFor(id), decision)) return;
    debugPrint('[neurofeed] mains decision saved for $id: $decision Hz');
    unawaited(_settings.setSavedMains(id, decision));
  }

  String? _mainsSavedKey;

  void _onDisconnected() {
    // A second Disconnected (muse-rs watcher after our own sink event) must
    // not abort an in-flight reconnect or restart one the user already
    // cancelled.
    if (!state.status.connected && !state.disconnecting) {
      return;
    }
    const idle = ConnectionStatus(
      connected: false,
      name: '',
      id: '',
      firmware: '',
      auxChannels: 0,
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
        signalQualitySource: null,
        crownSignalQuality: null,
        gestures: null,
        telemetry: telemetry,
        connectWindowOpen: _holdConnectWindow && !_closeWindowOnDisconnect,
        connectingTo: null,
        scanning: false,
        scanMessage: null,
        disconnecting: false,
        devices: _holdConnectWindow ? const <DeviceInfo>[] : state.devices,
      );
      _syncMulticastLock();
      return;
    }
    state = state.copyWith(
      status: idle,
      batteryLevel: 0,
      signalQuality: null,
      signalQualitySource: null,
      crownSignalQuality: null,
      gestures: null,
      telemetry: telemetry,
      connectWindowOpen: true,
      connectingTo: null,
      scanning: false,
      scanMessage: 'Reconnecting…',
      disconnecting: false,
    );
    _syncMulticastLock();
    unawaited(_tryReconnect());
  }

  /// Muse pad quality. Keep in sync with Rust
  /// `features::pad_quality_from_std_and_noise`, which also scores Neurosity.
  bool _deviceMatchesSource(DeviceInfo device) {
    final sim = isSimDeviceId(device.id);
    switch (state.connectSource) {
      case ConnectSource.simulator:
        return sim;
      case ConnectSource.muse:
        return !sim &&
            device.kind == DeviceKind.muse &&
            !isNeurosityHeadsetName(device.name);
      case ConnectSource.neurosity:
        return !sim && device.kind == DeviceKind.neurosity;
    }
  }

  Future<void> connectTo(DeviceInfo device, {bool persist = true}) async {
    if (state.connectingTo != null || _connectInFlight != null) return;
    if (!_deviceMatchesSource(device)) {
      debugPrint(
        '[neurofeed] connect ignored for ${device.id} '
        'while source=${state.connectSource.name}',
      );
      return;
    }
    final epoch = _linkEpoch;
    final done = Completer<void>();
    _connectInFlight = done.future;
    try {
      await _connectToBody(device, persist: persist, epoch: epoch);
    } finally {
      if (identical(_connectInFlight, done.future)) {
        _connectInFlight = null;
      }
      if (!done.isCompleted) done.complete();
    }
  }

  Future<void> _connectToBody(
    DeviceInfo device, {
    required bool persist,
    required int epoch,
  }) async {
    if (epoch != _linkEpoch || !_deviceMatchesSource(device)) return;
    _acceptConnectedEpoch = epoch;
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
      if (epoch != _linkEpoch || !_deviceMatchesSource(device)) {
        await _dropSupersededConnect(name);
        return;
      }
      debugPrint(
        '[neurofeed] connect attempt $attempt/$attempts — '
        '$name ($id) kind=$kind simulate=$simulate',
      );
      state = state.copyWith(scanMessage: 'Connecting… (attempt $attempt)');
      try {
        final savedMains = _settings.savedMainsFor(id);
        setSavedMains(
          notchHz: savedMains == null ? null : Float64List.fromList(savedMains),
        );
        final qualitySource = _settings.crownQualitySource;
        final status = await connectWithOptions(
          deviceId: id,
          kind: kind,
          simulate: simulate,
          recordAux: true,
          qualitySource: qualitySource,
        );
        if (epoch != _linkEpoch || !_deviceMatchesSource(device)) {
          await _dropSupersededConnect(name);
          return;
        }
        debugPrint(
          '[neurofeed] connect returned: connected=${status.connected}',
        );
        if (persist) await _settings.setLastDevice(id, kind);
        if (epoch != _linkEpoch || !_deviceMatchesSource(device)) {
          await _dropSupersededConnect(name);
          return;
        }
        state = state.copyWith(
          status: status,
          connectingTo: null,
          lastConnectedKind: kind,
          crownQualitySource: kind == DeviceKind.neurosity
              ? qualitySource
              : null,
          scanMessage: status.connected ? null : state.scanMessage,
        );
        _syncMulticastLock();
        return;
      } catch (e) {
        if (epoch != _linkEpoch) {
          await _dropSupersededConnect(name);
          return;
        }
        lastError = e;
        debugPrint('[neurofeed] connect attempt $attempt failed: $e');
        if (!simulate && attempt < attempts) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          if (epoch != _linkEpoch) {
            await _dropSupersededConnect(name);
            return;
          }
          if (kind == DeviceKind.muse) await _refreshDevice(id);
        }
      }
    }
    if (epoch != _linkEpoch) {
      await _dropSupersededConnect(name);
      return;
    }
    debugPrint(
      '[neurofeed] connect failed after $_maxConnectAttempts attempts: '
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

  Future<void> _dropSupersededConnect(String name) async {
    debugPrint('[neurofeed] connect dropped after device-type change');
    if (state.connectingTo == name) {
      state = state.copyWith(connectingTo: null);
    }
    if (_testMode) return;
    if (state.status.connected && _acceptConnectedEpoch == _linkEpoch) return;
    try {
      await disconnect();
    } catch (e) {
      debugPrint('[neurofeed] stale connect disconnect: $e');
    }
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
      debugPrint('[neurofeed] refresh scan error: $e');
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
        } else if (_settings.lastDeviceKind == DeviceKind.neurosity) {
          final ok = await _runCrownDiscovery(lookFor: lastId);
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
    _closeWindowOnDisconnect = true;
    _scanEnabled = false;
    _museScanGeneration++;
    _linkEpoch++;
    await _abandonCrownDiscovery();
    final pending = _connectInFlight;
    if (state.status.connected || state.connectingTo != null) {
      state = state.copyWith(disconnecting: true);
    }
    if (pending != null) {
      await pending.timeout(_linkReleaseTimeout, onTimeout: () {});
    }
    final dropped = await _invokeDisconnect();
    if (!dropped || state.status.connected || state.disconnecting) {
      _onDisconnected();
    }
  }

  /// Rust disconnect, or a test-mode stand-in. False when the link was left up.
  Future<bool> _invokeDisconnect() async {
    if (_debugDisconnectFails) {
      _debugDisconnectFails = false;
      return false;
    }
    if (_testMode) {
      if (state.status.connected || state.disconnecting) {
        _onDisconnected();
      }
      return !state.status.connected;
    }
    try {
      await disconnect();
      return true;
    } catch (e) {
      debugPrint('[neurofeed] disconnect error: $e');
      try {
        await disconnect();
        return true;
      } catch (e2) {
        debugPrint('[neurofeed] disconnect retry error: $e2');
        return false;
      }
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

  Future<bool> setConnectWindow({
    required bool open,
    ConnectSource? source,
  }) async {
    if (source != null) {
      final ok = await switchConnectSource(source);
      if (!ok) return false;
      if (!open) {
        _scanEnabled = false;
        state = state.copyWith(
          connectWindowOpen: false,
          scanning: false,
          scanMessage: null,
        );
      }
      return true;
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
    return true;
  }

  /// Change device type. A live link is disconnected first (no lost-link
  /// reconnect). Discovery for [source] starts only after that link is down.
  /// False means the headset is still up and the type was left unchanged.
  Future<bool> switchConnectSource(ConnectSource source) {
    final run = (_switchChain ?? Future<void>.value()).then(
      (_) => _switchConnectSource(source),
    );
    _switchChain = run.then((_) {}, onError: (Object _, StackTrace _) {});
    return run;
  }

  Future<bool> _switchConnectSource(ConnectSource source) async {
    final resolved = resolveConnectSource(
      source,
      debug: _settings.enableSimulatedDevices,
    );
    if (resolved == state.connectSource) return true;
    final released = await _releaseLinkForSourceSwitch();
    if (!released) return false;
    if (state.status.connected || state.connectingTo != null) return false;
    state = state.copyWith(connectSource: resolved);
    _startDiscoveryForCurrentSource();
    return true;
  }

  /// Stop scans and drop the link before [switchConnectSource] changes type.
  /// Waits out a connect that already started so its result cannot land after
  /// the new scan, then disconnects whatever that connect left active.
  Future<bool> _releaseLinkForSourceSwitch() async {
    final linked =
        state.status.connected ||
        state.connectingTo != null ||
        state.disconnecting;
    _holdConnectWindow = true;
    _closeWindowOnDisconnect = false;
    _scanEnabled = false;
    _museScanGeneration++;
    _linkEpoch++;
    final epoch = _linkEpoch;
    if (linked) _allowAutoReconnect = false;
    await _abandonCrownDiscovery();
    final pending = _connectInFlight;
    try {
      if (pending != null) {
        await pending.timeout(_linkReleaseTimeout, onTimeout: () {});
      }
      if (epoch != _linkEpoch) return false;
      final needsDrop =
          state.status.connected ||
          state.connectingTo != null ||
          pending != null;
      if (!needsDrop) return true;
      if (state.status.connected || state.connectingTo != null) {
        state = state.copyWith(
          disconnecting: true,
          scanning: false,
          scanMessage: null,
        );
      }
      final dropped = await _invokeDisconnect();
      if (state.connectingTo != null) {
        state = state.copyWith(connectingTo: null);
      }
      if (!dropped || state.status.connected || state.disconnecting) {
        if (dropped) _onDisconnected();
      }
      final idle = !state.status.connected && state.connectingTo == null;
      if (!idle) {
        if (state.status.connected) _allowAutoReconnect = true;
        state = state.copyWith(
          disconnecting: false,
          scanMessage:
              'Could not disconnect. Stay on this device and try again.',
        );
        return false;
      }
      return true;
    } finally {
      _holdConnectWindow = false;
    }
  }

  /// Debug mode turned off while Simulator is selected → Muse.
  /// Disconnects a live simulator first, same as a device-type change.
  Future<bool> onDebugModeChanged(bool enabled) {
    if (!enabled && state.connectSource == ConnectSource.simulator) {
      return switchConnectSource(ConnectSource.muse);
    }
    return Future<bool>.value(true);
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
    int auxChannels = 0,
  }) {
    if (connected) {
      _allowAutoReconnect = true;
      state = state.copyWith(
        status: ConnectionStatus(
          connected: true,
          name: name,
          id: id,
          firmware: firmware,
          auxChannels: auxChannels,
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
          auxChannels: 0,
        ),
      );
    }
  }

  @visibleForTesting
  void debugAddEvent(MuseEventDto event) {
    if (_dropStaleConnected(event)) return;
    _eventController.add(event);
    _onEvent(event);
  }

  @visibleForTesting
  void debugMarkUserDisconnected() {
    _allowAutoReconnect = false;
    _scanEnabled = false;
  }

  @visibleForTesting
  void debugSetConnecting(String name) {
    state = state.copyWith(connectingTo: name);
  }

  @visibleForTesting
  void debugFailNextDisconnect() {
    _debugDisconnectFails = true;
  }

  @override
  void dispose() {
    if (!mounted) return;
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
    this.signalQualitySource,
    this.crownSignalQuality,
    this.gestures,
    this.scanMessage,
    this.connectingTo,
    this.disconnecting = false,
    this.connectSource = ConnectSource.muse,
    this.lastConnectedKind,
    this.crownQualitySource,
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

  /// Neurosity only: which score filled [signalQuality] this second.
  final QualitySource? signalQualitySource;

  /// Neurosity only: Crown per-pad 1 Hz means (0..1) when the source is Crown.
  final List<double>? crownSignalQuality;

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

  /// Pad quality source the last Neurosity connect used ([lastConnectedKind]
  /// Neurosity). Null after a Muse connect or before any connect.
  final QualitySource? crownQualitySource;

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
    Object? signalQualitySource = _sentinel,
    Object? crownSignalQuality = _sentinel,
    Object? gestures = _sentinel,
    Object? scanMessage = _sentinel,
    Object? connectingTo = _sentinel,
    bool? disconnecting,
    ConnectSource? connectSource,
    Object? lastConnectedKind = _sentinel,
    Object? crownQualitySource = _sentinel,
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
    signalQualitySource: identical(signalQualitySource, _sentinel)
        ? this.signalQualitySource
        : signalQualitySource as QualitySource?,
    crownSignalQuality: identical(crownSignalQuality, _sentinel)
        ? this.crownSignalQuality
        : crownSignalQuality as List<double>?,
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
    crownQualitySource: identical(crownQualitySource, _sentinel)
        ? this.crownQualitySource
        : crownQualitySource as QualitySource?,
  );
}

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppUiState>((
  ref,
) {
  throw UnimplementedError('Initialize with settings before use');
});
