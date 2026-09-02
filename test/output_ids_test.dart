import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/audio/output_ids.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rewardOutputIdFromStored', () {
    test('maps old FeedbackMode names 1:1 onto new ids', () {
      expect(rewardOutputIdFromStored('bowlChimes'), RewardOutputId.chime);
      expect(rewardOutputIdFromStored('rain'), RewardOutputId.rainStage);
      expect(rewardOutputIdFromStored('music'), RewardOutputId.musicFilter);
      expect(rewardOutputIdFromStored('binaural'), RewardOutputId.binauralSwell);
      expect(rewardOutputIdFromStored('none'), RewardOutputId.none);
    });

    test('accepts already-migrated ids', () {
      expect(rewardOutputIdFromStored('chime'), RewardOutputId.chime);
      expect(rewardOutputIdFromStored('rainStage'), RewardOutputId.rainStage);
      expect(rewardOutputIdFromStored('musicFilter'), RewardOutputId.musicFilter);
      expect(
        rewardOutputIdFromStored('binauralSwell'),
        RewardOutputId.binauralSwell,
      );
    });

    test('unknown and null fall back to chime', () {
      expect(rewardOutputIdFromStored(null), RewardOutputId.chime);
      expect(rewardOutputIdFromStored(''), RewardOutputId.chime);
      expect(rewardOutputIdFromStored('garbage'), RewardOutputId.chime);
    });
  });

  group('feedbackSoundLabel', () {
    test('old and new ids share display labels', () {
      expect(feedbackSoundLabel('bowlChimes'), 'Bowl chimes');
      expect(feedbackSoundLabel('chime'), 'Bowl chimes');
      expect(feedbackSoundLabel('rain'), 'Rain');
      expect(feedbackSoundLabel('rainStage'), 'Rain');
      expect(feedbackSoundLabel('music'), 'Music');
      expect(feedbackSoundLabel('musicFilter'), 'Music');
      expect(feedbackSoundLabel('binaural'), 'Binaural Beats');
      expect(feedbackSoundLabel('binauralSwell'), 'Binaural Beats');
      expect(feedbackSoundLabel('none'), 'None');
    });
  });

  group('suppress and muffle policy', () {
    test('rainStage and musicFilter suppress background', () {
      expect(RewardOutputId.rainStage.suppressesBackground, isTrue);
      expect(RewardOutputId.musicFilter.suppressesBackground, isTrue);
      expect(RewardOutputId.chime.suppressesBackground, isFalse);
      expect(RewardOutputId.binauralSwell.suppressesBackground, isFalse);
      expect(RewardOutputId.none.suppressesBackground, isFalse);
    });

    test('chime is not mufflable; modulated outputs are', () {
      expect(RewardOutputId.chime.mufflable, isFalse);
      expect(RewardOutputId.none.mufflable, isFalse);
      expect(RewardOutputId.musicFilter.mufflable, isTrue);
      expect(RewardOutputId.rainStage.mufflable, isTrue);
      expect(RewardOutputId.binauralSwell.mufflable, isTrue);
    });
  });

  group('resolveRewardOutputId', () {
    test('no-reward protocols force none', () {
      expect(
        resolveRewardOutputId(
          hasReward: false,
          storedPref: 'musicFilter',
          catalogOutput: 'chime',
        ),
        RewardOutputId.none,
      );
    });

    test('user pref wins over catalog', () {
      expect(
        resolveRewardOutputId(
          hasReward: true,
          storedPref: 'rain',
          catalogOutput: 'chime',
        ),
        RewardOutputId.rainStage,
      );
    });

    test('catalog default when pref is unset', () {
      expect(
        resolveRewardOutputId(
          hasReward: true,
          storedPref: null,
          catalogOutput: 'musicFilter',
        ),
        RewardOutputId.musicFilter,
      );
    });

    test('chime when both pref and catalog are empty', () {
      expect(
        resolveRewardOutputId(
          hasReward: true,
          storedPref: null,
          catalogOutput: null,
        ),
        RewardOutputId.chime,
      );
    });
  });

  group('resolveGuardOutputId', () {
    test('user pref wins; catalog when unset; softBowl default', () {
      expect(
        resolveGuardOutputId(storedPref: 'alarm', catalogOutput: 'softBowl'),
        'alarm',
      );
      expect(
        resolveGuardOutputId(storedPref: null, catalogOutput: 'cough'),
        'cough',
      );
      expect(
        resolveGuardOutputId(storedPref: null, catalogOutput: null),
        'softBowl',
      );
    });
  });

  group('Settings.feedback_mode migrate', () {
    test('eager rewrite bowlChimes → chime', () async {
      SharedPreferences.setMockInitialValues({'feedback_mode': 'bowlChimes'});
      final settings = await Settings.load();
      expect(settings.rewardOutputPref, 'chime');
      expect(settings.rewardOutput, RewardOutputId.chime);
    });

    test('eager rewrite rain/music/binaural', () async {
      SharedPreferences.setMockInitialValues({'feedback_mode': 'rain'});
      expect((await Settings.load()).rewardOutput, RewardOutputId.rainStage);

      SharedPreferences.setMockInitialValues({'feedback_mode': 'music'});
      expect((await Settings.load()).rewardOutput, RewardOutputId.musicFilter);

      SharedPreferences.setMockInitialValues({'feedback_mode': 'binaural'});
      expect(
        (await Settings.load()).rewardOutput,
        RewardOutputId.binauralSwell,
      );
    });

    test('already-new ids and unset pref stay as stored', () async {
      SharedPreferences.setMockInitialValues({'feedback_mode': 'musicFilter'});
      final set = await Settings.load();
      expect(set.rewardOutputPref, 'musicFilter');

      SharedPreferences.setMockInitialValues({});
      final unset = await Settings.load();
      expect(unset.rewardOutputPref, isNull);
      expect(unset.rewardOutput, RewardOutputId.chime);
      expect(unset.warningSoundPref, isNull);
    });
  });
}
