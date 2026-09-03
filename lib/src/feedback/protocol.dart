import 'package:flutter/material.dart';
import 'package:muse_ml/src/feedback/feature_catalog.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';
import 'package:muse_ml/src/rust/api/features.dart';

/// Frozen catalog protocol ids (on-disk `protocol` string in `.muse.feedback`).
const List<String> catalogProtocolIds = [
  'drowsiness',
  'twilight',
  'alertnessOpen',
  'alertnessClosed',
  'mindfulness',
  'concentration',
  'relaxedConcentration',
  'recordOnly',
  'guardrailOnly',
];

final RegExp userProtocolIdPattern = RegExp(r'^user\.[a-z0-9-]{3,64}$');

Map<String, Object?> jsonObject(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const <String, Object?>{};

/// Clear error when Start is refused on Crown (real or simulated).
const String crownSessionUnsupportedMessage =
    'Crown sessions are not available yet. You can browse band protocols, '
    'but running a session on Crown is a later update. Connect a Muse to start.';

/// A per-sample condition a composite protocol applies on top of the scalar
/// reward metric. The scalar must beat the baseline threshold AND every
/// condition must pass for the sample to count as in-target. All values are
/// relative band powers (fractions of total power, summing to 1 across the
/// five bands).
sealed class TargetCondition {
  const TargetCondition();

  bool passes({
    required double deltaRel,
    required double thetaRel,
    required double alphaRel,
    required double betaRel,
  });

  Map<String, Object?> toJson();
}

/// Rewards only while relative beta stays at or below [maxBetaRel] — the
/// "beta inhibit" leg of calm-focus protocols (discourages elevated
/// high-frequency activity).
class BetaCeiling extends TargetCondition {
  const BetaCeiling(this.maxBetaRel);
  final double maxBetaRel;

  @override
  bool passes({
    required double deltaRel,
    required double thetaRel,
    required double alphaRel,
    required double betaRel,
  }) => betaRel <= maxBetaRel;

  @override
  Map<String, Object?> toJson() => {'type': 'betaCeiling', 'max': maxBetaRel};
}

/// Rewards only while relative delta stays at or below [maxDeltaRel] — keeps
/// the state out of deep-sleep territory on protocols near the sleep edge.
class DeltaCeiling extends TargetCondition {
  const DeltaCeiling(this.maxDeltaRel);
  final double maxDeltaRel;

  @override
  bool passes({
    required double deltaRel,
    required double thetaRel,
    required double alphaRel,
    required double betaRel,
  }) => deltaRel <= maxDeltaRel;

  @override
  Map<String, Object?> toJson() => {'type': 'deltaCeiling', 'max': maxDeltaRel};
}

TargetCondition parseInhibit(Map<String, Object?> json) {
  switch (json['type']) {
    case 'betaCeiling':
      final max = json['max'] ?? json['maxBetaRel'];
      return BetaCeiling((max as num).toDouble());
    case 'deltaCeiling':
      final max = json['max'] ?? json['maxDeltaRel'];
      return DeltaCeiling((max as num).toDouble());
    default:
      throw ArgumentError('Unknown inhibit type: ${json['type']}');
  }
}

/// User-facing copy for a protocol document.
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

  Map<String, Object?> toJson() => {
    'catchPhrase': catchPhrase,
    'title': title,
    'subtitle': subtitle,
    'guideText': guideText,
    'algorithmDescription': algorithmDescription,
    'expectedDelay': expectedDelay,
    if (metadataDescription != null) 'metadataDescription': metadataDescription,
  };
}

class ProtocolBackground {
  const ProtocolBackground({this.kind = 'drone'});

  final String kind;

  factory ProtocolBackground.fromJson(Object? json) {
    if (json is Map) {
      return ProtocolBackground(
        kind: jsonObject(json)['kind'] as String? ?? 'drone',
      );
    }
    return const ProtocolBackground();
  }

  Map<String, Object?> toJson() => {'kind': kind};
}

class ProtocolReward {
  const ProtocolReward({
    required this.feature,
    this.output = 'chime',
    this.policy = 'percentileUptrain',
    this.inhibit = const [],
    this.electrodes,
    this.locked = const [],
  });

  final String feature;
  final String output;
  final String policy;
  final List<TargetCondition> inhibit;
  final List<String>? electrodes;
  final List<String> locked;

  factory ProtocolReward.fromJson(
    Map<String, Object?> json, {
    required FeatureCatalog features,
  }) {
    final feature = json['feature'] as String?;
    if (feature == null || feature.isEmpty) {
      throw ArgumentError('reward.feature is required');
    }
    final entry = features[feature];
    if (entry == null || !entry.usableAsReward()) {
      throw ArgumentError(
        'reward.feature "$feature" is not listed for the reward lane',
      );
    }
    final inhibitJson = json['inhibit'] as List? ?? const [];
    return ProtocolReward(
      feature: feature,
      output: json['output'] as String? ?? 'chime',
      policy: json['policy'] as String? ?? 'percentileUptrain',
      inhibit: [
        for (final c in inhibitJson)
          if (c is Map) parseInhibit(jsonObject(c)),
      ],
      electrodes: json['electrodes'] is List
          ? (json['electrodes'] as List).whereType<String>().toList()
          : null,
      locked: json['locked'] is List
          ? (json['locked'] as List).whereType<String>().toList()
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
    'feature': feature,
    'output': output,
    'policy': policy,
    'inhibit': [for (final c in inhibit) c.toJson()],
    if (electrodes != null) 'electrodes': electrodes,
    'locked': locked,
  };

  ProtocolReward copyWith({String? feature}) => ProtocolReward(
    feature: feature ?? this.feature,
    output: output,
    policy: policy,
    inhibit: inhibit,
    electrodes: electrodes,
    locked: locked,
  );
}

class ProtocolGuard {
  const ProtocolGuard({
    required this.feature,
    this.output = 'softBowl',
    this.policy = 'percentileWarn',
    this.muffleReward = false,
    this.defaultEnabled = true,
    this.electrodes,
    this.copy,
    this.locked = const [],
  });

  final String feature;
  final String output;
  final String policy;
  final bool muffleReward;
  final bool defaultEnabled;
  final List<String>? electrodes;
  final String? copy;
  final List<String> locked;

  factory ProtocolGuard.fromJson(
    Map<String, Object?> json, {
    required FeatureCatalog features,
  }) {
    final feature = json['feature'] as String?;
    if (feature == null || feature.isEmpty) {
      throw ArgumentError('guard.feature is required');
    }
    final entry = features[feature];
    if (entry == null || !entry.usableAsGuard()) {
      throw ArgumentError(
        'guard.feature "$feature" is not listed for the guard lane',
      );
    }
    return ProtocolGuard(
      feature: feature,
      output: json['output'] as String? ?? 'softBowl',
      policy: json['policy'] as String? ?? 'percentileWarn',
      muffleReward: json['muffleReward'] as bool? ?? false,
      defaultEnabled: json['defaultEnabled'] as bool? ?? true,
      electrodes: json['electrodes'] is List
          ? (json['electrodes'] as List).whereType<String>().toList()
          : null,
      copy: json['copy'] as String?,
      locked: json['locked'] is List
          ? (json['locked'] as List).whereType<String>().toList()
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
    'feature': feature,
    'output': output,
    'policy': policy,
    'muffleReward': muffleReward,
    'defaultEnabled': defaultEnabled,
    if (electrodes != null) 'electrodes': electrodes,
    if (copy != null) 'copy': copy,
    'locked': locked,
  };

  ProtocolGuard copyWith({String? feature}) => ProtocolGuard(
    feature: feature ?? this.feature,
    output: output,
    policy: policy,
    muffleReward: muffleReward,
    defaultEnabled: defaultEnabled,
    electrodes: electrodes,
    copy: copy,
    locked: locked,
  );
}

/// Wiring document for a catalog or user protocol. Identity is the string [id]
/// — there is no Dart enum.
class ProtocolDocument {
  const ProtocolDocument({
    required this.id,
    required this.origin,
    required this.schemaVersion,
    required this.copy,
    required this.colorValue,
    required this.calibration,
    this.calibrationSkippable = false,
    this.background = const ProtocolBackground(),
    this.reward,
    this.guard,
  });

  final String id;
  final String origin;
  final int schemaVersion;
  final ProtocolCopy copy;
  final int colorValue;
  Color get color => Color(colorValue);
  final String calibration;
  final bool calibrationSkippable;
  final ProtocolBackground background;
  final ProtocolReward? reward;
  final ProtocolGuard? guard;

  bool get hasReward => reward != null;
  bool get guardrailAllowed => guard != null;
  bool get isUserDocument =>
      origin == 'user' || userProtocolIdPattern.hasMatch(id);
  List<TargetCondition> get conditions => reward?.inhibit ?? const [];

  String get catchPhrase => copy.catchPhrase;
  String get title => copy.title;
  String get subtitle => copy.subtitle;
  String get guideText => copy.guideText;
  String get algorithmDescription => copy.algorithmDescription;
  String get expectedDelay => copy.expectedDelay;
  String? get metadataDescription => copy.metadataDescription;

  factory ProtocolDocument.fromJson(
    Map<String, Object?> json, {
    required String id,
    required FeatureCatalog features,
    String defaultOrigin = 'catalog',
  }) {
    final origin = json['origin'] as String? ?? defaultOrigin;
    final copyJson = json['copy'];
    final ProtocolCopy copy = copyJson is Map
        ? ProtocolCopy.fromJson(jsonObject(copyJson))
        : ProtocolCopy.fromJson(json);
    final parsedColor = json['color'] as int? ?? 0xFF000000;
    final rewardJson = json['reward'];
    final guardJson = json['guard'];
    return ProtocolDocument(
      id: json['id'] as String? ?? id,
      origin: origin,
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      copy: copy,
      colorValue: parsedColor,
      calibration: json['calibration'] as String? ?? '',
      calibrationSkippable: json['calibrationSkippable'] as bool? ?? false,
      background: ProtocolBackground.fromJson(json['background']),
      reward: rewardJson is Map
          ? ProtocolReward.fromJson(jsonObject(rewardJson), features: features)
          : null,
      guard: guardJson is Map
          ? ProtocolGuard.fromJson(jsonObject(guardJson), features: features)
          : null,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'origin': origin,
    'schemaVersion': schemaVersion,
    'copy': copy.toJson(),
    'color': colorValue,
    'calibration': calibration,
    'calibrationSkippable': calibrationSkippable,
    'background': background.toJson(),
    if (reward != null) 'reward': reward!.toJson(),
    if (guard != null) 'guard': guard!.toJson(),
  };

  ProtocolDocument copyWith({ProtocolGuard? guard, bool clearGuard = false}) =>
      ProtocolDocument(
        id: id,
        origin: origin,
        schemaVersion: schemaVersion,
        copy: copy,
        colorValue: colorValue,
        calibration: calibration,
        calibrationSkippable: calibrationSkippable,
        background: background,
        reward: reward,
        guard: clearGuard ? null : (guard ?? this.guard),
      );

  factory ProtocolDocument.placeholder({String id = ''}) => ProtocolDocument(
    id: id,
    origin: 'catalog',
    schemaVersion: 1,
    copy: ProtocolCopy.empty,
    colorValue: 0xFF1E88E5,
    calibration: '',
  );

  /// Snapshot with the session's chosen guard feature applied. A disabled
  /// guard (`none`) is omitted so the snapshot matches what actually ran.
  ProtocolDocument resolved({String? guardFeature}) {
    if (guard == null) return this;
    if (guardFeature == null || guardFeature == 'none') {
      return copyWith(clearGuard: true);
    }
    return copyWith(guard: guard!.copyWith(feature: guardFeature));
  }

  /// Whether some legal configuration of this document's lanes is available
  /// on [kind] given [available] feature infos.
  bool isListedOn({
    required DeviceKind kind,
    required List<FeatureInfo> available,
    required bool anyModelInstalled,
  }) {
    final byId = {for (final f in available) f.id: f};

    bool featureAvailable(String id) {
      final info = byId[id];
      return info != null && info.available;
    }

    bool laneOk(String id, {required bool rewardLane}) {
      if (!featureAvailable(id)) return false;
      if (id.startsWith('ai.') && !anyModelInstalled) return false;
      return true;
    }

    if (reward != null) {
      if (!laneOk(reward!.feature, rewardLane: true)) return false;
    }
    if (guard != null) {
      final locked = guard!.locked.contains('feature');
      if (locked) {
        if (!laneOk(guard!.feature, rewardLane: false)) return false;
      } else {
        // Catalog does not lock guard.feature: band.delta or ai.drowsiness.
        final options = <String>{guard!.feature, 'band.delta', 'ai.drowsiness'};
        if (!options.any((id) => laneOk(id, rewardLane: false))) {
          return false;
        }
      }
    }
    return true;
  }
}

bool deviceKindIsCrown(DeviceKind kind) => kind == DeviceKind.neurosity;
