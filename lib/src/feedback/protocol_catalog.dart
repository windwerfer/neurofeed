import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:neurofeed/src/feedback/feature_catalog.dart';
import 'package:neurofeed/src/feedback/protocol.dart';
import 'package:neurofeed/src/feedback/user_protocol_store.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';
import 'package:neurofeed/src/rust/api/features.dart';

export 'package:neurofeed/src/feedback/protocol.dart' show ProtocolCopy;

class ProtocolCatalog {
  const ProtocolCatalog({
    required this.version,
    required this.byName,
    required this.features,
  });

  static const empty = ProtocolCatalog(
    version: 4,
    byName: {},
    features: FeatureCatalog.empty,
  );

  final int version;
  final Map<String, ProtocolDocument> byName;
  final FeatureCatalog features;

  /// Document for [protocolId]. Retired catalog ids (see
  /// [legacyProtocolAliases]) resolve to their current document, so old
  /// sessions, settings and agent calls still find a protocol. The returned
  /// document's [ProtocolDocument.id] is the current id.
  ProtocolDocument? forName(String protocolId) =>
      byName[protocolId] ?? byName[canonicalProtocolId(protocolId)];

  List<ProtocolDocument> get all => byName.values.toList();

  factory ProtocolCatalog.fromJson(
    Map json, {
    required FeatureCatalog features,
  }) {
    final mapJson = Map<String, Object?>.from(json);
    final version = mapJson['version'] as int? ?? 0;
    if (version != 4) {
      throw FormatException(
        'ProtocolCatalog.fromJson reads v4 only (got $version)',
      );
    }
    final raw = mapJson['protocols'];
    final map = raw is Map
        ? Map<String, Object?>.from(raw)
        : const <String, Object?>{};
    return ProtocolCatalog(
      version: version,
      features: features,
      byName: {
        for (final entry in map.entries)
          if (entry.value is Map)
            entry.key: ProtocolDocument.fromJson(
              jsonObject(entry.value),
              id: entry.key,
              features: features,
            ),
      },
    );
  }

  static const String asset = 'assets/protocols.json';

  /// Asset catalog plus any `protocols/*.json` under the app-support dir.
  static Future<ProtocolCatalog> load() async {
    final features = await FeatureCatalog.load();
    final raw = await rootBundle.loadString(asset);
    var catalog = ProtocolCatalog.fromJson(
      jsonDecode(raw) as Map,
      features: features,
    );
    catalog = await catalog.mergeUserProtocols();
    return catalog;
  }

  Future<ProtocolCatalog> mergeUserProtocols({Directory? directory}) async {
    final dir = directory ?? await UserProtocolStore.resolveDirectory();
    if (dir == null || !await dir.exists()) return this;
    final extra = Map<String, ProtocolDocument>.from(byName);
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map) continue;
        final json = Map<String, Object?>.from(decoded);
        final fallbackId = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last.replaceAll('.json', '');
        final id = json['id'] as String? ?? fallbackId;
        if (id.isEmpty) continue;
        if (extra.containsKey(id) ||
            catalogProtocolIds.contains(id) ||
            isLegacyProtocolId(id)) {
          continue;
        }
        if (!userProtocolIdPattern.hasMatch(id)) continue;
        extra[id] = ProtocolDocument.fromJson(
          jsonObject(json),
          id: id,
          features: features,
          defaultOrigin: 'user',
        );
      } catch (_) {
        continue;
      }
    }
    return ProtocolCatalog(version: version, byName: extra, features: features);
  }

  List<ProtocolDocument> listedFor({
    required DeviceKind kind,
    required List<FeatureInfo> available,
    required bool anyModelInstalled,
  }) {
    return [
      for (final doc in all)
        if (doc.isListedOn(
          kind: kind,
          available: available,
          anyModelInstalled: anyModelInstalled,
        ))
          doc,
    ];
  }
}

final protocolCatalogProvider = FutureProvider<ProtocolCatalog>((ref) async {
  return ProtocolCatalog.load();
});

final availableFeaturesProvider =
    FutureProvider.family<List<FeatureInfo>, DeviceKind>((ref, kind) {
      return availableFeatures(kind: kind);
    });

ProtocolDocument protocolOrPlaceholder(ProtocolCatalog? catalog, String id) =>
    catalog?.forName(id) ?? ProtocolDocument.placeholder(id: id);

/// The document a saved session actually ran: the `protocolJson` snapshot
/// recorded with the session when it parses, else the catalog document for
/// [protocol] (legacy ids resolve through the alias map).
///
/// Prefer this over [ProtocolCatalog.forName] wherever the recipe is
/// recomputed from a saved session (charts, export, PDF): a dropped protocol
/// such as `twilight` aliases to `restAwake` for display, but its saved
/// snapshot still carries the TAR reward it actually ran.
ProtocolDocument? savedProtocolDocument(
  ProtocolCatalog catalog, {
  required String protocol,
  Map<String, Object?>? protocolJson,
}) {
  if (protocolJson != null) {
    try {
      final id = protocol.isNotEmpty
          ? protocol
          : protocolJson['id'] as String? ?? '';
      return ProtocolDocument.fromJson(
        protocolJson,
        id: id,
        features: catalog.features,
      );
    } catch (_) {}
  }
  return catalog.forName(protocol);
}

String protocolListTitle(ProtocolCatalog? catalog, String id) {
  final copy = catalog?.forName(id)?.copy;
  if (copy == null || copy.title.isEmpty) return id;
  return copy.title;
}

/// Resolved copy for [info] from the catalog. While the catalog is still
/// loading an empty copy is returned so cards render without asserting.
ProtocolCopy useProtocolCopy(WidgetRef ref, ProtocolDocument info) {
  final catalogAsync = ref.watch(protocolCatalogProvider);
  if (catalogAsync.isLoading || catalogAsync.hasError) {
    return ProtocolCopy.empty;
  }
  final catalog = catalogAsync.valueOrNull;
  final protocolInfo = catalog?.forName(info.id);
  return protocolInfo?.copy ?? info.copy;
}
