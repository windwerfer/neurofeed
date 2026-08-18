import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/streaming/streaming_lsl.dart';
import 'package:muse_ml/src/streaming/streaming_mixer.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';

/// Exercises the real liblsl native library: creates outlets, pushes samples,
/// destroys them. Fails early if the native asset is missing or broken.
void main() {
  test('LSL outlets create, push and destroy (native lib)', () async {
    final streamer = LslStreamer(
      const StreamingConfig(
        protocol: StreamProtocol.lsl,
        enabled: true,
        oscIp: null,
        oscPort: null,
        prefix: 'Smoke',
        separateGroups: true,
      ),
    );
    await streamer.start('test-device-1');
    streamer.push(
        GroupSample('eeg', 100.0, [1.0, 2.0, 3.0, 4.0]));
    streamer.push(
        GroupSample('ppg', 100.01, [0.1, 0.2, 0.3]));
    expect(streamer.packetsSent, 2);
    expect(streamer.bytesSent, 4 * (4 + 3));
    await streamer.stop();
  });
}