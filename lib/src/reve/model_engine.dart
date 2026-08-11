import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

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
/// Each model lives in `<sessionFolder>/ai_models/<model>/` as
/// `config.json` + `model.safetensors`. LUNA (un-gated) is downloaded
/// directly from Hugging Face and verified against the model's SHA-256; REVE
/// (gated) is imported from a user-picked file with the same verification. A
/// managed in-app download for REVE is deferred until hosting exists.
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

  List<File> _files(Directory dir) => [
    File('${dir.path}/model.safetensors'),
    File('${dir.path}/config.json'),
  ];

  Future<List<String>> _missing(Directory dir) async {
    final missing = <String>[];
    for (final f in _files(dir)) {
      if (!(await f.exists()) || await f.length() == 0) {
        missing.add(f.path.split(Platform.pathSeparator).last);
      }
    }
    return missing;
  }

  Future<bool> isInstalledOnDisk(String? sessionFolder, ModelKind kind) async {
    final dir = await modelDirectory(sessionFolder, kind);
    return (await _missing(dir)).isEmpty;
  }

  /// SHA-256 of a stream, so a multi-hundred-MB file never lives in memory.
  Future<String> sha256Of(Stream<List<int>> bytes) async {
    return sha256.bind(bytes).first.then((d) => d.toString());
  }

  /// Import a user-picked `.safetensors` file for [kind]. Throws
  /// [ModelChecksumException] when the hash does not match [ModelKind.sha256].
  /// Returns the loaded model description.
  Future<ModelInstallResult> importModel(
    String? sessionFolder,
    ModelKind kind,
    Stream<List<int>> src,
  ) async {
    final dir = await modelDirectory(sessionFolder, kind);
    await dir.create(recursive: true);

    // Hash and copy in a single pass over the stream: verify the file while
    // writing to a `.part` sibling, then rename atomically so a bad file is
    // never left in place and a partial copy never looks like a good model.
    final part = File('${dir.path}/model.safetensors.part');
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
    return _installLoaded(dir, part, kind);
  }

  /// Download [kind]'s weights directly from Hugging Face and install it.
  /// Throws [ModelChecksumException] on a hash mismatch and
  /// [ModelDownloadException] on a network error. [onProgress] is called with
  /// `(receivedBytes, totalBytes)` (throttled to roughly 256 KiB steps).
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
    final part = File('${dir.path}/model.safetensors.part');
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
    return _installLoaded(dir, part, kind);
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

  /// Move the verified part into place, write config.json, and load.
  Future<ModelInstallResult> _installLoaded(
    Directory dir,
    File part,
    ModelKind kind,
  ) async {
    final dest = File('${dir.path}/model.safetensors');
    if (await dest.exists()) {
      await dest.delete();
    }
    await part.rename(dest.path);
    await _ensureConfig(dir, kind);
    final loadedDesc = await frb.modelLoad(modelDir: dir.path, kind: kind.ffId);
    return ModelInstallResult(
      kind: kind,
      directory: dir.path,
      loadedDesc: loadedDesc,
    );
  }

  /// Write the app-generated `config.json` unless one already exists. The
  /// loader needs both files; the config describes the architecture and is
  /// regenerated from the model's public hyperparameters.
  Future<void> _ensureConfig(Directory dir, ModelKind kind) async {
    final config = File('${dir.path}/config.json');
    if (await config.exists()) return;
    await config.writeAsString(
      await frb.modelConfigJson(kind: kind.ffId),
      flush: true,
    );
  }

  /// Load the model from disk (used by "check for model" — the user may have
  /// dropped the files in manually). Auto-writes config.json when missing.
  Future<ModelInstallResult> install(
    String? sessionFolder,
    ModelKind kind,
  ) async {
    final dir = await modelDirectory(sessionFolder, kind);
    await _ensureConfig(dir, kind);
    final missing = await _missing(dir);
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

/// Drives [ModelEngineState] for the *selected* model kind. LUNA is downloaded
/// directly; REVE is only ever obtained via user import (the Hub repo is
/// gated).
class ModelEngineNotifier extends Notifier<ModelEngineState> {
  static const ModelCache _cache = ModelCache();

  /// The kind this notifier currently reports on. Null until [build] or an
  /// explicit [select]/[import]/[download] pins it to the settings value.
  ModelKind? _kind;

  String? get _sessionFolder => ref.read(settingsProvider).sessionFolder;

  ModelKind get _selectedKind =>
      _kind ?? modelKindFromSettings(ref.read(settingsProvider));

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
      if (!await _cache.isInstalledOnDisk(_sessionFolder, kind)) {
        return const ModelEngineNotInstalled();
      }
      final result = await _cache.install(_sessionFolder, kind);
      return ModelEngineReady(kind: kind, description: result.loadedDesc);
    } on Exception catch (e) {
      return ModelEngineError(kind: kind, message: '$e');
    }
  }

  /// Switch the selected model (persisted to settings) and probe it.
  Future<void> select(ModelKind kind) async {
    if (_kind == kind && state is ModelEngineReady) {
      await _recheckBadges();
      return;
    }
    _kind = kind;
    await ref.read(settingsProvider).setModelKindName(kind.name);
    state = await _probe(kind);
    await _recheckBadges();
  }

  /// Import a user-picked model file (verified against the model's SHA-256).
  Future<ModelEngineState> import(ModelKind kind, Stream<List<int>> src) async {
    _kind = kind;
    await ref.read(settingsProvider).setModelKindName(kind.name);
    state = const ModelEngineLoading();
    try {
      final result = await _cache.importModel(_sessionFolder, kind, src);
      state = ModelEngineReady(kind: kind, description: result.loadedDesc);
    } on ModelChecksumException catch (e) {
      state = ModelEngineError(kind: kind, message: e.message);
    } on Exception catch (e) {
      state = ModelEngineError(kind: kind, message: '$e');
    }
    await _recheckBadges();
    return state;
  }

  /// Download the model directly from Hugging Face (LUNA only).
  Future<ModelEngineState> download(
    ModelKind kind, {
    void Function(int received, int total)? onProgress,
  }) async {
    _kind = kind;
    await ref.read(settingsProvider).setModelKindName(kind.name);
    state = const ModelEngineLoading();
    try {
      final result = await _cache.downloadModel(
        _sessionFolder,
        kind,
        onProgress: onProgress,
      );
      state = ModelEngineReady(kind: kind, description: result.loadedDesc);
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

/// Whether the selected model is loaded and usable by the drowsiness
/// protocol.
final modelEngineAvailabilityProvider = Provider<bool>(
  (ref) => ref.watch(modelEngineNotifierProvider) is ModelEngineReady,
);

/// Where the app currently looks for the selected model's files (resolved per
/// the session-folder setting, so the hint stays correct when the user changes
/// save location).
final modelFolderProvider = FutureProvider<String>(
  (ref) async => (await ModelCache.modelDirectory(
    ref.watch(settingsProvider).sessionFolder,
    modelKindFromSettings(ref.watch(settingsProvider)),
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
