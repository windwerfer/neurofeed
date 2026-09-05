import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/agent/agent_server.dart';
import 'package:muse_ml/src/agent/agent_server_config.dart';

void main() {
  tearDown(() async {
    await AgentServer.stop();
  });

  test('disabled start does not bind', () async {
    await AgentServer.start(
      ProviderContainer(),
      const AgentServerConfig(enabled: false, port: 0, portMax: 0),
    );
    expect(AgentServer.port, isNull);
  });

  test('enabled start binds loopback and serves /health', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await AgentServer.start(
      container,
      const AgentServerConfig(enabled: true, port: 0, portMax: 0),
    );
    final port = AgentServer.port;
    expect(port, isNotNull);
    expect(port, greaterThan(0));

    final client = HttpClient();
    addTearDown(client.close);
    final req = await client.get('127.0.0.1', port!, '/health');
    final res = await req.close();
    expect(res.statusCode, 200);
    final body = jsonDecode(await utf8.decoder.bind(res).join()) as Map;
    expect(body['ok'], true);
  });
}
