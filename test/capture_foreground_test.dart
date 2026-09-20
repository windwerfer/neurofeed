import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/monitor_state.dart';
import 'package:neurofeed/src/spine/capture_foreground.dart';

void main() {
  const now = 1700000000000;

  CaptureForegroundSpec? spec({
    CaptureKind kind = CaptureKind.idle,
    String? pending,
    bool unsavedSession = false,
    int? startedAtMs,
    int sessionElapsed = 0,
    bool crashHold = false,
  }) {
    return keepableCaptureForeground(
      captureKind: kind,
      pendingScratchPath: pending,
      unsavedSession: unsavedSession,
      captureStartedAtMs: startedAtMs,
      sessionElapsedSeconds: sessionElapsed,
      recordingCrashHold: crashHold,
      nowMs: () => now,
    );
  }

  test('tmp_ and idle do not start FGS', () {
    expect(spec(), isNull);
    expect(spec(kind: CaptureKind.tmp, startedAtMs: now - 5000), isNull);
  });

  test('recording starts live FGS', () {
    final got = spec(kind: CaptureKind.recording, startedAtMs: now - 65000);
    expect(got, isNotNull);
    expect(got!.kind, CaptureForegroundKind.recording);
    expect(got.unsaved, isFalse);
    expect(got.elapsedSeconds, 65);
    expect(got.kindName, 'recording');
  });

  test('feedback starts session FGS', () {
    final got = spec(kind: CaptureKind.feedback, sessionElapsed: 12);
    expect(got, isNotNull);
    expect(got!.kind, CaptureForegroundKind.session);
    expect(got.unsaved, isFalse);
    expect(got.elapsedSeconds, 12);
    expect(got.startedAtMs, now - 12000);
    expect(got.kindName, 'session');
  });

  test('pending recording scratch keeps FGS until Save/Discard', () {
    final got = spec(
      pending: '/tmp/recording_1.neurofeed',
      startedAtMs: now - 4000,
    );
    expect(got, isNotNull);
    expect(got!.kind, CaptureForegroundKind.recording);
    expect(got.unsaved, isTrue);
    expect(got.elapsedSeconds, 4);
  });

  test('unsaved ended session keeps FGS until Save/Discard', () {
    final got = spec(unsavedSession: true, sessionElapsed: 90);
    expect(got, isNotNull);
    expect(got!.kind, CaptureForegroundKind.session);
    expect(got.unsaved, isTrue);
    expect(got.elapsedSeconds, 90);
  });

  test('recording crash-recovery hold keeps FGS', () {
    final got = spec(crashHold: true);
    expect(got, isNotNull);
    expect(got!.kind, CaptureForegroundKind.recording);
    expect(got.unsaved, isTrue);
  });

  test('live recording wins over pending or unsaved session', () {
    final got = spec(
      kind: CaptureKind.recording,
      pending: '/x',
      unsavedSession: true,
      startedAtMs: now,
    );
    expect(got!.unsaved, isFalse);
    expect(got.kind, CaptureForegroundKind.recording);
  });

  test('apply is a no-op off Android', () async {
    CaptureForeground.resetForTest();
    addTearDown(CaptureForeground.resetForTest);
    await CaptureForeground.apply(
      spec(kind: CaptureKind.recording, startedAtMs: now),
    );
    await CaptureForeground.apply(null);
  });
}
