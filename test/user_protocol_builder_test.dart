import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:muse_ml/src/feedback/feature_catalog.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/protocol_catalog.dart';
import 'package:muse_ml/src/feedback/user_protocol_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FeatureCatalog features;
  late ProtocolCatalog catalog;

  setUpAll(() async {
    features = FeatureCatalog.fromJson(
      jsonDecode(await rootBundle.loadString(FeatureCatalog.asset)) as Map,
    );
    catalog = ProtocolCatalog.fromJson(
      jsonDecode(await rootBundle.loadString(ProtocolCatalog.asset)) as Map,
      features: features,
    );
  });

  ProtocolDocument draft({
    String id = 'user.my-rest',
    ProtocolReward? reward,
    ProtocolGuard? guard,
    bool includeReward = true,
    String origin = 'user',
    String calibration = 'eyes-closed-01',
    List<String> locked = const ['feature'],
  }) {
    return ProtocolDocument(
      id: id,
      origin: origin,
      schemaVersion: 1,
      copy: const ProtocolCopy(
        catchPhrase: 'My Rest',
        title: 'Custom ATR rest',
        subtitle: 'A user bookmark.',
        guideText: 'Close your eyes and rest.',
        algorithmDescription: 'Rewards ATR on the feature electrodes.',
        expectedDelay: '~1s',
        metadataDescription: 'User ATR rest bookmark.',
      ),
      colorValue: 16738533,
      calibration: calibration,
      reward: includeReward
          ? (reward ??
                ProtocolReward(
                  feature: 'band.atr',
                  output: 'chime',
                  locked: locked,
                ))
          : null,
      guard: guard,
    );
  }

  group('FeatureCatalog pickers', () {
    test('reward choices include band.atr; guard choices never do', () {
      final reward = features.rewardChoices();
      final guard = features.guardChoices();
      expect(reward.map((e) => e.id), contains('band.atr'));
      expect(guard.map((e) => e.id), isNot(contains('band.atr')));
      expect(
        guard.map((e) => e.id),
        containsAll(['band.delta', 'ai.drowsiness']),
      );
      for (final e in guard) {
        expect(e.usableAsGuard(), isTrue);
        expect(e.usableAsReward() && !e.usableAsGuard(), isFalse);
      }
    });

    test('availableIds intersection hides unavailable features', () {
      final reward = features.rewardChoices(
        availableIds: {'band.atr', 'device.focus'},
      );
      expect(reward.map((e) => e.id), ['band.atr', 'device.focus']);
      final guard = features.guardChoices(
        availableIds: {'band.atr', 'band.delta'},
      );
      expect(guard.map((e) => e.id), ['band.delta']);
      expect(guard.map((e) => e.id), isNot(contains('band.atr')));
    });
  });

  group('validateUserProtocolId', () {
    test('accepts user.<slug>', () {
      expect(() => validateUserProtocolId('user.abc'), returnsNormally);
      expect(() => validateUserProtocolId('user.my-rest'), returnsNormally);
    });

    test('rejects invalid slug and catalog ids', () {
      expect(
        () => validateUserProtocolId('drowsiness'),
        throwsA(isA<UserProtocolException>()),
      );
      expect(
        () => validateUserProtocolId('user.ab'),
        throwsA(isA<UserProtocolException>()),
      );
      expect(
        () => validateUserProtocolId('user.ABC'),
        throwsA(isA<UserProtocolException>()),
      );
      expect(
        () => validateUserProtocolId('custom.foo'),
        throwsA(isA<UserProtocolException>()),
      );
    });

    test('suggestUserProtocolSlug slugs a catch phrase', () {
      expect(suggestUserProtocolSlug('My Rest'), 'my-rest');
      expect(suggestUserProtocolSlug('  Alpha  / Theta  '), 'alpha-theta');
    });
  });

  group('UserProtocolStore save/load', () {
    late Directory dir;
    late UserProtocolStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('user_proto_');
      store = UserProtocolStore(directory: dir, features: features);
    });

    tearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    test('saves origin user, locked [], filename user.<slug>.json', () async {
      final saved = await store.save(draft());
      expect(saved.origin, 'user');
      expect(saved.reward!.locked, isEmpty);
      expect(saved.calibrationSkippable, isFalse);
      final file = File('${dir.path}/user.my-rest.json');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(await file.readAsString()) as Map;
      expect(json['id'], 'user.my-rest');
      expect(json['origin'], 'user');
      expect(json['reward'], isA<Map>());
      expect((json['reward'] as Map)['locked'], isEmpty);
      expect((json['reward'] as Map)['feature'], 'band.atr');
    });

    test('rejects catalog-id collision and writes nothing', () async {
      await expectLater(
        store.save(draft(id: 'drowsiness')),
        throwsA(isA<UserProtocolException>()),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('rejects an existing user file', () async {
      await store.save(draft());
      await expectLater(
        store.save(draft()),
        throwsA(
          isA<UserProtocolException>().having(
            (e) => e.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
    });

    test('overwrite of the same id is allowed', () async {
      await store.save(draft());
      final again = await store.save(
        draft(reward: const ProtocolReward(feature: 'band.alpha')),
        overwriteId: 'user.my-rest',
      );
      expect(again.reward!.feature, 'band.alpha');
      expect(File('${dir.path}/user.my-rest.json').existsSync(), isTrue);
    });

    test(
      'band.atr as guard is rejected at save and no file is written',
      () async {
        await expectLater(
          store.save(
            draft(
              includeReward: false,
              guard: const ProtocolGuard(feature: 'band.atr'),
            ),
          ),
          throwsA(
            isA<UserProtocolException>().having(
              (e) => e.message,
              'message',
              contains('guard.feature'),
            ),
          ),
        );
        expect(dir.listSync(), isEmpty);
      },
    );

    test('ProtocolGuard.fromJson rejects band.atr', () {
      expect(
        () =>
            ProtocolGuard.fromJson({'feature': 'band.atr'}, features: features),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('user.drowsiness is not a catalog-id collision', () async {
      final saved = await store.save(draft(id: 'user.drowsiness'));
      expect(saved.id, 'user.drowsiness');
    });

    test('mergeUserProtocols loads a hand-built user JSON', () async {
      await File('${dir.path}/user.hand-built.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'id': 'user.hand-built',
          'origin': 'user',
          'schemaVersion': 1,
          'copy': {
            'catchPhrase': 'Hand Built',
            'title': 'ATR + delta guard',
            'subtitle': 'Same path as catalog.',
            'guideText': 'Rest.',
            'algorithmDescription': 'band.atr reward, band.delta guard.',
            'expectedDelay': '~1s',
            'metadataDescription': 'Hand-built user protocol.',
          },
          'color': 16738533,
          'calibration': 'eyes-closed-01',
          'calibrationSkippable': false,
          'background': {'kind': 'drone'},
          'reward': {
            'feature': 'band.atr',
            'output': 'chime',
            'policy': 'percentileUptrain',
            'inhibit': [],
            'locked': [],
          },
          'guard': {
            'feature': 'band.delta',
            'output': 'softBowl',
            'policy': 'percentileWarn',
            'muffleReward': true,
            'defaultEnabled': true,
            'locked': [],
          },
        }),
      );
      final merged = await catalog.mergeUserProtocols(directory: dir);
      final doc = merged.forName('user.hand-built');
      expect(doc, isNotNull);
      expect(doc!.origin, 'user');
      expect(doc.isUserDocument, isTrue);
      expect(doc.reward!.feature, 'band.atr');
      expect(doc.guard!.feature, 'band.delta');
      expect(doc.calibration, 'eyes-closed-01');
      expect(doc.hasReward, isTrue);
      expect(doc.guardrailAllowed, isTrue);
    });

    test('loader skips a catalog-id collision file', () async {
      await File('${dir.path}/drowsiness.json').writeAsString(
        jsonEncode({
          'id': 'drowsiness',
          'origin': 'user',
          'schemaVersion': 1,
          'copy': {
            'catchPhrase': 'Nope',
            'title': 'Nope',
            'subtitle': 'Nope',
            'guideText': 'Nope',
            'algorithmDescription': 'Nope',
            'metadataDescription': 'Nope',
          },
          'color': 1,
          'calibration': 'eyes-closed-01',
          'reward': {'feature': 'band.atr'},
        }),
      );
      final merged = await catalog.mergeUserProtocols(directory: dir);
      expect(merged.forName('drowsiness')!.origin, 'catalog');
      expect(merged.forName('drowsiness')!.copy.catchPhrase, isNot('Nope'));
    });

    test('delete removes the user file', () async {
      await store.save(draft());
      await store.delete('user.my-rest');
      expect(File('${dir.path}/user.my-rest.json').existsSync(), isFalse);
    });
  });
}
