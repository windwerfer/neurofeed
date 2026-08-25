import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:muse_ml/src/feedback/protocol.dart';

/// User-facing protocol copy loaded from `assets/protocols.json` — the single
/// editable place for catch phrase / title / subtitle / guide text /
/// algorithm description / expected delay / scientific metadata description
/// (and the structural `calibration` reference read by `CalibrationManifest`).
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

  factory ProtocolCopy.fromProtocolInfo(ProtocolInfo info) => ProtocolCopy(
    catchPhrase: info.catchPhrase,
    title: info.title,
    subtitle: info.subtitle,
    guideText: info.guideText,
    algorithmDescription: info.algorithmDescription,
    expectedDelay: info.expectedDelay,
    metadataDescription: info.metadataDescription,
  );
}

class ProtocolCatalog {
  const ProtocolCatalog({required this.version, required this.byName});

  final int version;
  final Map<String, ProtocolInfo> byName;

  ProtocolInfo? forName(String protocolName) => byName[protocolName];

  List<ProtocolInfo> get all => byName.values.toList();

  factory ProtocolCatalog.fromJson(Map<String, Object?> json) {
    final raw = json['protocols'] as Map<String, Object?>? ?? const {};
    return ProtocolCatalog(
      version: json['version'] as int? ?? 1,
      byName: {
        for (final entry in raw.entries)
          if (entry.value is Map<String, Object?>)
            entry.key: ProtocolInfo.fromJson(
              entry.value as Map<String, Object?>,
              entry.key,
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
  final catalog = catalogAsync.valueOrNull;
  assert(
    catalog != null,
    'Protocol catalog not loaded',
  );
  final protocolInfo = catalog?.forName(info.type.name);
  assert(
    protocolInfo != null,
    'assets/protocols.json is missing an entry for ${info.type.name}',
  );
  return protocolInfo != null
      ? ProtocolCopy.fromProtocolInfo(protocolInfo)
      : ProtocolCopy.empty;
}