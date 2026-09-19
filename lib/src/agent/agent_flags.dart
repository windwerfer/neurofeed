import 'package:flutter/foundation.dart';

bool parseDartDefineFlag(String raw) {
  final v = raw.trim().toLowerCase();
  return v == 'true' || v == '1' || v == 'yes';
}

bool get neurofeedAgentEnabled =>
    kDebugMode &&
    parseDartDefineFlag(
      const String.fromEnvironment('NEUROFEED_AGENT', defaultValue: ''),
    );

bool get neurofeedDebugEnabled =>
    kDebugMode &&
    parseDartDefineFlag(
      const String.fromEnvironment('NEUROFEED_DEBUG', defaultValue: ''),
    );
