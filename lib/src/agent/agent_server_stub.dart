import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/agent/agent_server_config.dart';

class AgentServer {
  static int? get port => null;

  static Future<void> start(
    ProviderContainer container,
    AgentServerConfig cfg,
  ) async {}

  static Future<void> stop() async {}
}
