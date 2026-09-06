import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/audio/feedback_audio_controller.dart';
import 'package:muse_ml/src/audio/music_controller.dart';
import 'package:muse_ml/src/audio/rain_feedback_controller.dart';
import 'package:muse_ml/src/audio/reward_output.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('calibrationAwaitTimeout', () {
    test('zero length uses 60s', () {
      expect(
        calibrationAwaitTimeout(Duration.zero),
        const Duration(seconds: 60),
      );
    });

    test('pads by 2s with a 15s floor', () {
      expect(
        calibrationAwaitTimeout(const Duration(seconds: 10)),
        const Duration(seconds: 15),
      );
      expect(
        calibrationAwaitTimeout(const Duration(seconds: 20)),
        const Duration(seconds: 22),
      );
    });

    test('caps at 90s', () {
      expect(
        calibrationAwaitTimeout(const Duration(seconds: 100)),
        const Duration(seconds: 90),
      );
    });
  });

  group('rainStageWithHysteresis', () {
    test('maps percentile onto stage index 0–4', () {
      expect(rainStageIndexFor(0), 0);
      expect(rainStageIndexFor(19), 0);
      expect(rainStageIndexFor(20), 1);
      expect(rainStageIndexFor(40), 2);
      expect(rainStageIndexFor(60), 3);
      expect(rainStageIndexFor(80), 4);
      expect(rainStageIndexFor(100), 4);
    });

    test('holds the current stage inside the deadband', () {
      expect(rainStageWithHysteresis(current: 0, pct: 22), 0);
      expect(rainStageWithHysteresis(current: 1, pct: 18), 1);
      expect(rainStageWithHysteresis(current: 0, pct: 24), 1);
    });
  });

  group('moveCurrentToFront', () {
    test('moves the current index to 0 and returns 0', () {
      final order = [2, 0, 1];
      expect(moveCurrentToFront(order, 1), 0);
      expect(order, [0, 2, 1]);
    });

    test('leaves an invalid position unchanged', () {
      final order = [0, 1, 2];
      expect(moveCurrentToFront(order, -1), -1);
      expect(order, [0, 1, 2]);
    });
  });

  group('background binaural muffle callback', () {
    test(
      'chime and none call the callback and do not require own audio',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = await Settings.load();
        final calls = <(String, bool)>[];

        final chime = ChimeRewardOutput(
          FeedbackAudioController(settings),
          onBackgroundBinauralMuffle: (on) => calls.add(('chime', on)),
        );
        const none = NoneRewardOutput();
        final noneWired = NoneRewardOutput(
          onBackgroundBinauralMuffle: (on) => calls.add(('none', on)),
        );

        chime.setMuffle(true);
        none.setMuffle(true);
        noneWired.setMuffle(false);

        expect(calls, [('chime', true), ('none', false)]);
      },
    );
  });
}
