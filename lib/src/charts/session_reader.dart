import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';

export 'package:muse_ml/src/rust/api/session_format.dart'
    show BandsRecord, PulseRecord, MovementRecord, PeakAlphaRecord, SessionData;

class SessionReader {
  static Future<SessionData> read(File file) =>
      readBytes(file.readAsBytes(), label: file.path);

  static Future<SessionData> readBytes(
    Future<List<int>?> future, {
    String label = '<memory>',
  }) async {
    final bytes = await future;
    if (bytes == null) {
      throw const FormatException('No session bytes available');
    }
    return readRaw(bytes, label: label);
  }

  static Future<SessionData> readRaw(
    List<int> raw, {
    String label = '<memory>',
  }) async {
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    final session = await sessionParseBody(bytes: bytes);
    debugPrint(
        '[reader] $label: ${bytes.length}B bands=${session.bands.length} '
        'pulses=${session.pulses.length} mov=${session.movements.length} '
        'peak=${session.peakAlphas.length}');
    return session;
  }
}
