/// The selectable EEG foundation models behind the sleep guardrail.
///
/// Spur A (**CBraMod** + A-vig head, Apache-2.0 encoder) is the primary
/// `ai.drowsiness` path. **REVE** remains an optional gated import. LUNA has
/// been removed from the ship path.
enum ModelKind {
  /// CBraMod A-vig (Spur A) — frozen encoder + full-corpus HeadALinear.
  cbramodAVig(
    ffId: 'cbramod_a_vig',
    folder: 'cbramod_a_vig',
    label: 'CBraMod A-vig',
    sizeMb: 20,
    sha256: '0792cb808c14e6b7a2bb2ce1dff379bc47bc54c49a779825bdfeb33bf8157178',
    hfPageUrl: 'https://huggingface.co/weighting666/CBraMod',
    downloadUrl:
        'https://huggingface.co/weighting666/CBraMod/resolve/main/pretrained_weights.pth',
    shortDescription:
        'Open Spur A vigilance head on frozen CBraMod (Apache-2.0, Candle CPU). '
        '2 s Muse windows; live FeatureDto is P(hypnagogic). Head pack ships with the app; '
        'download the ~20 MB encoder weights once to go Ready.',
    getGuide:
        'Head pack is bundled. Download the CBraMod encoder '
        '(`pretrained_weights.pth`) into the model folder — Apache-2.0, no gate.',
    layout: ModelLayout.cbramodPack,
    packAssetRoot: 'assets/packs/cbramod-a-vig-full',
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
        'Optional gated path — specialised for the axes the guardrail tracks.',
    getGuide:
        'REVE is gated: Open Hugging Face, log in, accept the '
        'responsible-use agreement, download `model.safetensors` (~280 MB), '
        'then come back and use Import.',
    layout: ModelLayout.rlxSafetensors,
    packAssetRoot: null,
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
    required this.layout,
    required this.packAssetRoot,
  });

  /// Identifier passed to the Rust loader (`model_load`).
  final String ffId;

  /// Subdirectory under `<…>/ai_models` holding this model's files.
  final String folder;

  /// Human-readable model name.
  final String label;

  /// Approximate download size, for the "(20 MB)" dropdown labels.
  final int sizeMb;

  /// SHA-256 of the primary weights file (encoder `.pth` for CBraMod,
  /// `model.safetensors` for REVE).
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

  /// On-disk layout expected by [ModelCache].
  final ModelLayout layout;

  /// Flutter asset root for a bundled pack, if any.
  final String? packAssetRoot;

  /// App-written `config.json` body. Must stay aligned with Rust
  /// `generated_config_json` for the same kind. Written from Dart so Download
  /// does not need FRB for a static string (avoids half-install on stale native).
  String get generatedConfigJson {
    switch (this) {
      case ModelKind.cbramodAVig:
        return '''
{
  "model_type": "cbramod_a_vig",
  "pack_id": "cbramod-a-vig-full",
  "encoder_family": "CBraMod",
  "encoder_sha256": "$sha256",
  "head_arch": "HeadALinear",
  "in_dim": 200,
  "n_classes": 2,
  "labels": ["drowsy", "hypnagogic"],
  "decode": "argmax",
  "feature_dto_value": "P(class1)=P(hypnagogic)",
  "window_sec": 2.0,
  "input_sr_hz": 256.0,
  "n_times": 512,
  "native_sr_hz": 200.0,
  "patch_samples": 200,
  "pool": "mean",
  "muse_channels": ["AF7", "AF8", "TP9", "TP10"]
}''';
      case ModelKind.reveBase:
        return '''
{
  "architectures": [
    "Reve"
  ],
  "auto_map": {
    "AutoConfig": "configuration_reve.ReveConfig",
    "AutoModel": "modeling_reve.Reve"
  },
  "depth": 22,
  "dtype": "float32",
  "embed_dim": 512,
  "freqs": 4,
  "head_dim": 64,
  "heads": 8,
  "mlp_dim_ratio": 2.66,
  "model_type": "reve",
  "noise_ratio": 0.0025,
  "patch_overlap": 20,
  "patch_size": 200,
  "transformers_version": "4.56.2",
  "use_geglu": true
}''';
    }
  }

  String get folderLabel => '$label ($sizeMb MB)';

  /// Folder used in session files / labels when a REVE-style name is needed.
  String get engineName => label;
}

/// How weights are laid out under `ai_models/<folder>/`.
enum ModelLayout {
  /// Spur A: head pack (+ optional `pretrained_weights.pth` encoder).
  cbramodPack,

  /// REVE/RLX: `config.json` + `model.safetensors`.
  rlxSafetensors,
}

/// Default guardrail model — Spur A CBraMod A-vig.
const ModelKind defaultModelKind = ModelKind.cbramodAVig;
