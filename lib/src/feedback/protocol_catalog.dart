import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:muse_ml/src/feedback/protocol.dart';

/// User-facing protocol copy loaded from `assets/protocols.json` — the single
/// editable place for catch phrase / title / subtitle / guide text /
/// algorithm description / expected delay / scientific metadata description
/// (and the structural `calibration` reference read by `CalibrationManifest`).
/// Structure (colors, metrics, conditions, guardrail flags) stays in
/// `protocol.dart`.
class ProtocolCopy {
  const ProtocolCopy({
    required this.catchPhrase,
    required this.title,
    required this.subtitle,
    required this.guideText,
    required this.algorithmDescription,
    required this.expectedDelay,
    this.metadataDescription,
  });

  static const ProtocolCopy empty = ProtocolCopy(
    catchPhrase: '',
    title: '',
    subtitle: '',
    guideText: '',
    algorithmDescription: '',
    expectedDelay: '',
  );

  final String catchPhrase;
  final String title;
  final String subtitle;
  final String guideText;
  final String algorithmDescription;
  final String expectedDelay;

  /// Scientific description of what the protocol trains and how, recorded
  /// into the `.muse.feedback` session metadata.
  final String? metadataDescription;

  factory ProtocolCopy.fromJson(Map<String, Object?> json) => ProtocolCopy(
    catchPhrase: json['catchPhrase'] as String? ?? '',
    title: json['title'] as String? ?? '',
    subtitle: json['subtitle'] as String? ?? '',
    guideText: json['guideText'] as String? ?? '',
    algorithmDescription: json['algorithmDescription'] as String? ?? '',
    expectedDelay: json['expectedDelay'] as String? ?? '',
    metadataDescription: json['metadataDescription'] as String?,
  );
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

/// Resolved copy for [info] from `assets/protocols.json` — the single source
/// of protocol text. While the catalog is still loading (first frame) an
/// empty copy is returned so cards render without asserting; once loaded, a
/// missing entry is a data error (surfaced by an assert in debug builds).
ProtocolCopy useProtocolCopy(WidgetRef ref, ProtocolInfo info) {
  final catalogAsync = ref.watch(protocolCatalogProvider);
  if (catalogAsync.isLoading || catalogAsync.hasError) {
    return ProtocolCopy.empty;
  }
  final copy = catalogAsync.valueOrNull?.forName(info.type.name);
  assert(
    copy != null,
    'assets/protocols.json is missing an entry for ${info.type.name}',
  );
  return copy ?? ProtocolCopy.empty;
}