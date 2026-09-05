import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/agent/agent_commands.dart';
import 'package:muse_ml/src/agent/agent_protocol.dart';
import 'package:muse_ml/src/agent/agent_server_config.dart';

class AgentServer {
  static HttpServer? _server;

  static int? get port => _server?.port;

  static Future<void> start(
    ProviderContainer container,
    AgentServerConfig cfg,
  ) async {
    if (!cfg.enabled) return;
    await stop();
    HttpServer? bound;
    if (cfg.port == 0) {
      bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } else {
      SocketException? last;
      for (var p = cfg.port; p <= cfg.portMax; p++) {
        try {
          bound = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
          last = null;
          break;
        } on SocketException catch (e) {
          last = e;
        }
      }
      if (bound == null) {
        try {
          bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        } on SocketException catch (e) {
          debugPrint('[muse] agent-listen failed: ${last ?? e}');
          return;
        }
      }
    }
    _server = bound;
    final commands = AgentCommands(container);
    debugPrint('[muse] agent-listen ${bound.address.address}:${bound.port}');
    bound.listen((request) {
      unawaited(_handle(request, commands));
    });
  }

  static Future<void> stop() async {
    final s = _server;
    _server = null;
    if (s != null) {
      await s.close(force: true);
    }
  }

  static Future<void> _handle(
    HttpRequest request,
    AgentCommands commands,
  ) async {
    try {
      final raw = await utf8.decoder.bind(request).join();
      Map<String, Object?>? body;
      if (raw.isNotEmpty) {
        body = asJsonMap(jsonDecode(raw));
      }
      final result = await commands.handle(
        method: request.method,
        path: request.uri.path,
        body: body,
      );
      _write(request.response, result);
    } catch (e, st) {
      debugPrint('[muse] agent-http error: $e\n$st');
      _write(request.response, agentError(500, 'bad_request', e.toString()));
    }
  }

  static void _write(HttpResponse response, AgentHttpResult result) {
    response.statusCode = result.status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(result.body));
    response.close();
  }
}
