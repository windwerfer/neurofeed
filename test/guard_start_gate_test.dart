import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/guard_start_gate.dart';
import 'package:neurofeed/src/feedback/guardrail_mode.dart';
import 'package:neurofeed/src/reve/model_engine.dart';
import 'package:neurofeed/src/reve/models.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _missing = ModelEngineNotInstalled();
const _loading = ModelEngineLoading();
final _ready = ModelEngineReady(kind: defaultModelKind, description: 'test');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Settings settings;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await Settings.load();
  });

  GuardStartGate gate(String id, ModelEngineState engine) =>
      guardStartGate(settings: settings, protocolId: id, engine: engine);
  bool blocked(String id, ModelEngineState engine) =>
      guardStartBlocked(settings: settings, protocolId: id, engine: engine);

  group('sleepGuard (guard.requiresModel)', () {
    test('flag comes from the protocol document', () {
      expect(settings.guardRequiresModelFor('sleepGuard'), isTrue);
      expect(settings.guardRequiresModelFor('guardrailOnly'), isTrue);
      for (final id in [
        'restAwake',
        'openMonitor',
        'alertOpen',
        'alertClosed',
        'concentrate',
        'calibrateRecord',
        'recordOnly',
      ]) {
        expect(settings.guardRequiresModelFor(id), isFalse, reason: id);
      }
    });

    test('model missing: Start shows the model gate, never band.delta', () {
      expect(gate('sleepGuard', _missing), GuardStartGate.needsModel);
      expect(blocked('sleepGuard', _missing), isTrue);
      expect(
        settings.sessionGuardFeatureFor('sleepGuard', aiReady: false),
        guardFeatureAiAVig,
      );
    });

    test('model installed but still loading: gate waits, never band.delta', () {
      expect(gate('sleepGuard', _loading), GuardStartGate.needsModel);
      expect(blocked('sleepGuard', _loading), isTrue);
    });

    test('model not ready / error: gated', () {
      const notReady = ModelEngineNotReady(
        kind: defaultModelKind,
        reason: 'verifying',
      );
      final error = ModelEngineError(kind: defaultModelKind, message: 'x');
      expect(gate('sleepGuard', notReady), GuardStartGate.needsModel);
      expect(gate('sleepGuard', error), GuardStartGate.needsModel);
      expect(blocked('sleepGuard', error), isTrue);
    });

    test('model ready: starts on the AI head', () {
      expect(gate('sleepGuard', _ready), GuardStartGate.start);
      expect(blocked('sleepGuard', _ready), isFalse);
      expect(
        settings.sessionGuardFeatureFor('sleepGuard', aiReady: true),
        guardFeatureAiAVig,
      );
    });

    test(
      'stored band.delta pick is ignored (no band-math sleepGuard)',
      () async {
        await settings.setGuardFeature('sleepGuard', guardFeatureBandDelta);
        expect(settings.guardFeatureFor('sleepGuard'), guardFeatureAiAVig);
        expect(gate('sleepGuard', _missing), GuardStartGate.needsModel);
      },
    );

    test('guard switched off: nothing to gate', () async {
      await settings.setGuardFeature('sleepGuard', guardFeatureNone);
      expect(gate('sleepGuard', _missing), GuardStartGate.start);
      expect(blocked('sleepGuard', _missing), isFalse);
    });
  });

  group('other protocols keep the band.delta fallback', () {
    for (final engine in <ModelEngineState>[_missing, _loading]) {
      test('restAwake starts on band.delta (${engine.runtimeType})', () {
        expect(gate('restAwake', engine), GuardStartGate.start);
        expect(blocked('restAwake', engine), isFalse);
        expect(
          settings.sessionGuardFeatureFor('restAwake', aiReady: false),
          guardFeatureBandDelta,
        );
      });
    }

    test('explicit AI pick still gates, but is not hard-blocked', () async {
      await settings.setGuardFeature('openMonitor', guardFeatureAiAVig);
      expect(gate('openMonitor', _missing), GuardStartGate.needsModel);
      expect(blocked('openMonitor', _missing), isFalse);
    });

    test('guard-less protocols never gate', () {
      for (final id in ['alertOpen', 'calibrateRecord', 'recordOnly']) {
        expect(gate(id, _missing), GuardStartGate.start, reason: id);
      }
    });
  });
}
