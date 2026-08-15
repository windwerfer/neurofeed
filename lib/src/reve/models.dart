import 'package:muse_ml/src/settings.dart';

/// The selectable EEG foundation models behind the sleep guardrail.
///
/// Two engines, one abstraction: LUNA (`PulpBio/LUNA`, Apache-2.0, un-gated —
/// the app downloads it directly) and REVE (`brain-bzh/reve-base`, gated by a
/// responsible-use agreement — the user imports the weights file). The Rust
/// side picks the engine from [ffId]; the guardrail math consumes the embedding
/// either way, so swapping is just a setting change.
enum ModelKind {
  /// LUNA Base — 6.7M params, fast and light.
  lunaBase(
    ffId: 'luna_base',
    folder: 'luna_base',
    label: 'LUNA Base',
    sizeMb: 27,
    sha256: '482839ad9152b6948ff166d2a1638637c54b4d91f1cefadbce6312831ba9b11d',
    hfPageUrl: 'https://huggingface.co/PulpBio/LUNA',
    downloadUrl:
        'https://huggingface.co/PulpBio/LUNA/resolve/main/LUNA_base.safetensors',
    shortDescription:
        'Lightweight sleep foundation model (7M parameters). Fast and '
        'low-memory — a good default for older devices.',
    getGuide:
        'Downloaded automatically into the app — no account or license '
        'needed (Apache-2.0).',
  ),

  /// LUNA Large — 41M params. The default guardrail model.
  lunaLarge(
    ffId: 'luna_large',
    folder: 'luna_large',
    label: 'LUNA Large',
    sizeMb: 163,
    sha256: '03e0321a1e1a30dc074f7bfe512a901138200494f7694f31ab633e42b105c0e4',
    hfPageUrl: 'https://huggingface.co/PulpBio/LUNA',
    downloadUrl:
        'https://huggingface.co/PulpBio/LUNA/resolve/main/LUNA_large.safetensors',
    shortDescription:
        'Higher-capacity sleep foundation model (41M parameters). Better '
        'embeddings at the cost of more memory and slower inference.',
    getGuide:
        'Downloaded automatically into the app — no account or license '
        'needed (Apache-2.0).',
  ),

  /// REVE Base — drowsiness/artifact specialist, gated on Hugging Face.
  reveBase(
    ffId: 'reve_base',
    folder: 'reve_base',
    label: 'REVE Base',
    sizeMb: 280,
    sha256: '8ecc650619598748286c2457f81f5c6bd12e8bb59db44f7b02af1955c44de8fe',
    hfPageUrl: 'https://huggingface.co/brain-bzh/reve-base/tree/main',
    downloadUrl: null,
    shortDescription:
        'Purpose-trained drowsiness/artifact classifier (67M parameters). '
        'Specialised for exactly the axes the guardrail tracks.',
    getGuide:
        'REVE is gated: Open Hugging Face, log in, accept the '
        'responsible-use agreement, download `model.safetensors` (~280 MB), '
        'then come back and use Import.',
  );

  const ModelKind({
    required this.ffId,
    required this.folder,
    required this.label,
    required this.sizeMb,
    required this.sha256,
    required this.hfPageUrl,
    required this.downloadUrl,
    required this.shortDescription,
    required this.getGuide,
  });

  /// Identifier passed to the Rust loader (`model_load`).
  final String ffId;

  /// Subdirectory under `<…>/ai_models` holding this model's files.
  final String folder;

  /// Human-readable model name.
  final String label;

  /// Approximate download size, for the "(27 MB)" dropdown labels.
  final int sizeMb;

  /// SHA-256 of the weights file; the app verifies downloads and imports
  /// against this before loading.
  final String sha256;

  /// Model page on Hugging Face (Open Hugging Face button).
  final String hfPageUrl;

  /// Direct download URL, or null when the model is gated and must be
  /// imported manually (REVE).
  final String? downloadUrl;

  /// One-line description shown under the dropdown.
  final String shortDescription;

  /// Short "how to get this model" text shown with the buttons.
  final String getGuide;

  String get folderLabel => '$label ($sizeMb MB)';

  /// Folder used in session files / labels when a REVE-style name is needed.
  String get engineName => label;
}

/// Default guardrail model — LUNA Large (best quality/effort balance).
const ModelKind defaultModelKind = ModelKind.lunaLarge;

/// The model currently selected in [Settings].
ModelKind modelKindFromSettings(Settings settings) {
  final name = settings.modelKindName;
  for (final kind in ModelKind.values) {
    if (kind.name == name) return kind;
  }
  return defaultModelKind;
}
