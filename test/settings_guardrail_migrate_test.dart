import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/guardrail_mode.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unknown protocol key + mixed leftover values do not throw', () async {
    SharedPreferences.setMockInitialValues({
      'guardrail_mode': jsonEncode({
        'notAProtocol': 'drowsinessMath',
        'restAwake': 'drowsinessMath',
        'sleepGuard': {'feature': 'band.delta'},
        'garbage': 12,
      }),
    });
    final settings = await Settings.load();
    expect(settings.guardFeatureFor('restAwake'), guardFeatureBandDelta);
    // sleepGuard requires the model: a stored band.delta resolves to its AI
    // feature (guard.requiresModel).
    expect(settings.guardFeatureFor('sleepGuard'), guardFeatureAiAVig);
    expect(settings.guardFeatureFor('notAProtocol'), guardFeatureNone);
  });

  test(
    'alertOpen, calibrateRecord and recordOnly do not gain a guard',
    () async {
      SharedPreferences.setMockInitialValues({
        'guardrail_mode': jsonEncode({
          'alertOpen': 'drowsinessMath',
          'recordOnly': {'feature': 'band.delta'},
          'calibrateRecord': {'feature': 'ai.a_vig'},
        }),
      });
      final settings = await Settings.load();
      for (final id in ['alertOpen', 'recordOnly', 'calibrateRecord']) {
        expect(settings.guardFeatureFor(id), guardFeatureNone, reason: id);
        expect(settings.guardrailEnabledFor(id), isFalse, reason: id);
      }
    },
  );

  test(
    'empty prefs: guard rows default to the catalog guard feature',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await Settings.load();
      for (final id in [
        'sleepGuard',
        'restAwake',
        'openMonitor',
        'alertClosed',
      ]) {
        expect(settings.guardFeatureFor(id), guardFeatureAiAVig, reason: id);
        expect(settings.hasGuardFeaturePref(id), isFalse, reason: id);
      }
      // concentrate: optional guard, defaultEnabled false.
      expect(settings.guardFeatureFor('concentrate'), guardFeatureNone);
      expect(settings.guardFeatureFor('alertOpen'), guardFeatureNone);
      expect(settings.guardFeatureFor('recordOnly'), guardFeatureNone);
      expect(settings.guardFeatureFor('calibrateRecord'), guardFeatureNone);
      // The migration must not pin band.delta for rows without a pref.
      final stored =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                      'guardrail_mode',
                    ) ??
                    '{}',
              )
              as Map;
      expect(stored.containsKey('restAwake'), isFalse);
      expect(stored.containsKey('sleepGuard'), isFalse);
    },
  );

  test('no AI model ready: catalog-default AI guard falls back to band.delta '
      '(except sleepGuard, which requires the model)', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    expect(
      settings.sessionGuardFeatureFor('sleepGuard', aiReady: false),
      guardFeatureAiAVig,
    );
    expect(
      settings.sessionGuardFeatureFor('restAwake', aiReady: false),
      guardFeatureBandDelta,
    );
    expect(
      settings.sessionGuardFeatureFor('sleepGuard', aiReady: true),
      guardFeatureAiAVig,
    );
    // Guard-less / default-off rows stay off either way.
    expect(
      settings.sessionGuardFeatureFor('alertOpen', aiReady: false),
      guardFeatureNone,
    );
    expect(
      settings.sessionGuardFeatureFor('concentrate', aiReady: true),
      guardFeatureNone,
    );
  });

  test('explicit AI pref is kept when no model is ready (as before)', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    await settings.setGuardFeature('restAwake', guardFeatureAiWakeLight);
    expect(settings.hasGuardFeaturePref('restAwake'), isTrue);
    expect(
      settings.sessionGuardFeatureFor('restAwake', aiReady: false),
      guardFeatureAiWakeLight,
    );
    await settings.setGuardFeature('concentrate', guardFeatureBandDelta);
    expect(settings.guardFeatureFor('concentrate'), guardFeatureBandDelta);
  });

  test(
    'mixed AI leftovers under old ids: first freeze-order isAi wins guard_model',
    () async {
      SharedPreferences.setMockInitialValues({
        'guardrail_mode': jsonEncode({
          'drowsiness': 'drowsinessLunaLarge',
          'twilight': 'drowsinessReveBase',
        }),
      });
      final settings = await Settings.load();
      expect(settings.guardModel, 'cbramod_a_vig');
      // drowsiness → restAwake carries the explicit (LUNA → Spur A) AI pick.
      expect(settings.guardFeatureFor('restAwake'), guardFeatureAiAVig);
      expect(settings.hasGuardFeaturePref('restAwake'), isTrue);
      // Legacy ids resolve to the current row.
      expect(settings.guardFeatureFor('drowsiness'), guardFeatureAiAVig);
    },
  );

  test(
    'legacy prefs: AI choices carry over, band.delta defaults do not',
    () async {
      SharedPreferences.setMockInitialValues({
        'guardrail_mode': jsonEncode({
          'guardrailOnly': {'feature': 'ai.wake_light'},
          'mindfulness': {'feature': 'band.delta'},
          'alertnessClosed': {'feature': 'ai.a_vig'},
          // Current id already set: legacy value must not overwrite it.
          'restAwake': {'feature': 'band.delta'},
          'drowsiness': {'feature': 'ai.a_vig'},
          'twilight': {'feature': 'ai.a_vig'},
        }),
      });
      final settings = await Settings.load();
      expect(settings.guardFeatureFor('sleepGuard'), guardFeatureAiWakeLight);
      expect(settings.guardFeatureFor('alertClosed'), guardFeatureAiAVig);
      expect(settings.guardFeatureFor('restAwake'), guardFeatureBandDelta);
      // band.delta under an old id was the old auto default, not a choice.
      expect(settings.hasGuardFeaturePref('openMonitor'), isFalse);
      expect(settings.guardFeatureFor('openMonitor'), guardFeatureAiAVig);
      final stored =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'guardrail_mode',
                )!,
              )
              as Map;
      for (final legacy in [
        'guardrailOnly',
        'mindfulness',
        'alertnessClosed',
        'drowsiness',
        'twilight',
      ]) {
        expect(stored.containsKey(legacy), isFalse, reason: legacy);
      }
    },
  );

  test('inhibit ceiling overrides persist per protocol', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    expect(settings.inhibitCeilingOverrides('concentrate'), isEmpty);
    await settings.setInhibitCeiling('concentrate', 'beta', 0.22);
    expect(settings.inhibitCeilingOverrides('concentrate')['beta'], 0.22);
    // The legacy id reads the same row.
    expect(settings.inhibitCeilingOverrides('concentration')['beta'], 0.22);
    expect(settings.inhibitCeilingOverrides('restAwake'), isEmpty);
    await settings.clearInhibitCeilingOverrides('concentrate');
    expect(settings.inhibitCeilingOverrides('concentrate'), isEmpty);
  });

  test('legacy inhibit overrides move to the renamed protocol', () async {
    SharedPreferences.setMockInitialValues({
      'inhibit_ceilings': jsonEncode({
        'concentration': {'beta': 0.3},
        'relaxedConcentration': {'beta': 0.2, 'delta': 0.4},
      }),
    });
    final settings = await Settings.load();
    expect(settings.inhibitCeilingOverrides('concentrate'), {'beta': 0.3});
    // Merged-away rows are dropped, not mapped onto restAwake.
    expect(settings.inhibitCeilingOverrides('restAwake'), isEmpty);
    final stored =
        jsonDecode(
              (await SharedPreferences.getInstance()).getString(
                'inhibit_ceilings',
              )!,
            )
            as Map;
    expect(stored.keys, ['concentrate']);
  });
}
