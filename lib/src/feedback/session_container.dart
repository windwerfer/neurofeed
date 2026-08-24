import 'dart:typed_data';

import 'package:muse_ml/src/rust/api/session_format.dart';

/// Self-contained v5 session file container.
///
/// Layout (68-byte fixed header + WebP thumbnail + zstd metadata + zstd computed + zstd raw):
///   [68-byte fixed header][WebP thumbnail][metadata JSON (zstd)][computed 1Hz (zstd)][raw (zstd)]
///
/// The byte layout lives in Rust (`rust/src/api/session_format.rs`); these
/// methods are thin delegates so the single format authority is Rust.
class SessionContainer {
  SessionContainer._();

  /// Assemble a v5 container.
  static Uint8List encodeV5({
    required Uint8List thumbnail,
    required Uint8List metadataJson,
    required List<ComputedFrame> computedFrames,
    required Uint8List rawBody,
  }) =>
      containerEncodeV5(
        thumbnail: thumbnail,
        metadataJson: metadataJson,
        computedFrames: computedFrames,
        rawBody: rawBody,
      );

  /// Parse v5 header (68 bytes).
  static V5Header parseHeader(Uint8List bytes) => v5ParseHeader(bytes: bytes);

  /// Parse v5 head (header + thumbnail + metadata).
  static V5ParsedHead parseHead(Uint8List bytes) => v5ParseHead(bytes: bytes);

  /// Extract computed section (decompressed 1Hz frames).
  static List<ComputedFrame> extractComputed(Uint8List bytes) =>
      v5ExtractComputed(bytes: bytes);

  /// Extract raw section (decompressed raw body).
  static Uint8List extractRaw(Uint8List bytes) => v5ExtractRaw(bytes: bytes);
}
