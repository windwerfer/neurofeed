import 'package:flutter/foundation.dart';

bool get museAgentEnabled =>
    kDebugMode && const bool.fromEnvironment('MUSE_AGENT', defaultValue: false);

bool get museDebugEnabled =>
    kDebugMode && const bool.fromEnvironment('MUSE_DEBUG', defaultValue: false);
