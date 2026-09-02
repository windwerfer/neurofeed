import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:muse_ml/src/feedback/feature_catalog.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/user_protocol_store.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';
import 'package:muse_ml/src/rust/api/features.dart';

export 'package:muse_ml/src/feedback/protocol.dart' show ProtocolCopy;

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

  ProtocolDocument? forName(String protocolId) => byName[protocolId];

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
        if (extra.containsKey(id) || catalogProtocolIds.contains(id)) {
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
