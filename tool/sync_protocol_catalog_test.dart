import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:muse_ml/src/feedback/protocol.dart';

/// Regenerates `assets/protocols.json` from the Dart copy in
/// `ProtocolInfo.all` (fallback text). Run with:
/// `flutter test tool/sync_protocol_catalog_test.dart`
void main() {
  test('sync protocol catalog asset', () {
    final byName = <String, Object?>{
      for (final p in ProtocolInfo.all)
        p.type.name: {
          'catchPhrase': p.catchPhrase,
          'title': p.title,
          'subtitle': p.subtitle,
          'guideText': p.guideText,
          'algorithmDescription': p.algorithmDescription,
          'expectedDelay': p.expectedDelay,
        },
    };
    final json = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'protocols': byName,
    });
    File('assets/protocols.json').writeAsStringSync('$json\n');
  });
}
