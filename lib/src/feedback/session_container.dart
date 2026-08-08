import 'dart:typed_data';

import 'package:muse_ml/src/rust/api/session_format.dart';

/// Self-contained session file container.
///
/// Layout (PNG-first so file managers on Linux/macOS can render a thumbnail
/// from the leading PNG and ignore the trailing data):
///
///   [ PNG bytes ][ jsonLen u32 BE ][ json bytes ][ bodyLen u32 BE ][ frames ]
///
/// The `json` is the UTF-8 metadata. The `body` is the raw `.muse` frame
/// stream (parsed by [SessionReader]). Nothing is encrypted; the format
/// simply lets a session live as one `.muse.feedback` file.
///
/// The byte layout lives in Rust (`rust/src/api/session_format.rs`); these
/// methods are thin delegates so the single format authority is Rust.
class SessionContainer {
  SessionContainer._();

  /// Max bytes read from the file when we only need the head (PNG + json).
  /// Cover a thumbnail plus metadata without pulling the large frame body.
  static int get headReadLimit => containerHeadReadLimit().toInt();

  /// Assemble a container: PNG first, then json metadata, then the frame body.
  static Uint8List encode({
    required Uint8List pngBytes,
    required Uint8List jsonBytes,
    required Uint8List bodyBytes,
  }) =>
      containerEncodeBytes(
        png: pngBytes,
        json: jsonBytes,
        body: bodyBytes,
      );

  /// Parse the head of a container (PNG + json). `bodyLen` is resolved only
  /// when the full body is present in [bytes]. A leading PNG is optional; if
  /// [bytes] does not start with a PNG signature the json starts at offset 0.
  static ContainerHead parseHead(Uint8List bytes) =>
      containerParseHeadBytes(bytes: bytes);

  /// Extract the full frame body from a complete container [bytes].
  static Uint8List? extractBody(Uint8List bytes) =>
      containerExtractBodyBytes(bytes: bytes);
}