import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:muse_ml/src/audio/guardrail_sound.dart';
import 'package:muse_ml/src/audio/output_ids.dart';
import 'package:muse_ml/src/feedback/feature_catalog.dart';
import 'package:muse_ml/src/feedback/protocol.dart';

/// Calibration ids the builder may pick (from `assets/calibrations.json` v2).
const List<String> builderCalibrationIds = ['eyes-closed-01', 'eyes-open-01'];

const String userProtocolsSubdir = 'protocols';

class UserProtocolException implements Exception {
  const UserProtocolException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Suggest a slug from catch-phrase copy. Empty when nothing legal remains.
String suggestUserProtocolSlug(String catchPhrase) {
  var s = catchPhrase.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  s = s.replaceAll(RegExp(r'^-+|-+$'), '');
  if (s.length > 64) {
    s = s.substring(0, 64).replaceAll(RegExp(r'-+$'), '');
  }
  return s;
}

void validateUserProtocolId(String id) {
  if (!userProtocolIdPattern.hasMatch(id)) {
    throw const UserProtocolException(
      'Id must be user.<slug> with a 3–64 character slug of lowercase '
      'letters, digits, and hyphens.',
    );
  }
  if (catalogProtocolIds.contains(id)) {
    throw UserProtocolException(
      '"$id" is a catalog program id. Pick a different name.',
    );
  }
}

/// User protocol I/O under app-support `protocols/*.json`.
///
/// Not the history SAF tree. No remote fetch. No code execution from JSON.
class UserProtocolStore {
  UserProtocolStore({required this.directory, required this.features});

  final Directory directory;
  final FeatureCatalog features;

  static Future<Directory?> resolveDirectory() async {
    try {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}/$userProtocolsSubdir');
    } catch (_) {
      return null;
    }
  }

  static Future<UserProtocolStore> open(FeatureCatalog features) async {
    final dir = await resolveDirectory();
    if (dir == null) {
      throw const UserProtocolException(
        'Could not open the app-support protocols folder.',
      );
    }
    return UserProtocolStore(directory: dir, features: features);
  }

  File fileFor(String id) => File('${directory.path}/$id.json');

  /// Validate and write one document. [overwriteId] is the existing user id
  /// being edited (that file may be replaced). Catalog-id collisions, a
  /// non-matching `user.<slug>`, an existing other user file, and `usableFor`
  /// violations are rejected — nothing is written.
  Future<ProtocolDocument> save(
    ProtocolDocument draft, {
    String? overwriteId,
  }) async {
    final normalized = _normalize(draft);
    validateUserProtocolId(normalized.id);
    if (overwriteId != null && overwriteId != normalized.id) {
      validateUserProtocolId(overwriteId);
    }

    final json = normalized.toJson();
    json['origin'] = 'user';

    final ProtocolDocument parsed;
    try {
      parsed = ProtocolDocument.fromJson(
        jsonObject(json),
        id: normalized.id,
        features: features,
        defaultOrigin: 'user',
      );
    } catch (e) {
      final message = e is ArgumentError ? '${e.message}' : '$e';
      throw UserProtocolException(message);
    }
    if (parsed.origin != 'user') {
      throw const UserProtocolException(
        'User documents must have origin "user".',
      );
    }
    _validateOutputs(parsed);
    if (!builderCalibrationIds.contains(parsed.calibration)) {
      throw UserProtocolException(
        'Unknown calibration "${parsed.calibration}".',
      );
    }
    _validateCopy(parsed.copy);

    await directory.create(recursive: true);
    final dest = fileFor(parsed.id);
    final replacingSelf = overwriteId != null && overwriteId == parsed.id;
    if (await dest.exists() && !replacingSelf) {
      throw UserProtocolException(
        'A program named ${parsed.id} already exists.',
      );
    }

    final body = const JsonEncoder.withIndent('  ').convert(json);
    final tmp = File('${dest.path}.tmp');
    await tmp.writeAsString(body);
    await tmp.rename(dest.path);

    if (overwriteId != null && overwriteId != parsed.id) {
      final old = fileFor(overwriteId);
      if (await old.exists()) {
        await old.delete();
      }
    }
    return parsed;
  }

  Future<void> delete(String id) async {
    validateUserProtocolId(id);
    final file = fileFor(id);
    if (await file.exists()) {
      await file.delete();
    }
  }

  ProtocolDocument _normalize(ProtocolDocument draft) {
    final skippable = draft.reward == null && draft.guard == null;
    return ProtocolDocument(
      id: draft.id,
      origin: 'user',
      schemaVersion: 1,
      copy: draft.copy,
      colorValue: draft.colorValue,
      calibration: draft.calibration,
      calibrationSkippable: skippable,
      background: draft.background,
      reward: draft.reward == null
          ? null
          : ProtocolReward(
              feature: draft.reward!.feature,
              output: draft.reward!.output,
              policy: draft.reward!.policy,
              inhibit: draft.reward!.inhibit,
              electrodes: _namesOrOmit(draft.reward!.electrodes),
              locked: const [],
            ),
      guard: draft.guard == null
          ? null
          : ProtocolGuard(
              feature: draft.guard!.feature,
              output: draft.guard!.output,
              policy: draft.guard!.policy,
              muffleReward: draft.guard!.muffleReward,
              defaultEnabled: true,
              electrodes: _namesOrOmit(draft.guard!.electrodes),
              copy: _blankToNull(draft.guard!.copy),
              locked: const [],
            ),
    );
  }
}

void _validateCopy(ProtocolCopy copy) {
  void require(String label, String value) {
    if (value.trim().isEmpty) {
      throw UserProtocolException('$label is required.');
    }
  }

  require('Catch phrase', copy.catchPhrase);
  require('Title', copy.title);
  require('Subtitle', copy.subtitle);
  require('Guide text', copy.guideText);
  require('Algorithm description', copy.algorithmDescription);
  require('Metadata description', copy.metadataDescription ?? '');
}

void _validateOutputs(ProtocolDocument doc) {
  if (doc.reward != null) {
    final names = RewardOutputId.values.map((e) => e.name);
    if (!names.contains(doc.reward!.output)) {
      throw UserProtocolException(
        'Unknown reward.output "${doc.reward!.output}".',
      );
    }
  }
  if (doc.guard != null) {
    final names = GuardrailSound.values.map((e) => e.name);
    if (!names.contains(doc.guard!.output)) {
      throw UserProtocolException(
        'Unknown guard.output "${doc.guard!.output}".',
      );
    }
  }
  final kinds = BackgroundKind.values.map((e) => e.name);
  if (!kinds.contains(doc.background.kind)) {
    throw UserProtocolException(
      'Unknown background.kind "${doc.background.kind}".',
    );
  }
}

List<String>? _namesOrOmit(List<String>? names) {
  if (names == null) return null;
  final cleaned = [
    for (final n in names)
      if (n.trim().isNotEmpty) n.trim(),
  ];
  if (cleaned.isEmpty) return null;
  return cleaned;
}

String? _blankToNull(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return value;
}
