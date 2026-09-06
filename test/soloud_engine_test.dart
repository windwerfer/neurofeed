import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/audio/soloud_engine.dart';

AudioSource _fakeSource(int hash) {
  // ignore: invalid_use_of_internal_member
  return AudioSource(SoundHash(hash));
}

void main() {
  setUp(SoLoudEngine.resetForTest);
  tearDown(SoLoudEngine.resetForTest);

  test('opens with the requested conservative profile', () async {
    final calls = <bool>[];
    SoLoudEngine.resetForTest(
      init: ({required bool lowLatency}) async {
        calls.add(lowLatency);
      },
      deinit: () async {},
    );

    await SoLoudEngine.ensureInit(stable: true);

    expect(calls, [false]);
    expect(SoLoudEngine.isReady, isTrue);
    expect(SoLoudEngine.stable, isTrue);
    expect(SoLoudEngine.epoch, 1);
  });

  test('falls back to low-latency when conservative init fails', () async {
    final calls = <bool>[];
    SoLoudEngine.resetForTest(
      init: ({required bool lowLatency}) async {
        calls.add(lowLatency);
        if (!lowLatency) {
          throw StateError('backend not inited');
        }
      },
      deinit: () async {},
    );

    await SoLoudEngine.ensureInit(stable: true);

    expect(calls, [false, true]);
    expect(SoLoudEngine.isReady, isTrue);
    expect(SoLoudEngine.stable, isFalse);
  });

  test('does not retry a conservative profile that already failed', () async {
    var inits = 0;
    SoLoudEngine.resetForTest(
      init: ({required bool lowLatency}) async {
        inits++;
        if (!lowLatency) {
          throw StateError('backend not inited');
        }
      },
      deinit: () async {},
    );

    await SoLoudEngine.ensureInit(stable: true);
    await SoLoudEngine.ensureInit(stable: true);

    expect(inits, 2);
    expect(SoLoudEngine.stable, isFalse);
  });

  test('retries after a failed open instead of caching the error', () async {
    var inits = 0;
    SoLoudEngine.resetForTest(
      init: ({required bool lowLatency}) async {
        inits++;
        if (inits <= 2) {
          throw StateError('backend not inited');
        }
      },
      deinit: () async {},
    );

    await expectLater(SoLoudEngine.ensureInit(stable: true), throwsStateError);
    expect(SoLoudEngine.isReady, isFalse);

    await SoLoudEngine.ensureInit(stable: false);
    expect(SoLoudEngine.isReady, isTrue);
    expect(inits, 3);
  });

  test('concurrent callers share one native init', () async {
    var inits = 0;
    final started = Completer<void>();
    final release = Completer<void>();
    SoLoudEngine.resetForTest(
      init: ({required bool lowLatency}) async {
        inits++;
        if (!started.isCompleted) {
          started.complete();
        }
        await release.future;
      },
      deinit: () async {},
    );

    final a = SoLoudEngine.ensureInit(stable: true);
    final b = SoLoudEngine.ensureInit(stable: true);
    await started.future;
    release.complete();
    await Future.wait([a, b]);

    expect(inits, 1);
    expect(SoLoudEngine.isReady, isTrue);
  });

  test(
    'reopenIfProfileDiffers false keeps the open opposite profile',
    () async {
      final events = <String>[];
      SoLoudEngine.resetForTest(
        init: ({required bool lowLatency}) async {
          events.add('init lowLatency=$lowLatency');
        },
        deinit: () async {
          events.add('deinit');
        },
      );

      await SoLoudEngine.ensureInit(stable: true);
      await SoLoudEngine.ensureInit(stable: false);

      expect(events, ['init lowLatency=false']);
      expect(SoLoudEngine.stable, isTrue);
      expect(SoLoudEngine.epoch, 1);
    },
  );

  test('reopenIfProfileDiffers true tears down then reopens', () async {
    final events = <String>[];
    SoLoudEngine.resetForTest(
      init: ({required bool lowLatency}) async {
        events.add('init lowLatency=$lowLatency');
      },
      deinit: () async {
        events.add('deinit');
      },
    );

    await SoLoudEngine.ensureInit(stable: true);
    await SoLoudEngine.ensureInit(stable: false, reopenIfProfileDiffers: true);

    expect(events, ['init lowLatency=false', 'deinit', 'init lowLatency=true']);
    expect(SoLoudEngine.stable, isFalse);
    expect(SoLoudEngine.epoch, greaterThan(1));
  });

  test('deinit invalidates readiness and epoch', () async {
    SoLoudEngine.resetForTest(
      init: ({required bool lowLatency}) async {},
      deinit: () async {},
    );

    await SoLoudEngine.ensureInit();
    final epoch = SoLoudEngine.epoch;
    await SoLoudEngine.deinit();

    expect(SoLoudEngine.isReady, isFalse);
    expect(SoLoudEngine.epoch, greaterThan(epoch));
  });

  test(
    'deinit waits for in-flight ensureInit then engine is not ready',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var nativeDeinits = 0;
      SoLoudEngine.resetForTest(
        init: ({required bool lowLatency}) async {
          started.complete();
          await release.future;
        },
        deinit: () async {
          nativeDeinits++;
        },
      );

      final opened = SoLoudEngine.ensureInit(stable: true);
      await started.future;
      final closed = SoLoudEngine.deinit();
      release.complete();
      await opened;
      await closed;

      expect(SoLoudEngine.isReady, isFalse);
      expect(nativeDeinits, 1);
    },
  );

  test('loadAsset shares one in-flight load', () async {
    var loads = 0;
    final started = Completer<void>();
    final release = Completer<void>();
    SoLoudEngine.resetForTest(
      init: ({required bool lowLatency}) async {},
      deinit: () async {},
      loadAsset: (path, {required bool stream}) async {
        loads++;
        started.complete();
        await release.future;
        return _fakeSource(1);
      },
      disposeSource: (_) async {},
    );

    await SoLoudEngine.ensureInit();
    final a = SoLoudEngine.loadAsset('assets/a.opus', stream: true);
    final b = SoLoudEngine.loadAsset('assets/a.opus', stream: true);
    await started.future;
    release.complete();
    final sources = await Future.wait([a, b]);

    expect(loads, 1);
    expect(identical(sources[0], sources[1]), isTrue);
  });

  test('second epoch disposes cached assets', () async {
    var loads = 0;
    var disposes = 0;
    var hash = 1;
    SoLoudEngine.resetForTest(
      init: ({required bool lowLatency}) async {},
      deinit: () async {},
      loadAsset: (path, {required bool stream}) async {
        loads++;
        return _fakeSource(hash++);
      },
      disposeSource: (_) async {
        disposes++;
      },
    );

    await SoLoudEngine.ensureInit();
    await SoLoudEngine.loadAsset('assets/a.opus', stream: true);
    expect(loads, 1);
    expect(disposes, 0);

    await SoLoudEngine.deinit();
    expect(disposes, 1);

    await SoLoudEngine.ensureInit();
    await SoLoudEngine.loadAsset('assets/a.opus', stream: true);
    expect(loads, 2);
  });
}
