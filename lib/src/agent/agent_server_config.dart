import 'package:neurofeed/src/agent/agent_flags.dart';

class AgentServerConfig {
  const AgentServerConfig({
    required this.enabled,
    this.port = 17890,
    this.portMax = 17899,
  });

  factory AgentServerConfig.fromEnvironment() =>
      AgentServerConfig(enabled: neurofeedAgentEnabled);

  final bool enabled;
  final int port;
  final int portMax;
}
