import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:muse_ml/src/streaming/streaming_brainflow.dart';
import 'package:muse_ml/src/streaming/streaming_lsl.dart';
import 'package:muse_ml/src/streaming/streaming_mixer.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';
import 'package:muse_ml/src/streaming/streaming_osc.dart';

/// Immutable snapshot of the streaming UI state.
@immutable
class StreamingUiState {
  const StreamingUiState({
    required this.connected,
    required this.streaming,
    required this.protocol,
    required this.enabled,
    required this.groups,
    required this.bytesSent,
    required this.packetsSent,
    this.streamingSince,
    this.error,
  });

  final bool connected;
  final bool streaming;
  final StreamProtocol protocol;
  final bool enabled;

  /// Groups whose streams are active right now ([] when idle).
  final List<StreamGroupDef> groups;

  final int bytesSent;
  final int packetsSent;
  final DateTime? streamingSince;
  final String? error;

  Duration? get elapsed =>
      streamingSince == null ? null : DateTime.now().difference(streamingSince!);
}

/// Three-state indicator for the sidebar entry and status bar: no dot when
/// streaming is off, amber when enabled but no device is connected (armed),
/// green while data is actually streaming.
enum StreamBadgeState { off, armed, live }

StreamBadgeState streamBadgeOf(StreamingUiState s) =>
    s.streaming
        ? StreamBadgeState.live
        : s.enabled
        ? StreamBadgeState.armed
        : StreamBadgeState.off;

/// Coordinates network streaming: subscribes to the Muse event stream, mixes
/// per-group channels and pushes rows into the active protocol sender.
/// Streaming starts when a device connects (and the selected protocol is
/// enabled) and stops on disconnect.
class StreamingController extends Notifier<StreamingUiState> {
  late final Settings _settings;
  StreamSubscription<MuseEventDto>? _eventSub;
  Timer? _statsTimer;
  bool _connected = false;
  StreamingConfig? _config;
  StreamSender? _sender;
  final Map<String, GroupMixer> _mixers = {};
  int _bytesSent = 0;
  int _packetsSent = 0;
  DateTime? _streamingSince;
  String _deviceName = '';
  String? _lastError;

  @override
  StreamingUiState build() {
    _settings = ref.read(settingsProvider);
    _eventSub ??= ref
        .read(appStateProvider.notifier)
        .eventStream
        .listen(_onEvent);
    ref.onDispose(() {
      _eventSub?.cancel();
      _statsTimer?.cancel();
      unawaited(_stop());
    });
    return _snapshot(streaming: false);
  }

  StreamingUiState _snapshot({required bool streaming}) {
    // Intent (enabled/protocol) falls back to settings before any device has
    // connected (no `_config` yet) so the armed indicator shows the on/off
    // toggle state from the very first frame.
    final settings = _settings;
    final protocol =
        _config?.protocol ?? StreamProtocol.fromName(settings.streamProtocolName);
    final enabled = _config?.enabled ??
        switch (protocol) {
          StreamProtocol.osc => settings.oscEnabled,
          StreamProtocol.lsl => settings.lslEnabled,
          StreamProtocol.brainflow => settings.brainflowEnabled,
        };
    return StreamingUiState(
      connected: _connected,
      streaming: streaming,
      protocol: protocol,
      enabled: enabled,
      groups: streaming ? (_config?.groups ?? const []) : const [],
      bytesSent: _bytesSent,
      packetsSent: _packetsSent,
      streamingSince: streaming ? _streamingSince : null,
      error: streaming ? null : _lastError,
    );
  }

  void _onEvent(MuseEventDto event) {
    switch (event) {
      case MuseEventDto_Connected():
        _connected = true;
        _deviceName = event.field0;
        _config = StreamingConfig.fromSettings(_settings);
        state = _snapshot(streaming: false);
        if (_config!.enabled) {
          unawaited(_start(_config!));
        }
      case MuseEventDto_Disconnected():
        _connected = false;
        unawaited(_stop());
        state = _snapshot(streaming: false);
      case MuseEventDto_Eeg():
        _route(event.field0.electrode, event.field0.timestamp, 'eeg',
            event.field0.samples);
      case MuseEventDto_Ppg():
        _route(event.field0.channel, event.field0.timestamp, 'ppg',
            event.field0.samples);
      case MuseEventDto_Accelerometer():
        _routeXyz(event.field0.samples, 'imu', 0);
      case MuseEventDto_Gyroscope():
        _routeXyz(event.field0.samples, 'imu', 3);
      case MuseEventDto_Bands():
        _routeBands(event.field0);
      default:
        break;
    }
  }

  void _route(
      int channel, double timestamp, String groupId, List<double> samples) {
    final mixer = _mixers[groupId];
    if (mixer == null) return;
    mixer.add(channel, timestamp, samples);
    _pump(mixer);
  }

  void _routeXyz(List<XyzDto> samples, String groupId, int firstChannel) {
    final mixer = _mixers[groupId];
    if (mixer == null) return;
    final ts = mixer.lastTimestamp > 0
        ? mixer.lastTimestamp
        : DateTime.now().millisecondsSinceEpoch / 1000.0;
    for (final xyz in samples) {
      mixer.add(firstChannel, ts, [xyz.x]);
      mixer.add(firstChannel + 1, ts, [xyz.y]);
      mixer.add(firstChannel + 2, ts, [xyz.z]);
    }
    _pump(mixer);
  }

  void _routeBands(BandsDto bands) {
    final mixer = _mixers['bands'];
    if (mixer == null) return;
    final base = bands.electrode * 5;
    mixer.add(base, bands.timestamp, [bands.delta]);
    mixer.add(base + 1, bands.timestamp, [bands.theta]);
    mixer.add(base + 2, bands.timestamp, [bands.alpha]);
    mixer.add(base + 3, bands.timestamp, [bands.beta]);
    mixer.add(base + 4, bands.timestamp, [bands.gamma]);
    _pump(mixer);
  }

  void _pump(GroupMixer mixer) {
    final sender = _sender;
    if (sender == null) return;
    for (final sample in mixer.drain(drainLimit)) {
      sender.push(sample);
    }
  }

  Future<void> _start(StreamingConfig config) async {
    await _stop();
    _config = config;
    _lastError = null;
    _mixers
      ..clear()
      ..addAll({
        for (final g in config.groups) g.id: GroupMixer(g)..reset(),
      });
    try {
      switch (config.protocol) {
        case StreamProtocol.osc:
          final osc = OscStreamer(config);
          await osc.start();
          _sender = osc;
        case StreamProtocol.lsl:
          final lsl = LslStreamer(config);
          await lsl.start(_deviceName);
          _sender = lsl;
        case StreamProtocol.brainflow:
          final bf = BrainflowStreamer(config);
          await bf.start();
          _sender = bf;
      }
    } catch (e) {
      _lastError = '${config.protocol.label} start failed: $e';
      debugPrint('[streaming] $_lastError');
      _sender = null;
    }
    final sender = _sender;
    if (sender == null) {
      state = _snapshot(streaming: false);
      return;
    }
    _streamingSince = DateTime.now();
    _bytesSent = 0;
    _packetsSent = 0;
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _bytesSent = sender.bytesSent;
      _packetsSent = sender.packetsSent;
      state = _snapshot(streaming: true);
    });
    state = _snapshot(streaming: true);
    debugPrint('[streaming] ${config.protocol.name} streaming '
        '(${config.groups.map((g) => g.id).join(', ')})');
  }

  Future<void> _stop() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    final sender = _sender;
    _sender = null;
    if (sender != null) await sender.stop();
    _mixers.clear();
    _streamingSince = null;
  }

  /// Called when the user changes protocol settings while the app runs.
  /// Persists and restarts the stream (stop + start) if it was running.
  Future<void> reconfigure() async {
    final wasStreaming = state.streaming;
    if (wasStreaming) await _stop();
    final config = StreamingConfig.fromSettings(_settings);
    _config = config;
    state = _snapshot(streaming: false);
    if (_connected && config.enabled) {
      unawaited(_start(config));
    }
  }

  static const drainLimit = 64;
}

/// Provides the [StreamingController]. Settings are read from
/// [settingsProvider]. The notifier is only constructed while the Streaming
/// view is on screen (or after it was first visited); streaming continues
/// between views while the provider stays alive.
final streamingControllerProvider =
    NotifierProvider<StreamingController, StreamingUiState>(
        StreamingController.new);