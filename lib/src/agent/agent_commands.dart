import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/agent/agent_protocol.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/feedback/feedback_state.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/protocol_catalog.dart';
import 'package:muse_ml/src/monitor/monitor_providers.dart';
import 'package:muse_ml/src/monitor/monitor_state.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:muse_ml/src/version.dart';

class AgentCommands {
  AgentCommands(this._container);

  final ProviderContainer _container;

  AppStateNotifier get _app => _container.read(appStateProvider.notifier);

  FeedbackStateNotifier get _feedback =>
      _container.read(feedbackStateProvider.notifier);

  Future<AgentHttpResult> handle({
    required String method,
    required String path,
    Map<String, Object?>? body,
  }) async {
    final m = method.toUpperCase();
    if (m == 'GET' && path == '/health') {
      return AgentHttpResult(200, {'ok': true, 'version': appVersion});
    }
    if (m == 'GET' && path == '/state') {
      return AgentHttpResult(200, _stateJson());
    }
    if (m != 'POST') {
      return agentError(404, 'unknown_route', path);
    }
    return switch (path) {
      '/view' => _view(body),
      '/sidebar' => _sidebar(body),
      '/connect-window' => _connectWindow(body),
      '/connect' => _connect(body),
      '/disconnect' => _disconnect(),
      '/session/select' => _select(body),
      '/session/duration' => _duration(body),
      '/session/start' => _start(body),
      '/session/pause' => _pause(),
      '/session/resume' => _resume(),
      '/session/end' => _end(),
      '/session/reset' => _reset(),
      '/session/override' => _override(body),
      '/session/feature' => _feature(body),
      '/record/start' => _recordStart(),
      '/record/stop' => _recordStop(),
      _ => agentError(404, 'unknown_route', path),
    };
  }

  AgentHttpResult _ok() => AgentHttpResult(200, _stateJson());

  Map<String, Object?> _stateJson() {
    final app = _container.read(appStateProvider);
    final fb = _container.read(feedbackStateProvider);
    final settings = _container.read(settingsProvider);
    final mon = _container.read(monitorControllerProvider);
    return {
      'ok': true,
      'view': app.currentView.name,
      'sidebarOpen': app.sidebarOpen,
      'connectWindowOpen': app.connectWindowOpen,
      'connectSource': app.connectSource.name,
      'debug': settings.enableSimulatedDevices,
      'connected': app.status.connected,
      'deviceId': app.status.id,
      'deviceName': app.status.name,
      'kind': app.lastConnectedKind?.name,
      'phase': fb.phase.name,
      'protocol': fb.protocol,
      'elapsedSeconds': fb.elapsedSeconds,
      'captureKind': mon.kind.name,
      'captureElapsedSeconds': mon.captureElapsedSeconds,
      'durationMinutes': fb.durationMinutes,
      'audioInitFailed': fb.audioInitFailed,
      'scanMessage': app.scanMessage,
      'overrideEnabled': fb.featureOverrideEnabled,
      'override': fb.featureOverrides,
      'probeFeatures': _feedback.probeFeatureIds,
      'percentile': _feedback.rewardLastPercentile,
      'inTarget': _feedback.rewardLastInTarget,
      'rewardValue': _feedback.rewardLastNative,
      'warningActive': _feedback.guardWarningActive,
      'threshold': fb.currentThreshold,
    };
  }

  Future<AgentHttpResult> _view(Map<String, Object?>? body) async {
    final view = parseAppView(body?['view'] as String?);
    if (view == null) {
      return agentError(404, 'unknown_view', body?['view'] as String?);
    }
    _app.setCurrentView(view, persist: false);
    return _ok();
  }

  Future<AgentHttpResult> _sidebar(Map<String, Object?>? body) async {
    final open = body?['open'];
    if (open is! bool) {
      return agentError(400, 'bad_request', 'open bool required');
    }
    _app.setSidebar(open);
    return _ok();
  }

  Future<AgentHttpResult> _connectWindow(Map<String, Object?>? body) async {
    final open = body?['open'];
    if (open is! bool) {
      return agentError(400, 'bad_request', 'open bool required');
    }
    final source = parseConnectSource(body?['source'] as String?);
    if (body?['source'] != null && source == null) {
      return agentError(400, 'bad_request', 'unknown source');
    }
    _app.setConnectWindow(open: open, source: source);
    return _ok();
  }

  Future<AgentHttpResult> _connect(Map<String, Object?>? body) async {
    final id = body?['id'] as String?;
    if (id == null || id.isEmpty) {
      return agentError(400, 'bad_request', 'id required');
    }
    final app = _container.read(appStateProvider);
    if (app.connectingTo != null) {
      return agentError(409, 'busy', app.connectingTo);
    }
    final info = resolveAgentDevice(id, app.devices);
    if (info == null) {
      return agentError(404, 'unknown_device', id);
    }
    await _app.connectTo(info, persist: false);
    final after = _container.read(appStateProvider);
    if (!after.status.connected) {
      return agentError(409, 'connect_failed', after.scanMessage);
    }
    return _ok();
  }

  Future<AgentHttpResult> _disconnect() async {
    await _app.disconnectDevice(persist: false);
    return _ok();
  }

  Future<AgentHttpResult> _select(Map<String, Object?>? body) async {
    final id = body?['protocol'] as String?;
    if (id == null || id.isEmpty) {
      return agentError(400, 'bad_request', 'protocol required');
    }
    final catalog = await _container.read(protocolCatalogProvider.future);
    if (catalog.forName(id) == null) {
      return agentError(412, 'unknown_protocol', id);
    }
    _feedback.selectProtocol(id);
    return _ok();
  }

  Future<AgentHttpResult> _duration(Map<String, Object?>? body) async {
    final raw = body?['minutes'];
    final minutes = raw is int ? raw : (raw is num ? raw.toInt() : null);
    if (minutes == null || minutes <= 0) {
      return agentError(400, 'bad_request', 'minutes int required');
    }
    _feedback.selectDuration(minutes, persist: false);
    return _ok();
  }

  Future<AgentHttpResult> _start(Map<String, Object?>? body) async {
    final app = _container.read(appStateProvider);
    if (!app.status.connected) {
      return agentError(412, 'not_connected');
    }
    if (app.lastConnectedKind != null &&
        deviceKindIsCrown(app.lastConnectedKind!)) {
      return agentError(409, 'crown_refused', crownSessionUnsupportedMessage);
    }
    if (_container.read(monitorControllerProvider).kind ==
        CaptureKind.recording) {
      return agentError(
        409,
        'recording_active',
        'Stop the recording before starting a session.',
      );
    }
    final skip = body?['skipCalibration'] == true;
    await _feedback.startCalibration(skipCalibration: skip);
    return _ok();
  }

  Future<AgentHttpResult> _recordStart() async {
    final app = _container.read(appStateProvider);
    if (!app.status.connected) {
      return agentError(412, 'disconnected');
    }
    final mon = _container.read(monitorControllerProvider);
    if (mon.kind == CaptureKind.feedback) {
      return agentError(409, 'feedback_active');
    }
    await _container.read(monitorControllerProvider.notifier).startRecording();
    return _ok();
  }

  Future<AgentHttpResult> _recordStop() async {
    await _container
        .read(monitorControllerProvider.notifier)
        .stopRecording(promptSave: false, restartTmp: true);
    return _ok();
  }

  Future<AgentHttpResult> _pause() async {
    final fb = _container.read(feedbackStateProvider);
    if (fb.phase != FeedbackPhase.playing) {
      return agentError(409, 'bad_phase', fb.phase.name);
    }
    await _feedback.pause();
    return _ok();
  }

  Future<AgentHttpResult> _resume() async {
    final fb = _container.read(feedbackStateProvider);
    if (fb.phase != FeedbackPhase.paused) {
      return agentError(409, 'bad_phase', fb.phase.name);
    }
    await _feedback.resume();
    return _ok();
  }

  Future<AgentHttpResult> _end() async {
    final app = _container.read(appStateProvider);
    final fb = _container.read(feedbackStateProvider);
    if (!app.status.connected ||
        fb.phase == FeedbackPhase.idle ||
        fb.phase == FeedbackPhase.ended) {
      return _ok();
    }
    await _feedback.end();
    return _ok();
  }

  Future<AgentHttpResult> _reset() async {
    _feedback.reset();
    return _ok();
  }

  AgentHttpResult _override(Map<String, Object?>? body) {
    if (!_feedback.featureProbeAvailable) {
      return agentError(412, 'probe_unavailable');
    }
    final enabled = body?['enabled'];
    if (enabled is! bool) {
      return agentError(400, 'bad_request', 'enabled bool required');
    }
    _feedback.setFeatureOverrideEnabled(enabled);
    return _ok();
  }

  AgentHttpResult _feature(Map<String, Object?>? body) {
    if (!_feedback.featureProbeAvailable) {
      return agentError(412, 'probe_unavailable');
    }
    final id = body?['id'] as String?;
    if (id == null || id.isEmpty) {
      return agentError(400, 'bad_request', 'id required');
    }
    final raw = body?['value'];
    if (raw == null) {
      _feedback.setFeatureOverride(id, null);
      return _ok();
    }
    final value = raw is num ? raw.toDouble() : null;
    if (value == null) {
      return agentError(400, 'bad_request', 'value number required');
    }
    _feedback.setFeatureOverride(id, value);
    return _ok();
  }
}
