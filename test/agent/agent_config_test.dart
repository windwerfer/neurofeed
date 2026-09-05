import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/agent/agent_flags.dart';
import 'package:muse_ml/src/agent/agent_server_config.dart';

void main() {
  test('fromEnvironment is disabled without MUSE_AGENT define', () {
    expect(museAgentEnabled, isFalse);
    expect(AgentServerConfig.fromEnvironment().enabled, isFalse);
  });

  test('injected config can enable without fromEnvironment', () {
    const cfg = AgentServerConfig(enabled: true, port: 0, portMax: 0);
    expect(cfg.enabled, isTrue);
    expect(cfg.port, 0);
  });
}
