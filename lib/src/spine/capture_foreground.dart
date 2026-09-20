import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/feedback/feedback_state.dart';
import 'package:neurofeed/src/monitor/monitor_providers.dart';
import 'package:neurofeed/src/monitor/monitor_state.dart';
import 'package:permission_handler/permission_handler.dart';

const kCaptureForegroundChannel = 'neurofeed/capture_fgs';

enum CaptureForegroundKind { recording, session }

class CaptureForegroundSpec {
  const CaptureForegroundSpec({
    required this.kind,
    required this.startedAtMs,
    required this.elapsedSeconds,
    required this.unsaved,
  });

  final CaptureForegroundKind kind;
  final int startedAtMs;
  final int elapsedSeconds;
  final bool unsaved;

  String get kindName =>
      kind == CaptureForegroundKind.session ? 'session' : 'recording';
}

/// Persistent FGS while keepable capture is live or waiting Save/Discard.
/// Not for [CaptureKind.tmp]. Linux / Windows are no-ops.
CaptureForegroundSpec? keepableCaptureForeground({
  required CaptureKind captureKind,
  String? pendingScratchPath,
  required bool unsavedSession,
  int? captureStartedAtMs,
  int sessionElapsedSeconds = 0,
  bool recordingCrashHold = false,
  int Function()? nowMs,
}) {
  final now = nowMs?.call() ?? DateTime.now().millisecondsSinceEpoch;
  int elapsedFrom(int start) {
    final ms = now - start;
    if (ms <= 0) return 0;
    return ms ~/ 1000;
  }

  if (captureKind == CaptureKind.recording) {
    final start = captureStartedAtMs ?? now;
    return CaptureForegroundSpec(
      kind: CaptureForegroundKind.recording,
      startedAtMs: start,
      elapsedSeconds: elapsedFrom(start),
      unsaved: false,
    );
  }
  if (captureKind == CaptureKind.feedback) {
    final elapsed = sessionElapsedSeconds < 0 ? 0 : sessionElapsedSeconds;
    return CaptureForegroundSpec(
      kind: CaptureForegroundKind.session,
      startedAtMs: now - elapsed * 1000,
      elapsedSeconds: elapsed,
      unsaved: false,
    );
  }
  if (pendingScratchPath != null) {
    final start = captureStartedAtMs ?? now;
    return CaptureForegroundSpec(
      kind: CaptureForegroundKind.recording,
      startedAtMs: start,
      elapsedSeconds: captureStartedAtMs == null ? 0 : elapsedFrom(start),
      unsaved: true,
    );
  }
  if (unsavedSession) {
    final elapsed = sessionElapsedSeconds < 0 ? 0 : sessionElapsedSeconds;
    return CaptureForegroundSpec(
      kind: CaptureForegroundKind.session,
      startedAtMs: now - elapsed * 1000,
      elapsedSeconds: elapsed,
      unsaved: true,
    );
  }
  if (recordingCrashHold) {
    return CaptureForegroundSpec(
      kind: CaptureForegroundKind.recording,
      startedAtMs: now,
      elapsedSeconds: 0,
      unsaved: true,
    );
  }
  return null;
}

class CaptureForeground {
  static const MethodChannel _channel = MethodChannel(
    kCaptureForegroundChannel,
  );

  static CaptureForegroundSpec? _active;
  static bool recordingCrashHold = false;
  static bool _askedNotify = false;
  static ProviderSubscription<MonitorState>? _monitorSub;
  static ProviderSubscription<FeedbackState>? _feedbackSub;

  @visibleForTesting
  static Future<void> Function(String method, [Map<String, Object?>? args])?
  debugInvoke;

  @visibleForTesting
  static bool debugForceAndroid = false;

  static bool get _android =>
      debugForceAndroid || (!kIsWeb && Platform.isAndroid);

  static void bind(ProviderContainer container) {
    _monitorSub?.close();
    _feedbackSub?.close();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopRequested') {
        _onStopRequested(container);
      }
    });
    void push() => unawaited(syncFrom(container));
    _monitorSub = container.listen<MonitorState>(
      monitorControllerProvider,
      (_, _) => push(),
    );
    _feedbackSub = container.listen<FeedbackState>(
      feedbackStateProvider,
      (_, _) => push(),
    );
  }

  static void _onStopRequested(ProviderContainer container) {
    final mon = container.read(monitorControllerProvider);
    if (mon.kind == CaptureKind.recording) {
      unawaited(
        container.read(monitorControllerProvider.notifier).stopRecording(),
      );
      return;
    }
    if (mon.kind == CaptureKind.feedback) {
      final phase = container.read(feedbackStateProvider).phase;
      if (phase != FeedbackPhase.ended) {
        unawaited(container.read(feedbackStateProvider.notifier).end());
      }
    }
  }

  static Future<void> syncFrom(ProviderContainer container) {
    final mon = container.read(monitorControllerProvider);
    final fb = container.read(feedbackStateProvider);
    final unsaved = container
        .read(feedbackStateProvider.notifier)
        .hasUnsavedSession;
    return sync(
      captureKind: mon.kind,
      pendingScratchPath: mon.pendingScratchPath,
      unsavedSession: unsaved,
      captureStartedAtMs: mon.captureStartedAtMs,
      sessionElapsedSeconds: fb.elapsedSeconds,
    );
  }

  static Future<void> syncFromRef(WidgetRef ref) {
    final mon = ref.read(monitorControllerProvider);
    final fb = ref.read(feedbackStateProvider);
    final unsaved = ref.read(feedbackStateProvider.notifier).hasUnsavedSession;
    return sync(
      captureKind: mon.kind,
      pendingScratchPath: mon.pendingScratchPath,
      unsavedSession: unsaved,
      captureStartedAtMs: mon.captureStartedAtMs,
      sessionElapsedSeconds: fb.elapsedSeconds,
    );
  }

  static Future<void> setRecordingCrashHold(bool held) async {
    recordingCrashHold = held;
  }

  static Future<void> sync({
    required CaptureKind captureKind,
    String? pendingScratchPath,
    required bool unsavedSession,
    int? captureStartedAtMs,
    int sessionElapsedSeconds = 0,
  }) {
    return apply(
      keepableCaptureForeground(
        captureKind: captureKind,
        pendingScratchPath: pendingScratchPath,
        unsavedSession: unsavedSession,
        captureStartedAtMs: captureStartedAtMs,
        sessionElapsedSeconds: sessionElapsedSeconds,
        recordingCrashHold: recordingCrashHold,
      ),
    );
  }

  static Future<void> apply(CaptureForegroundSpec? next) async {
    if (next == null) {
      if (_active == null) return;
      _active = null;
      debugPrint('[spine] fgs stop');
      await _invoke('stop');
      return;
    }
    if (_active != null &&
        _active!.kind == next.kind &&
        _active!.unsaved == next.unsaved) {
      return;
    }
    _active = next;
    debugPrint(
      '[spine] fgs start kind=${next.kindName} unsaved=${next.unsaved}',
    );
    await _ensureNotificationPermission();
    await _invoke('start', {
      'kind': next.kindName,
      'startedAtMs': next.startedAtMs,
      'elapsedSeconds': next.elapsedSeconds,
      'unsaved': next.unsaved,
    });
  }

  static Future<void> _ensureNotificationPermission() async {
    if (_askedNotify || !_android) return;
    _askedNotify = true;
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('[spine] fgs notification permission: $e');
    }
  }

  static Future<void> _invoke(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (!_android) return;
    final override = debugInvoke;
    if (override != null) {
      await override(method, args);
      return;
    }
    try {
      await _channel.invokeMethod(method, args);
    } on MissingPluginException {
      return;
    } catch (e) {
      debugPrint('[spine] fgs $method failed: $e');
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _active = null;
    recordingCrashHold = false;
    _askedNotify = false;
    debugInvoke = null;
    debugForceAndroid = false;
    _monitorSub?.close();
    _feedbackSub?.close();
    _monitorSub = null;
    _feedbackSub = null;
  }
}
