import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:muse_ml/src/feedback/protocol.dart';

/// User-facing protocol copy loaded from `assets/protocols.json` — the single
/// editable place for catch phrase / title / subtitle / guide text /
/// algorithm description / expected delay. Regenerate the asset from
/// `ProtocolInfo.all` with:
/// `flutter test tool/sync_protocol_catalog_test.dart`
/// Structure (colors, metrics, guardrail flags, conditions) stays in
/// `protocol.dart`.
class ProtocolCopy {
  const ProtocolCopy({
    required this.catchPhrase,
    required this.title,
    required this.subtitle,
    required this.guideText,
    required this.algorithmDescription,
    required this.expectedDelay,
  });

  final String catchPhrase;
  final String title;
  final String subtitle;
  final String guideText;
  final String algorithmDescription;
  final String expectedDelay;

  factory ProtocolCopy.fromJson(Map<String, Object?> json) => ProtocolCopy(
    catchPhrase: json['catchPhrase'] as String? ?? '',
    title: json['title'] as String? ?? '',
    subtitle: json['subtitle'] as String? ?? '',
    guideText: json['guideText'] as String? ?? '',
    algorithmDescription: json['algorithmDescription'] as String? ?? '',
    expectedDelay: json['expectedDelay'] as String? ?? '',
  );

  Map<String, String> toJson() => {
    'catchPhrase': catchPhrase,
    'title': title,
    'subtitle': subtitle,
    'guideText': guideText,
    'algorithmDescription': algorithmDescription,
    'expectedDelay': expectedDelay,
  };
}

class ProtocolCatalog {
  const ProtocolCatalog({required this.version, required this.byName});

  final int version;
  final Map<String, ProtocolCopy> byName;

  ProtocolCopy? forName(String protocolName) => byName[protocolName];

  factory ProtocolCatalog.fromJson(Map<String, Object?> json) {
    final raw = json['protocols'] as Map<String, Object?>? ?? const {};
    return ProtocolCatalog(
      version: json['version'] as int? ?? 1,
      byName: {
        for (final entry in raw.entries)
          if (entry.value is Map<String, Object?>)
            entry.key: ProtocolCopy.fromJson(
              entry.value as Map<String, Object?>,
            ),
      },
    );
  }

  static const String asset = 'assets/protocols.json';
}

final protocolCatalogProvider = FutureProvider<ProtocolCatalog>((ref) async {
  final raw = await rootBundle.loadString(ProtocolCatalog.asset);
  return ProtocolCatalog.fromJson(
    (jsonDecode(raw) as Map<String, Object?>),
  );
});

/// Resolved copy for [info]: the JSON entry when present, else the Dart
/// fallback text in `protocol.dart`. Watch this in `build()` so edits to
/// `assets/protocols.json` take effect without code changes.
ProtocolCopy useProtocolCopy(WidgetRef ref, ProtocolInfo info) {
  final copy = ref
      .watch(protocolCatalogProvider)
      .valueOrNull
      ?.forName(info.type.name);
  return ProtocolCopy(
    catchPhrase: copy?.catchPhrase ?? info.catchPhrase,
    title: copy?.title ?? info.title,
    subtitle: copy?.subtitle ?? info.subtitle,
    guideText: copy?.guideText ?? info.guideText,
    algorithmDescription: copy?.algorithmDescription ?? info.algorithmDescription,
    expectedDelay: copy?.expectedDelay ?? info.expectedDelay,
  );
}
