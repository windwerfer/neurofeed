import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/agent/agent_flags.dart';
import 'package:muse_ml/src/agent/agent_server_config.dart';

void main() {
  test('parseDartDefineFlag accepts true/1/yes, not bool.fromEnvironment 1', () {
    expect(parseDartDefineFlag('true'), isTrue);
    expect(parseDartDefineFlag('1'), isTrue);
    expect(parseDartDefineFlag('yes'), isTrue);
    expect(parseDartDefineFlag('TRUE'), isTrue);
    expect(parseDartDefineFlag(''), isFalse);
    expect(parseDartDefineFlag('false'), isFalse);
  });

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
