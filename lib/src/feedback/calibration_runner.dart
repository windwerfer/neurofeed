import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neurofeed/src/audio/calibration_clips.dart';
import 'package:neurofeed/src/feedback/baseline_window.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/feedback/session_store.dart';

/// One step of a calibration recipe: an optional guidance clip followed by a
/// silent collection window. `seconds == 0` means no collection (intro-only).
class CalibrationStepRun {
  const CalibrationStepRun({
    required this.name,
    this.clip,
    this.seconds = 0,
    this.eyes,
    this.challengeText,
    this.baselineWindow = false,
  });

  final String name;
  final CalibrationStep? clip;
  final int seconds;
  final String? eyes;
  final String? challengeText;
  final bool baselineWindow;
}

class CalibrationUi {
  const CalibrationUi({
    this.waitingForSignal,
    this.startAnywayAvailable,
    this.baselineSecondsLeft,
    this.stepName,
    this.stepTotal,
    this.challengeHint,
    this.challengeText,
    this.clearChallenges = false,
    this.cleanCountdown,
  });

  final bool? waitingForSignal;
  final bool? startAnywayAvailable;
  final int? baselineSecondsLeft;
  final String? stepName;
  final int? stepTotal;
  final String? challengeHint;
  final String? challengeText;
  final bool clearChallenges;
  final bool? cleanCountdown;
}

/// Playback of today's `single` / `staged` clips, composed from a
/// [CalibrationPlan] derived from the session's enabled feature set.
class CalibrationRunner {
  CalibrationRunner({
    required this.loadManifest,
    required this.playClip,
    required this.writeMetadata,
    required this.updateUi,
    required this.isActive,
    required this.protocolOf,
    required this.sessionStartAt,
    required this.onCollectionEyes,
    required this.onFinished,
    this.usedStartAnyway = _startAnywayDefault,
    this.baselineFrameValid = _baselineFrameInvalid,
    this.clock = _systemClock,
  });

  final Future<CalibrationManifest> Function() loadManifest;
  final Future<void> Function(String file) playClip;
  final void Function(Map<String, dynamic> meta) writeMetadata;
  final void Function(CalibrationUi ui) updateUi;
  final bool Function() isActive;
  final String Function() protocolOf;
  final DateTime? Function() sessionStartAt;
  final void Function(String? eyes) onCollectionEyes;
  final void Function() onFinished;
  final bool Function() usedStartAnyway;

  final bool Function() baselineFrameValid;
  final DateTime Function() clock;

  static bool _startAnywayDefault() => false;
  static bool _baselineFrameInvalid() => false;
  static DateTime _systemClock() => DateTime.now();

  final List<CalibrationStepRun> steps = [];
  int stepIndex = 0;
  String kind = 'single';
  String calibrationId = '';
  Map<String, Object?>? calibrationJson;
  final List<SessionCalibrationPhase> clipPhases = [];
  Completer<void>? collectionCompleter;
  Timer? collectionTimer;
  bool collectingBaselineWindow = false;
  int? baselineValidSeconds;
  int? baselineWallSeconds;
  BaselineWindow _window = const BaselineWindow();
  final BaselineFrameClock _frameClock = BaselineFrameClock();
  bool _finishAfterSample = false;

  void reset() {
    cancelTimers();
    steps.clear();
    stepIndex = 0;
    kind = 'single';
    calibrationId = '';
    calibrationJson = null;
    clipPhases.clear();
    baselineValidSeconds = null;
    baselineWallSeconds = null;
    _window = const BaselineWindow();
    _frameClock.reset();
    _finishAfterSample = false;
    onCollectionEyes(null);
  }

  void cancelTimers() {
    collectionTimer?.cancel();
    collectionTimer = null;
    collectingBaselineWindow = false;
    _finishAfterSample = false;
    _frameClock.reset();
    final pending = collectionCompleter;
    collectionCompleter = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  /// Runs the calibration for the selected protocol from the manifest recipe
  /// composed by [plan]:
  /// * baseline-only — a random intro clip, then one silent baseline window.
  /// * staged — the requested artifact / challenge / rest clips; each plays
  ///   a guidance clip then collects silently for that stage's seconds.
  Future<void> playAndBaseline({required CalibrationPlan plan}) async {
    if (!isActive()) {
      return;
    }
    updateUi(
      const CalibrationUi(
        waitingForSignal: false,
        clearChallenges: true,
        cleanCountdown: false,
      ),
    );
    steps.clear();
    stepIndex = 0;
    clipPhases.clear();
    onCollectionEyes(null);
    kind = 'single';
    calibrationId = '';
    calibrationJson = null;
    CalibrationRecipe? recipe;
    try {
      final manifest = await loadManifest();
      calibrationId = manifest.calibrationIdFor(protocolOf()) ?? '';
      calibrationJson = manifest.calibrationJsonFor(protocolOf());
      if (calibrationId.isNotEmpty) {
        recipe = manifest.recipeFor(calibrationId, plan: plan);
      }
    } catch (e) {
      debugPrint('[feedback] calibration manifest unavailable: $e');
    }
    if (recipe == null || recipe.isSingle) {
      kind = 'single';
      steps
        ..add(CalibrationStepRun(name: 'Intro', clip: recipe?.randomIntro()))
        ..add(
          CalibrationStepRun(
            name: 'Baseline',
            seconds: calibrationBaselineValidSeconds,
            eyes: recipe?.eyes,
            baselineWindow: true,
          ),
        );
    } else {
      kind = 'staged';
      for (final stage in recipe.stages) {
        steps.add(
          CalibrationStepRun(
            name: _stageName(stage),
            clip: stage,
            seconds: stage.isRestStage
                ? calibrationBaselineValidSeconds
                : stage.seconds,
            eyes: stage.eyes,
            challengeText: stage.randomChallenge(),
            baselineWindow: stage.isRestStage,
          ),
        );
      }
    }
    writeMetadata({
      'type': 'calibration_start',
      'kind': kind,
      'calibrationId': calibrationId,
      'timestamp': DateTime.now().toIso8601String(),
      if (calibrationJson != null) 'calibrationJson': calibrationJson,
      if (usedStartAnyway()) 'usedStartAnyway': true,
    });
    await _runNextStep();
  }

  String _stageName(CalibrationStep step) => switch (step.eyes) {
    'open' => 'Eyes open',
    'closed' => 'Eyes closed',
    _ => 'Artifacts',
  };

  Future<void> _runNextStep() async {
    if (!isActive()) {
      return;
    }
    if (stepIndex >= steps.length) {
      onFinished();
      return;
    }
    final step = steps[stepIndex];
    updateUi(
      CalibrationUi(
        stepName: step.name,
        stepTotal: step.seconds,
        challengeHint: step.clip?.challengeTextHint,
        challengeText: step.challengeText,
        baselineSecondsLeft: 0,
        cleanCountdown: false,
      ),
    );
    if (step.clip != null) {
      final sessionStart = sessionStartAt();
      final clipStart = DateTime.now();
      try {
        await playClip(
          step.clip!.file,
        ).timeout(calibrationAudioTimeout, onTimeout: () {});
      } catch (e) {
        debugPrint('[feedback] calibration clip failed: $e');
      }
      if (!isActive()) {
        return;
      }
      final clipEnd = DateTime.now();
      if (sessionStart != null) {
        clipPhases.add(
          SessionCalibrationPhase(
            name: step.clip!.id,
            durationSecs: clipEnd.difference(clipStart).inMilliseconds / 1000,
            sampleCount: 0,
            clipFile: step.clip!.file,
            spokenText: step.clip!.text,
            eyes: step.clip!.eyes,
            challengeText: step.challengeText,
            startSecs: clipStart.difference(sessionStart).inMilliseconds / 1000,
            endSecs: clipEnd.difference(sessionStart).inMilliseconds / 1000,
            kind: kind == 'staged' ? 'stage' : 'intro',
          ),
        );
        writeMetadata({
          'type': 'calibration_phase',
          'clipId': step.clip!.id,
          'clipFile': step.clip!.file,
          'spokenText': step.clip!.text,
          'eyes': step.clip!.eyes,
          if (step.challengeText != null) 'challengeText': step.challengeText,
          'startSecs': clipStart.difference(sessionStart).inMilliseconds / 1000,
          'endSecs': clipEnd.difference(sessionStart).inMilliseconds / 1000,
          'kind': kind == 'staged' ? 'stage' : 'intro',
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }
    if (step.baselineWindow || step.seconds > 0) {
      await _runCollection(step);
    }
    if (!isActive()) {
      return;
    }
    stepIndex++;
    await _runNextStep();
  }

  Future<void> _runCollection(CalibrationStepRun step) async {
    if (step.baselineWindow) {
      await _runBaselineWindow(step);
      return;
    }
    onCollectionEyes(step.eyes);
    updateUi(
      CalibrationUi(
        baselineSecondsLeft: step.seconds,
        waitingForSignal: false,
        startAnywayAvailable: false,
        cleanCountdown: false,
      ),
    );
    final completer = Completer<void>();
    collectionCompleter = completer;
    collectionTimer?.cancel();
    _collectionLeft = step.seconds;
    collectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _collectionLeft--;
      if (_collectionLeft <= 0) {
        collectionTimer?.cancel();
        collectionTimer = null;
        if (!completer.isCompleted) {
          completer.complete();
        }
      } else {
        updateUi(CalibrationUi(baselineSecondsLeft: _collectionLeft));
      }
    });
    await completer.future;
    collectionCompleter = null;
    onCollectionEyes(null);
    if (!isActive()) {
      return;
    }
  }

  Future<void> _runBaselineWindow(CalibrationStepRun step) async {
    onCollectionEyes(step.eyes);
    final started = clock();
    _window = const BaselineWindow().start(started);
    _frameClock.reset();
    _finishAfterSample = false;
    collectingBaselineWindow = true;
    baselineValidSeconds = null;
    baselineWallSeconds = null;
    updateUi(
      CalibrationUi(
        baselineSecondsLeft: _window.secondsLeft,
        stepTotal: _window.targetValidSeconds,
        waitingForSignal: false,
        startAnywayAvailable: false,
        cleanCountdown: true,
      ),
    );
    final completer = Completer<void>();
    collectionCompleter = completer;
    collectionTimer?.cancel();
    collectionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!collectingBaselineWindow) return;
      final now = clock();
      if (_window.finishedAt(now)) {
        _completeBaseline(now);
      }
    });
    await completer.future;
    onCollectionEyes(null);
    if (!isActive()) {
      return;
    }
  }

  bool noteBaselineFrame({required String featureId, int? sourceSecond}) {
    if (!collectingBaselineWindow) return false;
    final now = clock();
    final bucket = _sourceBucket(now, sourceSecond);
    if (bucket == null) return false;
    if (_window.finishedAt(now) && !_frameClock.contains(bucket)) {
      _finishAfterSample = true;
      return false;
    }
    final taken = _frameClock.take(
      sourceSecond: bucket,
      featureId: featureId,
      accept: baselineFrameValid(),
    );
    if (taken.opened && taken.accepted) {
      _window = _window.recordAccepted();
      updateUi(
        CalibrationUi(
          baselineSecondsLeft: _window.secondsLeft,
          cleanCountdown: true,
        ),
      );
    }
    if (_window.finishedAt(now)) {
      _finishAfterSample = true;
    }
    return taken.store;
  }

  int? _sourceBucket(DateTime now, int? sourceSecond) {
    final start = _window.started;
    if (start == null) return null;
    final startSecond = start.millisecondsSinceEpoch ~/ 1000;
    final limit = startSecond + _window.maxWallSeconds;
    if (sourceSecond != null) {
      if (sourceSecond < startSecond || sourceSecond > limit) return null;
      return sourceSecond;
    }
    final second = now.millisecondsSinceEpoch ~/ 1000;
    if (second < startSecond || second > limit) return null;
    return second;
  }

  void finishBaselineFrame() {
    if (!_finishAfterSample || !collectingBaselineWindow) return;
    _finishAfterSample = false;
    _completeBaseline(clock());
  }

  void _completeBaseline(DateTime now) {
    if (!collectingBaselineWindow) return;
    baselineValidSeconds = _window.validSeconds;
    baselineWallSeconds = _window.wallSecondsAt(now);
    collectingBaselineWindow = false;
    _finishAfterSample = false;
    collectionTimer?.cancel();
    collectionTimer = null;
    onCollectionEyes(null);
    final pending = collectionCompleter;
    collectionCompleter = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }

  int _collectionLeft = 0;
}
