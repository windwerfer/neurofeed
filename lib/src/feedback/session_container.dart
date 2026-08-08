import 'dart:typed_data';

import 'package:flutter/foundation.dart';

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
class SessionContainer {
  SessionContainer._();

  /// Max bytes read from the file when we only need the head (PNG + json).
  /// Cover a thumbnail plus metadata without pulling the large frame body.
  static const int headReadLimit = 262144;

  static Uint8List _u32(int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.big);
    return b.buffer.asUint8List();
  }

  static int _readU32(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes, offset, offset + 4).getUint32(0, Endian.big);

  /// Assemble a container: PNG first, then json metadata, then the frame body.
  static Uint8List encode({
    required Uint8List pngBytes,
    required Uint8List jsonBytes,
    required Uint8List bodyBytes,
  }) {
    final out = BytesBuilder(copy: false);
    out.add(pngBytes);
    out.add(_u32(jsonBytes.length));
    out.add(jsonBytes);
    out.add(_u32(bodyBytes.length));
    out.add(bodyBytes);
    return out.toBytes();
  }

  /// Length in bytes of the PNG portion at the front of [bytes], or null if
  /// the buffer does not contain a complete valid PNG.
  static int? _localImageLength(Uint8List bytes) {
    const sig = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length < 8) return null;
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != sig[i]) return null;
    }
    var offset = 8;
    while (offset + 8 <= bytes.length) {
      final length = ByteData.sublistView(bytes, offset, offset + 8)
          .getUint32(0, Endian.big);
      final type = bytes.sublist(offset + 4, offset + 8);
      // PNG is little-endian-free; type bytes are plain ASCII.
      final end = offset + 12 + length;
      if (end > bytes.length) return null;
      if (type[0] == 0x49 && type[1] == 0x45 && type[2] == 0x4E &&
          type[3] == 0x44) {
        return end;
      }
      offset = end;
    }
    return null;
  }

/// Parse the head of a container (PNG + json). `bodyLen` is resolved only
  /// when the full body is present in [bytes]. A leading PNG is optional; if
  /// [bytes] does not start with a PNG signature the json starts at offset 0.
  static ({Uint8List pngBytes, Uint8List jsonBytes, int? bodyLen}) parseHead(
    Uint8List bytes,
  ) {
    var pngEnd = _localImageLength(bytes);
    pngEnd ??= 0;
    if (bytes.length < pngEnd + 4) {
      throw const FormatException('Missing session json length');
    }
    final jsonLen = _readU32(bytes, pngEnd);
    final jsonStart = pngEnd + 4;
    if (bytes.length < jsonStart + jsonLen) {
      throw const FormatException('Missing session json');
    }
    final jsonBytes = Uint8List.sublistView(bytes, jsonStart, jsonStart + jsonLen);
    int? bodyLen;
    final bodyStart = jsonStart + jsonLen;
    if (bytes.length >= bodyStart + 4) {
      bodyLen = _readU32(bytes, bodyStart);
    }
    return (
      pngBytes: Uint8List.sublistView(bytes, 0, pngEnd),
      jsonBytes: jsonBytes,
      bodyLen: bodyLen,
    );
  }

  /// Extract the full frame body from a complete container [bytes].
  static Uint8List? extractBody(Uint8List bytes) {
    // A whole-file read; parse the head then return the trailing body.
    final head = parseHead(bytes);
    final bodyLen = head.bodyLen;
    if (bodyLen == null) {
      debugPrint('[container] extractBody: bodyLen null, '
          'total=${bytes.length}, jsonLen=${head.jsonBytes.length}, '
          'pngLen=${head.pngBytes.length}');
      return null;
    }
    final start = bytes.length - bodyLen;
    if (start < 0) {
      debugPrint('[container] extractBody: start=$start < 0, '
          'total=${bytes.length}, bodyLen=$bodyLen');
      return null;
    }
    debugPrint('[container] extractBody: total=${bytes.length} '
        'bodyLen=$bodyLen start=$start pngLen=${head.pngBytes.length} '
        'jsonLen=${head.jsonBytes.length}');
    return Uint8List.sublistView(bytes, start, bytes.length);
  }
}