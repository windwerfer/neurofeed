import 'dart:io';

import 'package:flutter/services.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:muse_ml/src/feedback/guardrail_mode.dart';
import 'package:muse_ml/src/reve/models.dart';
import 'package:muse_ml/src/rust/api/reve.dart' as frb;
import 'package:muse_ml/src/settings.dart';

/// Thrown when an imported/downloaded file is not the expected weights file.
class ModelChecksumException implements Exception {
  ModelChecksumException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when a direct download fails (network/HTTP).
class ModelDownloadException implements Exception {
  ModelDownloadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when the model files are not where the app expects them.
class ModelNotFoundException implements Exception {
  ModelNotFoundException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Result of an install: where the model lives, its kind and loaded
/// description.
class ModelInstallResult {
  const ModelInstallResult({
    required this.kind,
    required this.directory,
    required this.loadedDesc,
  });
  final ModelKind kind;
  final String directory;
  final String loadedDesc;
}

/// On-disk model management for the guardrail AI engines.
///
/// Spur A (CBraMod) lives in `<sessionFolder>/ai_models/cbramod_a_vig/` with a
/// bundled head pack copied from Flutter assets plus an optional
/// `pretrained_weights.pth` encoder (SHA-pinned, HF Apache-2.0 download).
/// REVE remains `config.json` + `model.safetensors` via user import.
/// Flip when native CBraMod encoder forward is linked in Rust.
/// Until then the Model Ready card stays false even with verified weights.
const bool kCbramodEncoderForwardReady = false;

class ModelCache {
  const ModelCache();

  /// The directory the app expects [kind]'s files in:
  /// `<sessionFolder>/ai_models/<kind.folder>` when the session folder is a
  /// real path, otherwise `<app documents>/ai_models/<kind.folder>` (a SAF
  /// `content://` folder cannot be opened by the Rust loader).
  static Future<Directory> modelDirectory(
    String? sessionFolder,
    ModelKind kind,
  ) async {
    final base =
        sessionFolder != null && !sessionFolder.startsWith('content://')
        ? sessionFolder
        : (await getApplicationDocumentsDirectory()).path;
    return Directory('$base/ai_models/${kind.folder}');
  }

  List<File> _requiredFiles(Directory dir, ModelKind kind) {
    switch (kind.layout) {
      case ModelLayout.cbramodPack:
        return [
          File('${dir.path}/heads/head_a_vig_linear.f32bin'),
          File('${dir.path}/pack_manifest.json'),
        ];
      case ModelLayout.rlxSafetensors:
        return [
          File('${dir.path}/model.safetensors'),
          File('${dir.path}/config.json'),
        ];
    }
  }

  Future<List<String>> _missing(Directory dir, ModelKind kind) async {
    final missing = <String>[];
    for (final f in _requiredFiles(dir, kind)) {
      if (!(await f.exists()) || await f.length() == 0) {
        missing.add(f.path.split(Platform.pathSeparator).last);
      }
    }
    return missing;
  }

  /// Pack/head files present (CBraMod) or REVE safetensors present.
  /// Does **not** call [ensureBundledPack] — copying the bundled head must not
  /// alone mark the model installed/Ready.
  Future<bool> isPackPresentOnDisk(String? sessionFolder, ModelKind kind) async {
    final dir = await modelDirectory(sessionFolder, kind);
    if (kind.layout == ModelLayout.rlxSafetensors) {
      await ensureReveExperimentalHeads(dir);
    }
    return (await _missing(dir, kind)).isEmpty;
  }

  Future<File> _encoderFile(Directory dir) async {
    final candidates = [
      File('${dir.path}/pretrained_weights.pth'),
      File('${dir.path}/encoder/pretrained_weights.pth'),
    ];
    for (final f in candidates) {
      if (await f.exists() && await f.length() > 0) return f;
    }
    return candidates.first;
  }

  /// Encoder weights present and SHA-verified (stamp or live hash).
  Future<bool> isEncoderVerifiedOnDisk(
    String? sessionFolder,
    ModelKind kind,
  ) async {
    if (kind.layout != ModelLayout.cbramodPack) {
      return isVerifiedOnDisk(sessionFolder, kind);
    }
    final dir = await modelDirectory(sessionFolder, kind);
    if (await isVerifiedOnDisk(sessionFolder, kind)) {
      final enc = await _encoderFile(dir);
      return enc.existsSync() && await enc.length() > 0;
    }
    final enc = await _encoderFile(dir);
    if (!(await enc.exists()) || await enc.length() == 0) return false;
    final hex = await sha256Of(enc.openRead());
    if (hex != kind.sha256) return false;
    await _stampVerified(dir, kind);
    return true;
  }

  /// Installed for badges: CBraMod needs head pack + verified encoder; REVE
  /// needs safetensors. Ready (scoring) is a stricter gate — see notifier.
  Future<bool> isInstalledOnDisk(String? sessionFolder, ModelKind kind) async {
    if (!(await isPackPresentOnDisk(sessionFolder, kind))) return false;
    if (kind.layout == ModelLayout.cbramodPack) {
      return isEncoderVerifiedOnDisk(sessionFolder, kind);
    }
    return true;
  }

  /// Human-readable reason CBraMod is not Ready, or null when Ready is allowed.
  Future<String?> cbramodNotReadyReason(
    String? sessionFolder,
    ModelKind kind,
  ) async {
    if (kind.layout != ModelLayout.cbramodPack) return null;
    // Ensure head pack is on disk for load attempts (explicit, not via installed).
    final dir = await modelDirectory(sessionFolder, kind);
    await ensureBundledPack(dir, kind);
    if (!(await isPackPresentOnDisk(sessionFolder, kind))) {
      return 'CBraMod head pack missing';
    }
    if (!(await isEncoderVerifiedOnDisk(sessionFolder, kind))) {
      return 'CBraMod encoder weights not verified — download or import '
          'pretrained_weights.pth (SHA-pinned Apache-2.0)';
    }
    if (!kCbramodEncoderForwardReady) {
      return 'CBraMod encoder forward not linked yet (encoder SHA + head OK) — '
          'not Ready until native forward exists';
    }
    return null;
  }

  /// Copy the bundled Spur A pack from Flutter assets into [dir] when missing.
  Future<void> ensureBundledPack(Directory dir, ModelKind kind) async {
    final root = kind.packAssetRoot;
    if (root == null) return;
    await dir.create(recursive: true);
    final heads = Directory('${dir.path}/heads');
    await heads.create(recursive: true);
    final encoder = Directory('${dir.path}/encoder');
    await encoder.create(recursive: true);
    const files = <String>[
      'pack_manifest.json',
      'app_integration.json',
      'ATTRIBUTION.md',
      'README.md',
      'heads/head_a_vig_linear.f32bin',
      'heads/head_a_vig_linear.pt',
      'heads/head_c_wake_light_linear.f32bin',
      'heads/head_c_wake_light_linear.pt',
      'encoder/EXPECTED.json',
    ];
    for (final rel in files) {
      final dest = File('${dir.path}/$rel');
      if (await dest.exists() && await dest.length() > 0) continue;
      try {
        final data = await rootBundle.load('$root/$rel');
        await dest.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      } on Exception {
        // Optional docs may be absent in slim asset lists; head is required.
      }
    }
  }

  /// Copy experimental REVE linear heads into `reve_base/heads/` so Rust can
  /// score `ai.a_vig_reve` / `ai.wake_light_reve` after a gated base import.
  Future<void> ensureReveExperimentalHeads(Directory dir) async {
    await Directory('${dir.path}/heads').create(recursive: true);
    const copies = <(String, String)>[
      (
        'assets/packs/reve-a-vig-subsample/heads/head_a_vig_reve_linear.f32bin',
        'heads/head_a_vig_reve_linear.f32bin',
      ),
      (
        'assets/packs/reve-a-vig-subsample/heads/head_a_vig_reve_linear.pt',
        'heads/head_a_vig_reve_linear.pt',
      ),
      (
        'assets/packs/reve-head-c-wake-light-subsample/heads/head_c_wake_light_reve_linear.f32bin',
        'heads/head_c_wake_light_reve_linear.f32bin',
      ),
      (
        'assets/packs/reve-head-c-wake-light-subsample/heads/head_c_wake_light_reve_linear.pt',
        'heads/head_c_wake_light_reve_linear.pt',
      ),
    ];
    for (final (asset, rel) in copies) {
      final dest = File('${dir.path}/$rel');
      if (await dest.exists() && await dest.length() > 0) continue;
      try {
        final data = await rootBundle.load(asset);
        await dest.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      } on Exception {
        // Experimental; absence leaves those feature IDs unscored.
      }
    }
  }

  /// SHA-256 of a stream, so a multi-hundred-MB file never lives in memory.
  Future<String> sha256Of(Stream<List<int>> bytes) async {
    return sha256.bind(bytes).first.then((d) => d.toString());
  }

  /// Import a user-picked weights file for [kind].
  /// REVE expects `.safetensors`; CBraMod expects `pretrained_weights.pth`.
  Future<ModelInstallResult> importModel(
    String? sessionFolder,
    ModelKind kind,
    Stream<List<int>> src,
  ) async {
    final dir = await modelDirectory(sessionFolder, kind);
    await dir.create(recursive: true);
    if (kind.layout == ModelLayout.cbramodPack) {
      await ensureBundledPack(dir, kind);
      return _importNamed(dir, kind, src, 'pretrained_weights.pth');
    }
    await ensureReveExperimentalHeads(dir);
    return _importNamed(dir, kind, src, 'model.safetensors');
  }

  Future<ModelInstallResult> _importNamed(
    Directory dir,
    ModelKind kind,
    Stream<List<int>> src,
    String filename,
  ) async {
    final part = File('${dir.path}/$filename.part');
    final sink = part.openWrite();
    final digester = _DigestSink();
    final hasher = sha256.startChunkedConversion(digester);
    try {
      await for (final chunk in src) {
        sink.add(chunk);
        hasher.add(chunk);
      }
    } finally {
      await sink.close();
      hasher.close();
    }
    _verifyHash(kind, digester.hex, part);
    return _installLoaded(dir, part, kind, filename);
  }

  /// Download [kind]'s primary weights from Hugging Face and install.
  Future<ModelInstallResult> downloadModel(
    String? sessionFolder,
    ModelKind kind, {
    void Function(int received, int total)? onProgress,
  }) async {
    final url = kind.downloadUrl;
    if (url == null) {
      throw ModelDownloadException(
        '${kind.label} cannot be downloaded — it is gated on Hugging Face. '
        'Use Import instead.',
      );
    }
    final dir = await modelDirectory(sessionFolder, kind);
    await dir.create(recursive: true);
    if (kind.layout == ModelLayout.cbramodPack) {
      await ensureBundledPack(dir, kind);
    }
    final filename = kind.layout == ModelLayout.cbramodPack
        ? 'pretrained_weights.pth'
        : 'model.safetensors';
    final part = File('${dir.path}/$filename.part');
    if (await part.exists()) {
      await part.delete();
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw ModelDownloadException(
          'Download failed (HTTP ${response.statusCode}). '
          'Check your connection and try again.',
        );
      }
      final total = response.contentLength < 0 ? 0 : response.contentLength;
      final sink = part.openWrite();
      final digester = _DigestSink();
      final hasher = sha256.startChunkedConversion(digester);
      var received = 0;
      var lastReported = -1;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          if (received - lastReported >= 256 * 1024) {
            lastReported = received;
            onProgress?.call(received, total);
          }
        }
      } finally {
        await sink.close();
        hasher.close();
      }
      onProgress?.call(received, total);
      _verifyHash(kind, digester.hex, part);
    } on HttpException catch (e) {
      if (await part.exists()) {
        await part.delete();
      }
      throw ModelDownloadException('Download failed: $e');
    } on SocketException catch (e) {
      if (await part.exists()) {
        await part.delete();
      }
      throw ModelDownloadException(
        'Network error — could not reach Hugging Face.\n\n$e',
      );
    } finally {
      client.close(force: true);
    }
    return _installLoaded(dir, part, kind, filename);
  }

  void _verifyHash(ModelKind kind, String hex, File part) {
    if (hex == kind.sha256) return;
    final _ = part.existsSync() ? part.deleteSync() : null;
    throw ModelChecksumException(
      'That file is not the ${kind.label} weights.\n\n'
      'Got      $hex\nExpected ${kind.sha256}\n\n'
      'Download the weights from the Hugging Face page (Open Hugging Face) '
      'and try again.',
    );
  }

  Future<ModelInstallResult> _installLoaded(
    Directory dir,
    File part,
    ModelKind kind,
    String filename,
  ) async {
    final dest = File('${dir.path}/$filename');
    if (await dest.exists()) {
      await dest.delete();
    }
    await part.rename(dest.path);
    await _ensureConfig(dir, kind);
    await _stampVerified(dir, kind);
    final loadedDesc = await frb.modelLoad(modelDir: dir.path, kind: kind.ffId);
    return ModelInstallResult(
      kind: kind,
      directory: dir.path,
      loadedDesc: loadedDesc,
    );
  }

  Future<void> _stampVerified(Directory dir, ModelKind kind) async {
    await File('${dir.path}/verified.json').writeAsString(
      '{"sha256":"${kind.sha256}"}',
      flush: true,
    );
  }

  Future<bool> isVerifiedOnDisk(
    String? sessionFolder,
    ModelKind kind,
  ) async {
    final dir = await modelDirectory(sessionFolder, kind);
    try {
      final contents = await File('${dir.path}/verified.json').readAsString();
      return contents.contains('"sha256":"${kind.sha256}"');
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _ensureConfig(Directory dir, ModelKind kind) async {
    final config = File('${dir.path}/config.json');
    if (await config.exists()) return;
    await config.writeAsString(
      await frb.modelConfigJson(kind: kind.ffId),
      flush: true,
    );
  }

  /// Load the model from disk. For Spur A, copies the bundled head pack first.
  Future<ModelInstallResult> install(
    String? sessionFolder,
    ModelKind kind,
  ) async {
    final dir = await modelDirectory(sessionFolder, kind);
    if (kind.layout == ModelLayout.cbramodPack) {
      await ensureBundledPack(dir, kind);
    }
    await _ensureConfig(dir, kind);
    final missing = await _missing(dir, kind);
    if (missing.isNotEmpty) {
      throw ModelNotFoundException(
        '${kind.label} model not found.\n'
        'Missing ${missing.join(' and ')} in:\n${dir.path}\n\n'
        'Use “Import” or “Download” to add the model file, or put the files '
        'there manually.',
      );
    }
    final loadedDesc = await frb.modelLoad(modelDir: dir.path, kind: kind.ffId);
    return ModelInstallResult(
      kind: kind,
      directory: dir.path,
      loadedDesc: loadedDesc,
    );
  }

  /// Drop the loaded model and delete its on-disk files.
  Future<void> clear(String? sessionFolder, ModelKind kind) async {
    final dir = await modelDirectory(sessionFolder, kind);
    await frb.modelUnload();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

/// The user-facing lifecycle of the guardrail AI engine.
sealed class ModelEngineState {
  const ModelEngineState();
}

/// Model files not (yet) found on disk.
class ModelEngineNotInstalled extends ModelEngineState {
  const ModelEngineNotInstalled();
}

/// Checking disk, downloading or loading into the Rust runtime.
class ModelEngineLoading extends ModelEngineState {
  const ModelEngineLoading();
}

/// Model verified, imported/downloaded and loaded; [description] comes from
/// the Rust loader.
class ModelEngineReady extends ModelEngineState {
  const ModelEngineReady({required this.kind, required this.description});
  final ModelKind kind;
  final String description;
}

/// Files may be present / loaded, but scoring Ready is false — [reason] is
/// user-facing (e.g. encoder forward pending).
class ModelEngineNotReady extends ModelEngineState {
  const ModelEngineNotReady({
    required this.kind,
    required this.reason,
    this.description,
  });
  final ModelKind kind;
  final String reason;
  final String? description;
}

/// Previous attempt failed; [message] is user-facing.
class ModelEngineError extends ModelEngineState {
  const ModelEngineError({required this.kind, required this.message});
  final ModelKind kind;
  final String message;
}

/// Collects the final digest from a chunked SHA-256 conversion.
class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}

  String get hex =>
      (_digest ?? (throw StateError('SHA-256 digest never produced')))
          .toString();
}

/// Drives [ModelEngineState] for the *selected* model kind. Spur A (CBraMod)
/// ships its head pack and downloads the encoder; REVE is user-import only.
class ModelEngineNotifier extends Notifier<ModelEngineState> {
  static const ModelCache _cache = ModelCache();

  /// The kind this notifier currently reports on. Null until [build] or an
  /// explicit [select]/[import]/[download] pins it to the settings value.
  ModelKind? _kind;

  String? get _sessionFolder => ref.read(settingsProvider).sessionFolder;

  ModelKind get _selectedKind {
    if (_kind != null) return _kind!;
    final settings = ref.read(settingsProvider);
    return modelKindFromFfId(settings.guardModel) ?? defaultModelKind;
  }

  @override
  ModelEngineState build() {
    // Probe disk state without blocking build: load a model that is already
    // installed; otherwise settle into the "not installed" state.
    Future.microtask(() async {
      if (state is ModelEngineReady || state is ModelEngineLoading) return;
      state = await _probe(_selectedKind);
    });
    return const ModelEngineNotInstalled();
  }

  Future<ModelEngineState> _probe(ModelKind kind) async {
    try {
      if (kind.layout == ModelLayout.cbramodPack) {
        final reason = await _cache.cbramodNotReadyReason(_sessionFolder, kind);
        // Always try to load head when pack can be ensured — description feeds UI.
        String? desc;
        try {
          final result = await _cache.install(_sessionFolder, kind);
          desc = result.loadedDesc;
        } on Exception catch (_) {
          // Head-only load may still fail if assets missing.
        }
        if (reason != null) {
          if (desc == null &&
              !(await _cache.isPackPresentOnDisk(_sessionFolder, kind))) {
            return const ModelEngineNotInstalled();
          }
          return ModelEngineNotReady(
            kind: kind,
            reason: reason,
            description: desc,
          );
        }
        return ModelEngineReady(kind: kind, description: desc ?? kind.label);
      }
      if (!await _cache.isInstalledOnDisk(_sessionFolder, kind)) {
        return const ModelEngineNotInstalled();
      }
      final result = await _cache.install(_sessionFolder, kind);
      return ModelEngineReady(kind: kind, description: result.loadedDesc);
    } on Exception catch (e) {
      return ModelEngineError(kind: kind, message: '$e');
    }
  }

  ModelEngineState _readyOrNot(ModelKind kind, String loadedDesc) {
    if (kind.layout == ModelLayout.cbramodPack && !kCbramodEncoderForwardReady) {
      return ModelEngineNotReady(
        kind: kind,
        reason:
            'CBraMod encoder forward not linked yet (encoder SHA + head OK) — '
            'not Ready until native forward exists',
        description: loadedDesc,
      );
    }
    return ModelEngineReady(kind: kind, description: loadedDesc);
  }

  /// Switch the selected model (persisted to settings) and probe it.
  Future<void> select(ModelKind kind) async {
    if (_kind == kind && state is ModelEngineReady) {
      await _recheckBadges();
      return;
    }
    _kind = kind;
    await ref.read(settingsProvider).setGuardModel(kind.ffId);
    state = await _probe(kind);
    await _recheckBadges();
  }

  /// Import a user-picked model file (verified against the model's SHA-256).
  Future<ModelEngineState> import(ModelKind kind, Stream<List<int>> src) async {
    _kind = kind;
    await ref.read(settingsProvider).setGuardModel(kind.ffId);
    state = const ModelEngineLoading();
    try {
      final result = await _cache.importModel(_sessionFolder, kind, src);
      state = _readyOrNot(kind, result.loadedDesc);
    } on ModelChecksumException catch (e) {
      state = ModelEngineError(kind: kind, message: e.message);
    } on Exception catch (e) {
      state = ModelEngineError(kind: kind, message: '$e');
    }
    await _recheckBadges();
    return state;
  }

  /// Download the model directly from Hugging Face (CBraMod encoder).
  Future<ModelEngineState> download(
    ModelKind kind, {
    void Function(int received, int total)? onProgress,
  }) async {
    _kind = kind;
    await ref.read(settingsProvider).setGuardModel(kind.ffId);
    state = const ModelEngineLoading();
    try {
      final result = await _cache.downloadModel(
        _sessionFolder,
        kind,
        onProgress: onProgress,
      );
      state = _readyOrNot(kind, result.loadedDesc);
    } on ModelChecksumException catch (e) {
      state = ModelEngineError(kind: kind, message: e.message);
    } on ModelDownloadException catch (e) {
      state = ModelEngineError(kind: kind, message: e.message);
    } on Exception catch (e) {
      state = ModelEngineError(kind: kind, message: '$e');
    }
    await _recheckBadges();
    return state;
  }

  /// Re-check the disk for the selected model's files.
  Future<ModelEngineState> recheck() async {
    state = const ModelEngineLoading();
    state = await _probe(_selectedKind);
    await _recheckBadges();
    return state;
  }

  /// Unload the selected model and delete its files.
  Future<ModelEngineState> clear() async {
    final kind = _selectedKind;
    state = const ModelEngineLoading();
    await _cache.clear(_sessionFolder, kind);
    state = const ModelEngineNotInstalled();
    await _recheckBadges();
    return state;
  }

  /// Invalidate the per-kind availability badges (after any install change).
  Future<void> _recheckBadges() async {
    for (final kind in ModelKind.values) {
      ref.invalidate(modelInstalledProvider(kind));
    }
  }
}

final modelEngineNotifierProvider =
    NotifierProvider<ModelEngineNotifier, ModelEngineState>(
      ModelEngineNotifier.new,
    );

/// Whether the selected model is loaded and usable by the sleep-guardrail
/// protocols.
final modelEngineAvailabilityProvider = Provider<bool>(
  (ref) => ref.watch(modelEngineNotifierProvider) is ModelEngineReady,
);

/// Where the app currently looks for the selected model's files (resolved per
/// the session-folder setting, so the hint stays correct when the user changes
/// save location).
final modelFolderProvider = FutureProvider<String>(
  (ref) async => (await ModelCache.modelDirectory(
    ref.watch(settingsProvider).sessionFolder,
    modelKindFromFfId(ref.watch(settingsProvider).guardModel) ??
        defaultModelKind,
  )).path,
);

/// Whether a given model's files are on disk (drives the "available" badges in
/// the selector). Invalidated by the notifier after install changes.
final modelInstalledProvider = FutureProvider.family<bool, ModelKind>((
  ref,
  kind,
) async {
  return ModelCache().isInstalledOnDisk(
    ref.watch(settingsProvider).sessionFolder,
    kind,
  );
});
