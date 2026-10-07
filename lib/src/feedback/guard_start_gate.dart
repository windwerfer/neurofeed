/// What Start does about the guard's AI engine.
library;

import 'package:neurofeed/src/feedback/guardrail_mode.dart';
import 'package:neurofeed/src/reve/model_engine.dart';
import 'package:neurofeed/src/settings.dart';

enum GuardStartGate {
  /// Start right away: no guard, a band-math guard, or the AI engine is
  /// Ready.
  start,

  /// The guard will run an AI head but the engine is not Ready (not
  /// installed, still loading, or failed). Start shows the model gate
  /// (install / import, or wait for the load) and starts once it is Ready.
  needsModel,
}

/// Start gate for [protocolId] given the AI [engine] state.
///
/// A catalog-default AI head without a stored pref falls back to band.delta
/// while the engine is not Ready, so it starts at once. An explicit AI pick,
/// or a protocol whose guard sets `requiresModel` (sleepGuard), never falls
/// back: those return [GuardStartGate.needsModel] until the engine is Ready,
/// whether the model is missing or still loading.
GuardStartGate guardStartGate({
  required Settings settings,
  required String protocolId,
  required ModelEngineState engine,
}) {
  if (!settings.guardrailEnabledFor(protocolId)) return GuardStartGate.start;
  final ready = engine is ModelEngineReady;
  final feature = settings.sessionGuardFeatureFor(protocolId, aiReady: ready);
  if (guardFeatureIsAi(feature) && !ready) return GuardStartGate.needsModel;
  return GuardStartGate.start;
}

/// Whether a session for [protocolId] must not start right now: its guard
/// requires the AI model (`guard.requiresModel`) and the engine is not Ready.
/// [FeedbackState.startCalibration] refuses in this case so a model-only
/// guard can never quietly run without its model (or on band.delta).
bool guardStartBlocked({
  required Settings settings,
  required String protocolId,
  required ModelEngineState engine,
}) =>
    settings.guardRequiresModelFor(protocolId) &&
    guardStartGate(
          settings: settings,
          protocolId: protocolId,
          engine: engine,
        ) ==
        GuardStartGate.needsModel;
