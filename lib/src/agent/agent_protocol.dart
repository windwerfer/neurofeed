import 'package:muse_ml/src/connect_source.dart';
import 'package:muse_ml/src/rust/api/muse.dart';
import 'package:muse_ml/src/settings.dart';

class AgentHttpResult {
  const AgentHttpResult(this.status, this.body);

  final int status;
  final Map<String, Object?> body;

  bool get ok => status >= 200 && status < 300;
}

AgentHttpResult agentError(int status, String error, [String? message]) =>
    AgentHttpResult(status, {
      'ok': false,
      'error': error,
      'message': ?message,
    });

AppView? parseAppView(String? name) {
  if (name == null) return null;
  for (final v in AppView.values) {
    if (v.name == name) return v;
  }
  return null;
}

ConnectSource? parseConnectSource(String? name) {
  if (name == null) return null;
  for (final s in ConnectSource.values) {
    if (s.name == name) return s;
  }
  return null;
}

DeviceInfo? resolveAgentDevice(String id, List<DeviceInfo> scanned) {
  final sim = simulatorCatalogRow(id);
  if (sim != null) return sim;
  for (final d in scanned) {
    if (d.id == id) return d;
  }
  return null;
}

Map<String, Object?>? asJsonMap(Object? raw) {
  if (raw is Map<String, Object?>) return raw;
  if (raw is Map) return Map<String, Object?>.from(raw);
  return null;
}
