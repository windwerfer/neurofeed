import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Copy + `usableFor` for a feature id, loaded from `assets/features.json`.
class FeatureCatalogEntry {
  const FeatureCatalogEntry({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.source,
    required this.usableFor,
    this.rewardCopy,
    this.guardCopy,
  });

  final String id;
  final String label;
  final String shortLabel;
  final String source;
  final List<String> usableFor;
  final String? rewardCopy;
  final String? guardCopy;

  bool usableAsReward() => usableFor.contains('reward');
  bool usableAsGuard() => usableFor.contains('guard');

  factory FeatureCatalogEntry.fromJson(String id, Map<String, Object?> json) {
    return FeatureCatalogEntry(
      id: id,
      label: json['label'] as String? ?? id,
      shortLabel: json['shortLabel'] as String? ?? id,
      source: json['source'] as String? ?? '',
      usableFor: json['usableFor'] is List
          ? (json['usableFor'] as List).whereType<String>().toList()
          : const [],
      rewardCopy: json['rewardCopy'] as String?,
      guardCopy: json['guardCopy'] as String?,
    );
  }
}

class FeatureCatalog {
  const FeatureCatalog({required this.version, required this.byId});

  final int version;
  final Map<String, FeatureCatalogEntry> byId;

  FeatureCatalogEntry? operator [](String id) => byId[id];

  static const String asset = 'assets/features.json';

  static const FeatureCatalog empty = FeatureCatalog(version: 1, byId: {});

  factory FeatureCatalog.fromJson(Map json) {
    final mapJson = Map<String, Object?>.from(json);
    final raw = mapJson['features'];
    final map = raw is Map ? Map<String, Object?>.from(raw) : const <String, Object?>{};
    return FeatureCatalog(
      version: mapJson['version'] as int? ?? 1,
      byId: {
        for (final entry in map.entries)
          if (entry.value is Map)
            entry.key: FeatureCatalogEntry.fromJson(
              entry.key,
              Map<String, Object?>.from(entry.value as Map),
            ),
      },
    );
  }

  static Future<FeatureCatalog> load() async {
    final raw = await rootBundle.loadString(asset);
    return FeatureCatalog.fromJson(jsonDecode(raw) as Map);
  }
}

final featureCatalogProvider = FutureProvider<FeatureCatalog>((ref) async {
  return FeatureCatalog.load();
});
