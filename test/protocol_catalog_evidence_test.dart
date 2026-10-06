import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:neurofeed/src/audio/calibration_clips.dart';
import 'package:neurofeed/src/feedback/feature_catalog.dart';
import 'package:neurofeed/src/feedback/protocol.dart';
import 'package:neurofeed/src/feedback/protocol_catalog.dart';

/// The 2026-10 evidence-backed catalog (feedback_gym/PROTOCOL_CANDIDATES.md):
/// ids, recipes, calibration kind and the legacy-id alias map.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProtocolCatalog catalog;
  late Map<String, Object?> rawProtocols;

  setUpAll(() async {
    final features = FeatureCatalog.fromJson(
      jsonDecode(await rootBundle.loadString(FeatureCatalog.asset)) as Map,
    );
    final raw =
        jsonDecode(await rootBundle.loadString(ProtocolCatalog.asset)) as Map;
    rawProtocols = Map<String, Object?>.from(raw['protocols'] as Map);
    catalog = ProtocolCatalog.fromJson(raw, features: features);
  });

  test('catalog ids match catalogProtocolIds, in order', () {
    expect(rawProtocols.keys.toList(), catalogProtocolIds);
    expect(catalog.byName.keys.toList(), catalogProtocolIds);
    for (final id in catalogProtocolIds) {
      expect(catalog.byName[id]!.id, id);
    }
  });

  test('recipes match the approved table', () {
    ProtocolDocument d(String id) => catalog.byName[id]!;

    final sleepGuard = d('sleepGuard');
    expect(sleepGuard.reward, isNull);
    expect(sleepGuard.guard!.feature, 'ai.a_vig');
    expect(sleepGuard.guard!.defaultEnabled, isTrue);
    expect(sleepGuard.requiresStagedCalibration, isTrue);
    expect(sleepGuard.calibrationSkippable, isFalse);

    expect(d('restAwake').reward!.feature, 'band.atr');
    expect(d('restAwake').guard!.feature, 'ai.a_vig');
    expect(d('restAwake').guard!.muffleReward, isTrue);
    expect(d('restAwake').calibration, 'eyes-closed-01');

    expect(d('openMonitor').reward!.feature, 'band.alpha');
    expect(d('openMonitor').guard!.feature, 'ai.a_vig');
    expect(d('openMonitor').guard!.muffleReward, isFalse);

    expect(d('alertOpen').reward!.feature, 'band.btr');
    expect(d('alertOpen').guard, isNull);
    expect(d('alertOpen').calibration, 'eyes-open-01');

    expect(d('alertClosed').reward!.feature, 'band.btr');
    expect(d('alertClosed').guard!.feature, 'ai.a_vig');
    expect(d('alertClosed').calibration, 'eyes-closed-01');

    final concentrate = d('concentrate');
    expect(concentrate.reward!.feature, 'band.alpha');
    expect(concentrate.conditions, hasLength(1));
    expect(concentrate.conditions.single, isA<BetaCeiling>());
    expect((concentrate.conditions.single as BetaCeiling).maxBetaRel, 0.25);
    expect(concentrate.guard!.feature, 'ai.a_vig');
    expect(concentrate.guard!.defaultEnabled, isFalse, reason: 'optional');

    for (final id in [
      'restAwake',
      'openMonitor',
      'alertOpen',
      'alertClosed',
      'concentrate',
    ]) {
      expect(d(id).requiresStagedCalibration, isFalse, reason: id);
      expect(d(id).calibrationSkippable, isFalse, reason: id);
    }
    // No training protocol keeps a delta ceiling inhibit.
    for (final doc in catalog.all) {
      expect(doc.conditions.whereType<DeltaCeiling>(), isEmpty, reason: doc.id);
    }
  });

  test('calibrateRecord: staged calibration required, quiet record', () {
    final doc = catalog.byName['calibrateRecord']!;
    expect(doc.reward, isNull);
    expect(doc.guard, isNull);
    expect(doc.calibration, 'eyes-closed-01');
    expect(doc.calibrationKind, calibrationKindStaged);
    expect(doc.requiresStagedCalibration, isTrue);
    expect(doc.calibrationSkippable, isFalse);
    // No reward/guard → empty S, yet the plan is still fully staged.
    expect(
      CalibrationPlan.fromEnabledFeatures(
        const [],
        protocolRequiresStaged: doc.requiresStagedCalibration,
      ),
      CalibrationPlan.stagedAi,
    );
    // Round-trips through the session snapshot.
    final again = ProtocolDocument.fromJson(
      doc.toJson(),
      id: doc.id,
      features: catalog.features,
    );
    expect(again.requiresStagedCalibration, isTrue);
  });

  test(
    'recordOnly stays optional single calibration, distinct from calibrateRecord',
    () {
      final doc = catalog.byName['recordOnly']!;
      expect(doc.reward, isNull);
      expect(doc.guard, isNull);
      expect(doc.calibrationSkippable, isTrue);
      expect(doc.calibrationKind, calibrationKindAuto);
      expect(doc.toJson().containsKey('calibrationKind'), isFalse);
      expect(
        CalibrationPlan.fromEnabledFeatures(const []),
        CalibrationPlan.baselineOnly,
      );
    },
  );

  test('unknown calibrationKind is rejected', () {
    expect(
      () => ProtocolDocument.fromJson(
        {'calibration': 'eyes-closed-01', 'calibrationKind': 'triple'},
        id: 'user.bad-kind',
        features: catalog.features,
      ),
      throwsArgumentError,
    );
  });

  test('dropped ids are gone; stressDownshift not added', () {
    for (final id in [
      'twilight',
      'relaxedConcentration',
      'drowsiness',
      'mindfulness',
      'alertnessOpen',
      'alertnessClosed',
      'concentration',
      'guardrailOnly',
      'stressDownshift',
    ]) {
      expect(catalog.byName.containsKey(id), isFalse, reason: id);
    }
  });

  group('legacy alias map', () {
    const expected = {
      'drowsiness': 'restAwake',
      'mindfulness': 'openMonitor',
      'alertnessOpen': 'alertOpen',
      'alertnessClosed': 'alertClosed',
      'concentration': 'concentrate',
      'guardrailOnly': 'sleepGuard',
      'twilight': 'restAwake',
      'relaxedConcentration': 'restAwake',
    };

    test('maps every retired id to a current catalog id', () {
      expect(legacyProtocolAliases, expected);
      for (final target in legacyProtocolAliases.values) {
        expect(catalogProtocolIds, contains(target));
      }
      expect(legacyProtocolRenames, isNot(contains('twilight')));
      expect(legacyProtocolRenames, isNot(contains('relaxedConcentration')));
    });

    test('canonicalProtocolId passes current and user ids through', () {
      for (final id in catalogProtocolIds) {
        expect(canonicalProtocolId(id), id);
        expect(isLegacyProtocolId(id), isFalse);
      }
      expect(canonicalProtocolId('user.my-proto'), 'user.my-proto');
      expect(canonicalProtocolId(''), '');
      expect(canonicalProtocolId('drowsiness'), 'restAwake');
    });

    test('catalog.forName resolves old session ids with a title', () {
      expected.forEach((legacy, current) {
        final doc = catalog.forName(legacy);
        expect(doc, isNotNull, reason: legacy);
        expect(doc!.id, current);
        expect(protocolListTitle(catalog, legacy), isNot(legacy));
        expect(protocolListTitle(catalog, legacy), doc.title);
      });
      expect(catalog.forName('neverExisted'), isNull);
    });

    test('saved protocolJson wins over the alias for recomputation', () {
      // An old twilight session: alias says restAwake (ATR) for display, but
      // the snapshot records the TAR reward it actually ran.
      final doc = savedProtocolDocument(
        catalog,
        protocol: 'twilight',
        protocolJson: const {
          'id': 'twilight',
          'calibration': 'eyes-closed-01',
          'reward': {'feature': 'band.tar'},
          'guard': {'feature': 'band.delta'},
        },
      );
      expect(doc!.id, 'twilight');
      expect(doc.reward!.feature, 'band.tar');

      // No snapshot → alias fallback.
      final fallback = savedProtocolDocument(catalog, protocol: 'twilight');
      expect(fallback!.id, 'restAwake');

      // Unparseable snapshot → alias fallback.
      final broken = savedProtocolDocument(
        catalog,
        protocol: 'concentration',
        protocolJson: const {
          'reward': {'feature': 'not.a.feature'},
        },
      );
      expect(broken!.id, 'concentrate');
    });
  });
}
