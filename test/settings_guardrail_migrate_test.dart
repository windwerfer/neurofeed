import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/feedback/guardrail_mode.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unknown protocol key + mixed leftover values do not throw', () async {
    SharedPreferences.setMockInitialValues({
      'guardrail_mode': jsonEncode({
        'notAProtocol': 'drowsinessMath',
        'drowsiness': 'drowsinessMath',
        'twilight': {'feature': 'band.delta'},
        'garbage': 12,
      }),
    });
    final settings = await Settings.load();
    expect(settings.guardFeatureFor('drowsiness'), guardFeatureBandDelta);
    expect(settings.guardFeatureFor('twilight'), guardFeatureBandDelta);
    expect(settings.guardFeatureFor('notAProtocol'), guardFeatureNone);
  });

  test('alertnessOpen and recordOnly do not gain band.delta', () async {
    SharedPreferences.setMockInitialValues({
      'guardrail_mode': jsonEncode({
        'alertnessOpen': 'drowsinessMath',
        'recordOnly': {'feature': 'band.delta'},
      }),
    });
    final settings = await Settings.load();
    expect(settings.guardFeatureFor('alertnessOpen'), guardFeatureNone);
    expect(settings.guardFeatureFor('recordOnly'), guardFeatureNone);
    expect(settings.guardrailEnabledFor('alertnessOpen'), isFalse);
    expect(settings.guardrailEnabledFor('recordOnly'), isFalse);
  });

  test('empty prefs: closed-eye catalog rows start ON as band.delta', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    expect(settings.guardFeatureFor('drowsiness'), guardFeatureBandDelta);
    expect(settings.guardFeatureFor('alertnessClosed'), guardFeatureBandDelta);
    expect(settings.guardFeatureFor('mindfulness'), guardFeatureBandDelta);
    expect(settings.guardFeatureFor('concentration'), guardFeatureBandDelta);
    expect(settings.guardFeatureFor('alertnessOpen'), guardFeatureNone);
    expect(settings.guardFeatureFor('recordOnly'), guardFeatureNone);
  });

  test('mixed AI leftovers: first freeze-order isAi wins guard_model', () async {
    SharedPreferences.setMockInitialValues({
      'guardrail_mode': jsonEncode({
        'drowsiness': 'drowsinessLunaLarge',
        'twilight': 'drowsinessReveBase',
      }),
    });
    final settings = await Settings.load();
    expect(settings.guardModel, 'luna_large');
    expect(settings.guardFeatureFor('drowsiness'), guardFeatureAiDrowsiness);
    expect(settings.guardFeatureFor('twilight'), guardFeatureAiDrowsiness);
  });
}
