import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/streaming/streaming_controller.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';
import 'package:muse_ml/src/views/streaming_view.dart';

StreamingUiState _state({
  bool connected = false,
  bool streaming = false,
  bool enabled = false,
  StreamProtocol protocol = StreamProtocol.osc,
}) =>
    StreamingUiState(
      connected: connected,
      streaming: streaming,
      protocol: protocol,
      enabled: enabled,
      groups: const [],
      bytesSent: 0,
      packetsSent: 0,
    );

void main() {
  group('streamBadgeOf', () {
    test('off when disabled and idle', () {
      expect(streamBadgeOf(_state()), StreamBadgeState.off);
    });

    test('armed when enabled but no device', () {
      expect(streamBadgeOf(_state(enabled: true)), StreamBadgeState.armed);
      expect(
        streamBadgeOf(_state(connected: true, enabled: true)),
        StreamBadgeState.armed,
      );
    });

    test('live while streaming (takes precedence over enabled)', () {
      expect(
        streamBadgeOf(_state(connected: true, enabled: true, streaming: true)),
        StreamBadgeState.live,
      );
      expect(
        streamBadgeOf(_state(connected: true, streaming: true)),
        StreamBadgeState.live,
      );
    });
  });

  group('subnetOfPrivateIp', () {
    test('private subnets are detected', () {
      expect(subnetOfPrivateIp('192.168.200.34'), '192.168.200');
      expect(subnetOfPrivateIp('10.0.2.15'), '10.0.2');
      expect(subnetOfPrivateIp('172.16.5.9'), '172.16.5');
      expect(subnetOfPrivateIp('172.31.255.1'), '172.31.255');
    });

    test('public, link-local and malformed IPs are rejected', () {
      expect(subnetOfPrivateIp('8.8.8.8'), isNull);
      expect(subnetOfPrivateIp('169.254.3.7'), isNull);
      expect(subnetOfPrivateIp('172.32.0.1'), isNull);
      expect(subnetOfPrivateIp('192.169.1.1'), isNull);
      expect(subnetOfPrivateIp('not-an-ip'), isNull);
      expect(subnetOfPrivateIp('256.1.1.1'), isNull);
      expect(subnetOfPrivateIp('192.168.1'), isNull);
    });
  });
}