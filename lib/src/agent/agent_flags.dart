import 'package:flutter/foundation.dart';

bool parseDartDefineFlag(String raw) {
  final v = raw.trim().toLowerCase();
  return v == 'true' || v == '1' || v == 'yes';
}

bool get museAgentEnabled =>
    kDebugMode &&
    parseDartDefineFlag(
      const String.fromEnvironment('MUSE_AGENT', defaultValue: ''),
    );

bool get museDebugEnabled =>
    kDebugMode &&
    parseDartDefineFlag(
      const String.fromEnvironment('MUSE_DEBUG', defaultValue: ''),
    );
