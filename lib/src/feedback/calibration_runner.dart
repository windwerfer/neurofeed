import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/audio/calibration_clips.dart';
import 'package:muse_ml/src/feedback/feedback_phase.dart';
import 'package:muse_ml/src/feedback/session_store.dart';

/// One step of a calibration recipe: an optional guidance clip followed by a
/// silent collection window. `seconds == 0` means no collection (intro-only).
class CalibrationStepRun {
  const CalibrationStepRun({
    required this.name,
    this.clip,
    this.seconds = 0,
    this.eyes,
    this.challengeText,
  });

  final String name;
  final CalibrationStep? clip;
  final int seconds;
  final String? eyes;
  final String? challengeText;
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
  });

  final bool? waitingForSignal;
  final bool? startAnywayAvailable;
  final int? baselineSecondsLeft;
  final String? stepName;
  final int? stepTotal;
  final String? challengeHint;
  final String? challengeText;
  final bool clearChallenges;
}

/// Playback of today's `single` / `staged` clips. Compose-from-subscribed
/// features is PR 6 — [useStaged] stays "any `ai.*` enabled".
class CalibrationRunner {
  CalibrationRunner({
    required this.loadManifest,
    required this.playClip,
    required this.writeMetadata,
    required this.updateUi,
    required this.phaseOf,
    required this.protocolOf,
    required this.sessionStartAt,
    required this.onCollectionEyes,
    required this.onFinished,
  });

  final Future<CalibrationManifest> Function() loadManifest;
  final Future<void> Function(String file) playClip;
  final void Function(Map<String, dynamic> meta) writeMetadata;
  final void Function(CalibrationUi ui) updateUi;
  final FeedbackPhase Function() phaseOf;
  final String Function() protocolOf;
  final DateTime? Function() sessionStartAt;
  final void Function(String? eyes) onCollectionEyes;
  final void Function() onFinished;

  final List<CalibrationStepRun> steps = [];
  int stepIndex = 0;
  String kind = 'single';
  String calibrationId = '';
  Map<String, Object?>? calibrationJson;
  final List<SessionCalibrationPhase> clipPhases = [];
  Completer<void>? collectionCompleter;
  Timer? collectionTimer;

  void reset() {
    collectionTimer?.cancel();
    collectionTimer = null;
    collectionCompleter?.complete();
    collectionCompleter = null;
    steps.clear();
    stepIndex = 0;
    kind = 'single';
    calibrationId = '';
    calibrationJson = null;
    clipPhases.clear();
    onCollectionEyes(null);
  }

  void cancelTimers() {
    collectionTimer?.cancel();
    collectionTimer = null;
    collectionCompleter?.complete();
    collectionCompleter = null;
  }

  /// Runs the calibration for the selected protocol from the manifest recipe:
  /// * `single` — a random intro clip, then one silent baseline window.
  /// * `staged` — the fixed ordered stages; each plays a guidance clip then
  ///   collects silently for that stage's seconds.
  Future<void> playAndBaseline({required bool useStaged}) async {
    updateUi(
      const CalibrationUi(waitingForSignal: false, clearChallenges: true),
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
      recipe = manifest.recipeFor(protocolOf(), useStaged: useStaged);
      calibrationId = manifest.calibrationIdFor(protocolOf()) ?? '';
      calibrationJson = manifest.calibrationJsonFor(protocolOf());
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
            seconds: recipe?.seconds ?? calibrationBaselineSeconds,
            eyes: recipe?.eyes,
          ),
        );
    } else {
      kind = 'staged';
      for (final stage in recipe.stages) {
        steps.add(
          CalibrationStepRun(
            name: _stageName(stage),
            clip: stage,
            seconds: stage.seconds,
            eyes: stage.eyes,
            challengeText: stage.randomChallenge(),
          ),
        );
      }
    }
    writeMetadata({
      'type': 'calibration_start',
      'kind': kind,
      'calibrationId': calibrationId,
      'timestamp': DateTime.now().toIso8601String(),
    });
    await _runNextStep();
  }

  String _stageName(CalibrationStep step) => switch (step.eyes) {
    'open' => 'Eyes open',
    'closed' => 'Eyes closed',
    _ => 'Artifacts',
  };

  Future<void> _runNextStep() async {
    if (phaseOf() != FeedbackPhase.calibrating) {
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
      ),
    );
    if (step.clip != null) {
      final sessionStart = sessionStartAt();
      final clipStart = DateTime.now();
      await playClip(
        step.clip!.file,
      ).timeout(calibrationAudioTimeout, onTimeout: () {});
      if (phaseOf() != FeedbackPhase.calibrating) {
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
          'eyes': step.clip!.eyes,
          'startSecs': clipStart.difference(sessionStart).inMilliseconds / 1000,
          'endSecs': clipEnd.difference(sessionStart).inMilliseconds / 1000,
          'kind': kind == 'staged' ? 'stage' : 'intro',
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }
    if (step.seconds > 0) {
      await _runCollection(step);
    }
    stepIndex++;
    await _runNextStep();
  }

  Future<void> _runCollection(CalibrationStepRun step) async {
    onCollectionEyes(step.eyes);
    updateUi(
      CalibrationUi(
        baselineSecondsLeft: step.seconds,
        waitingForSignal: false,
        startAnywayAvailable: false,
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
  }

  int _collectionLeft = 0;
}
