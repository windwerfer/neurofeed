import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:muse_ml/src/charts/band_cache.dart';
import 'package:muse_ml/src/charts/session_reader.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_chart_data.dart';
import 'package:muse_ml/src/feedback/session_pdf_export.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/rust/api/edf_export.dart';

/// What an export produces.
enum ExportKind { pdf, pngThumbnail, pngAll, csv, edf }

/// A non-fatal problem during an export (e.g. a session without raw EEG).
class ExportWarning {
  const ExportWarning(this.sessionId, this.message);

  final String sessionId;
  final String message;

  @override
  String toString() => message;
}

/// Outcome of an export run: files written and warnings collected.
class SessionExportResult {
  const SessionExportResult({
    required this.fileCount,
    required this.warnings,
    required this.location,
  });

  final int fileCount;
  final List<ExportWarning> warnings;
  final String location;
}

/// One value line of an exported chart. Samples are evenly spaced on the
/// x-axis (`x = index * xStepSeconds`, plotted in minutes).
class ExportChartLine {
  const ExportChartLine(this.label, this.color, this.values, {this.threshold});

  final String label;
  final Color color;
  final List<double> values;

  /// Optional horizontal dashed reference line (e.g. the guardrail threshold).
  final double? threshold;
}

/// A chart to render for export: title + lines + axis configuration.
class ExportChart {
  const ExportChart({
    required this.title,
    this.subtitle,
    required this.lines,
    this.xStepSeconds = 1.0,
    this.yMin,
    this.yMax,
  });

  final String title;
  final String? subtitle;
  final List<ExportChartLine> lines;
  final double xStepSeconds;

  /// Fixed y-axis range; null = auto-scale to the data.
  final double? yMin;
  final double? yMax;

  /// Copy with a resolved y-axis range when auto-scaling was requested.
  /// Shared by the PNG and PDF painters so both render identically.
  ExportChart resolveScale() {
    if (yMin != null && yMax != null) {
      return this;
    }
    final allValues = [
      for (final l in lines) ...l.values,
      for (final l in lines)
        if (l.threshold != null) l.threshold!,
    ];
    var lo = allValues.isEmpty ? 0.0 : allValues.reduce(mathMin);
    var hi = allValues.isEmpty ? 1.0 : allValues.reduce(mathMax);
    if (hi <= lo) {
      hi = lo + 1;
    }
    final pad = (hi - lo) * 0.08;
    lo -= pad;
    hi += pad;
    return ExportChart(
      title: title,
      subtitle: subtitle,
      lines: lines,
      xStepSeconds: xStepSeconds,
      yMin: yMin ?? lo,
      yMax: yMax ?? hi,
    );
  }
}

/// One chart PNG rendered for the "PNG (all)" export.
class ExportedImage {
  const ExportedImage(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// Exports finished sessions from history into `<root>/export/`.
///
/// The target storage is resolved by [resolveExportStorage] before the
/// exporter is built: the history folder itself, or a freshly picked SAF
/// folder on Android when history is not SAF-backed.
/// Mind Monitor CSV band column names (capitalized, per-channel).
const List<String> _mindMonitorBands = [
  'Delta',
  'Theta',
  'Alpha',
  'Beta',
  'Gamma',
];

class SessionExporter {
  SessionExporter(this._store, this._storage);

  final SessionStore _store;
  final SessionStorage _storage;

  static const exportDirName = 'export';

  Future<SessionExportResult> exportSessions({
    required List<SessionSummary> sessions,
    required ExportKind kind,
  }) async {
    final warnings = <ExportWarning>[];
    var files = 0;
    for (final s in sessions) {
      switch (kind) {
        case ExportKind.csv:
          files += await _exportCsv(s, warnings);
        case ExportKind.edf:
          files += await _exportEdf(s, warnings);
        case ExportKind.pngThumbnail:
          files += await _exportPngThumbnail(s, warnings);
        case ExportKind.pngAll:
          files += await _exportPngAll(s, warnings);
        case ExportKind.pdf:
          files += await _exportPdf(s, warnings);
      }
    }
    return SessionExportResult(
      fileCount: files,
      warnings: warnings,
      location: '${_storage.displayName}/$exportDirName',
    );
  }

  // ── CSV (Mind Monitor format, 1 Hz, absolute band powers) ─────────────

  Future<int> _exportCsv(SessionSummary s, List<ExportWarning> warnings) async {
    final data = await _readBody(s, warnings);
    if (data == null) {
      return 0;
    }
    final meta = s.metadata;

    final bandsPerSec = <int, Map<int, BandsRecord>>{};
    for (final b in data.bands) {
      bandsPerSec.putIfAbsent((b.timestamp / 1000).floor(), () => {})[b
          .electrode] = b;
    }
    final eegLastPerSec = <int, Map<int, double>>{};
    for (final e in data.eeg) {
      final sec = (e.timestamp / 1000).floor();
      for (var i = 0; i < e.samples.length; i++) {
        eegLastPerSec.putIfAbsent(sec, () => {})[e.electrode] = e.samples[i];
      }
    }
    if (bandsPerSec.isEmpty && eegLastPerSec.isEmpty) {
      warnings.add(ExportWarning(s.id, 'no band or raw data in file'));
      return 0;
    }

    // Mind Monitor column order: Delta, Theta, Alpha, Beta, Gamma, RAW per
    // channel. Only channels actually present in the file get columns.
    final channels = meta.recordedChannels.isEmpty
        ? const ['TP9', 'AF7', 'AF8', 'TP10']
        : meta.recordedChannels;
    final withBands = [
      for (var e = 0; e < channels.length; e++)
        if (bandsPerSec.values.any((m) => m.containsKey(e))) e,
    ];
    final withEeg = [
      for (var e = 0; e < channels.length; e++)
        if (eegLastPerSec.values.any((m) => m.containsKey(e))) e,
    ];
    if (withEeg.isEmpty) {
      warnings.add(
        ExportWarning(s.id, 'no raw EEG in file — CSV carries bands only'),
      );
    }
    if (withBands.isEmpty) {
      warnings.add(
        ExportWarning(s.id, 'no band data in file — CSV carries raw only'),
      );
    }

    final buf = StringBuffer();
    buf
      ..write('TimeStamp')
      ..writeAll([
        for (final e in withBands)
          for (final b in _mindMonitorBands) ',${b}_${channels[e]}',
      ])
      ..writeAll([for (final e in withEeg) ',RAW_${channels[e]}'])
      ..write('\n');

    var maxSec = meta.elapsedSeconds - 1;
    for (final sec in bandsPerSec.keys) {
      if (sec > maxSec) maxSec = sec;
    }
    for (final sec in eegLastPerSec.keys) {
      if (sec > maxSec) maxSec = sec;
    }
    final anchor = meta.savedAt.subtract(Duration(seconds: meta.elapsedSeconds));
    for (var sec = 0; sec <= maxSec; sec++) {
      final ts = anchor.add(Duration(seconds: sec));
      buf.write(
        '${ts.year.toString().padLeft(4, '0')}-'
        '${ts.month.toString().padLeft(2, '0')}-'
        '${ts.day.toString().padLeft(2, '0')} '
        '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}:'
        '${ts.second.toString().padLeft(2, '0')}.'
        '${ts.millisecond.toString().padLeft(3, '0')}',
      );
      final bands = bandsPerSec[sec];
      final eegLast = eegLastPerSec[sec];
      for (final e in withBands) {
        final b = bands?[e];
        if (b == null) {
          buf.write(',');
        } else {
          buf
            ..write(',')
            ..write(_num(b.delta))
            ..write(',')
            ..write(_num(b.theta))
            ..write(',')
            ..write(_num(b.alpha))
            ..write(',')
            ..write(_num(b.beta))
            ..write(',')
            ..write(_num(b.gamma));
        }
      }
      for (final e in withEeg) {
        final v = eegLast?[e];
        buf.write(',');
        if (v != null) {
          buf.write(_num(v));
        }
      }
      buf.write('\n');
    }

    await _storage.writeFileAtomic(
      '${_stem(meta, s.id)}.csv',
      Uint8List.fromList(buf.toString().codeUnits),
      dir: exportDirName,
    );
    return 1;
  }

  // ── EDF+ (raw EEG, via the edf_export FFI) ─────────────────────────────

  Future<int> _exportEdf(SessionSummary s, List<ExportWarning> warnings) async {
    final body = await _store.readMuse(s.id);
    if (body == null) {
      warnings.add(ExportWarning(s.id, 'could not read session file'));
      return 0;
    }
    final meta = s.metadata;
    final labels = List<String>.filled(8, '');
    for (var e = 0; e < meta.recordedChannels.length && e < labels.length; e++) {
      labels[e] = meta.recordedChannels[e];
    }
    final cal = meta.calibration;
    final annotations = <EdfExportAnnotation>[
      if (cal != null && cal.calibrationStartSecs != null)
        const EdfExportAnnotation(onsetSeconds: 0, text: 'Calibration start'),
      if (cal != null &&
          cal.calibrationStartSecs != null &&
          cal.calibrationEndSecs != null)
        EdfExportAnnotation(
          onsetSeconds: cal.calibrationEndSecs! - cal.calibrationStartSecs!,
          text: 'Calibration end',
        ),
      if (cal != null &&
          cal.calibrationStartSecs != null &&
          cal.trainingStartSecs != null)
        EdfExportAnnotation(
          onsetSeconds: cal.trainingStartSecs! - cal.calibrationStartSecs!,
          text: 'Training start',
        ),
      for (final g in meta.gestures)
        EdfExportAnnotation(
          onsetSeconds: g.offsetSeconds.toDouble(),
          text: switch (g.type) {
            GestureType.doubleBlink => 'Double blink',
            GestureType.doubleClench => 'Double clench',
            GestureType.eyeUp => 'Eye up',
            GestureType.eyeDown => 'Eye down',
          },
        ),
    ]..sort((a, b) => a.onsetSeconds.compareTo(b.onsetSeconds));

    final Uint8List edf;
    try {
      edf = encodeEdfExport(
        body: body,
        channelLabels: labels,
        params: EdfExportParams(
          patientId: 'Muse ML',
          recordingId:
              '${meta.protocol.name} ${meta.savedAt.toIso8601String()}',
          year: meta.savedAt.year,
          month: meta.savedAt.month,
          day: meta.savedAt.day,
          hour: meta.savedAt.hour,
          minute: meta.savedAt.minute,
          second: meta.savedAt.second,
          annotations: annotations,
        ),
      );
    } catch (e) {
      warnings.add(ExportWarning(s.id, 'EDF export failed: $e'));
      return 0;
    }
    await _storage.writeFileAtomic(
      '${_stem(meta, s.id)}.edf',
      edf,
      dir: exportDirName,
    );
    return 1;
  }

  // ── PNG thumbnail (flat export folder) ─────────────────────────────────

  Future<int> _exportPngThumbnail(
    SessionSummary s,
    List<ExportWarning> warnings,
  ) async {
    final png = await _store.readPng(s.id);
    if (png == null || png.isEmpty) {
      warnings.add(ExportWarning(s.id, 'no thumbnail in session file'));
      return 0;
    }
    await _storage.writeFileAtomic(
      '${_stem(s.metadata, s.id)}_thumbnail.png',
      Uint8List.fromList(png),
      dir: exportDirName,
    );
    return 1;
  }

  // ── PNG all (thumbnail + every detail chart, per-session subfolder) ────

  Future<int> _exportPngAll(
    SessionSummary s,
    List<ExportWarning> warnings,
  ) async {
    final data = await _readBody(s, warnings);
    if (data == null) {
      return 0;
    }
    final images = <ExportedImage>[];

    final thumbnail = await _store.readPng(s.id);
    if (thumbnail == null || thumbnail.isEmpty) {
      warnings.add(ExportWarning(s.id, 'no thumbnail in session file'));
    } else {
      images.add(ExportedImage('thumbnail.png', Uint8List.fromList(thumbnail)));
    }

    final meta = s.metadata;
    final protocol = ProtocolInfo.forType(meta.protocol);
    final prepared = prepareChartData(
      data,
      trainingStartOffset: meta.calibration?.trainingStartOffsetSecs,
      metric: protocol.rewardMetric,
      conditions: protocol.conditions,
    );
    final charts = chartsFor(prepared, meta);

    for (final chart in charts) {
      final bytes = await rasterizeChart(chart);
      images.add(
        ExportedImage(
          '${chart.title.toLowerCase().replaceAll(' ', '_')}.png',
          bytes,
        ),
      );
    }

    final folder = _stem(meta, s.id);
    for (final img in images) {
      await _storage.writeFileAtomic(
        img.name,
        img.bytes,
        dir: '$exportDirName/$folder',
      );
    }
    return images.length;
  }

  // ── PDF (implemented in session_pdf_export.dart) ───────────────────────

  Future<int> _exportPdf(SessionSummary s, List<ExportWarning> warnings) async {
    final bytes = await buildPdfPage(s, _store);
    if (bytes == null) {
      warnings.add(ExportWarning(s.id, 'could not read session file'));
      return 0;
    }
    await _storage.writeFileAtomic(
      '${_stem(s.metadata, s.id)}.pdf',
      bytes,
      dir: exportDirName,
    );
    return 1;
  }

  // ── shared helpers ─────────────────────────────────────────────────────

  Future<SessionData?> _readBody(
    SessionSummary s,
    List<ExportWarning> warnings,
  ) async {
    final body = await _store.readMuse(s.id);
    if (body == null) {
      warnings.add(ExportWarning(s.id, 'could not read session file'));
      return null;
    }
    return SessionReader.readRaw(body);
  }

  static String _num(double v) => v.toStringAsPrecision(6);

  /// File stem for one session: `yyyyMMdd_HHmmss_protocol_id8`.
  static String _stem(SessionMetadata meta, String id) {
    final t = meta.savedAt;
    final date = '${t.year.toString().padLeft(4, '0')}'
        '${t.month.toString().padLeft(2, '0')}'
        '${t.day.toString().padLeft(2, '0')}';
    final time = '${t.hour.toString().padLeft(2, '0')}'
        '${t.minute.toString().padLeft(2, '0')}'
        '${t.second.toString().padLeft(2, '0')}';
    final shortId = id.length > 8 ? id.substring(id.length - 8) : id;
    return '${date}_${time}_${meta.protocol.name}_$shortId';
  }

  /// The same charts the detail view shows: bands, alpha-vs-theta, movement,
  /// heart rate, plus the guardrail/music traces when present. Shared with
  /// the PDF exporter so PNG and PDF render identical content.
  static List<ExportChart> chartsFor(
    SessionChartData prepared,
    SessionMetadata meta,
  ) {
    final charts = <ExportChart>[
      ExportChart(
        title: 'Bands',
        subtitle: 'AF7/AF8 average · relative power',
        lines: [
          for (var i = 0; i < bandNames.length; i++)
            ExportChartLine(
              bandNames[i],
              bandColors[i],
              switch (i) {
                0 => prepared.deltaRel,
                1 => prepared.thetaRel,
                2 => prepared.alphaRel,
                3 => prepared.betaRel,
                _ => prepared.gammaRel,
              },
            ),
        ],
        yMin: 0,
        yMax: 1,
      ),
      ExportChart(
        title: 'Alpha vs Theta',
        subtitle: 'AF7/AF8 average · relative power',
        lines: [
          ExportChartLine('alpha', bandColors[2], prepared.alphaRel),
          ExportChartLine('theta', bandColors[1], prepared.thetaRel),
        ],
        yMin: 0,
        yMax: 1,
      ),
      ExportChart(
        title: 'Movement',
        subtitle: 'accelerometer magnitude',
        lines: [
          ExportChartLine('movement', const Color(0xFF26C6DA), prepared.movement),
        ],
      ),
      ExportChart(
        title: 'Heart rate',
        subtitle: 'PPG-derived BPM',
        lines: [
          ExportChartLine('bpm', const Color(0xFFEC407A), prepared.bpm),
        ],
      ),
      ExportChart(
        title: 'Blood oxygen (SpO₂)',
        subtitle: 'PPG IR+Red ratio-of-ratios',
        lines: [
          ExportChartLine('spo2', const Color(0xFF26C6DA), prepared.spo2),
        ],
        yMin: 50,
        yMax: 100,
      ),
    ];
    final drowsiness = meta.drowsiness;
    if (drowsiness != null && drowsiness.buckets.isNotEmpty) {
      charts.add(
        ExportChart(
          title: 'Sleep guardrail',
          subtitle: 'sleep-direction score (higher = sleepier)',
          lines: [
            ExportChartLine(
              'sleep-dir',
              const Color(0xFFAB47BC),
              [for (final b in drowsiness.buckets) b.sleepDir],
              threshold: drowsiness.threshold,
            ),
          ],
        ),
      );
    }
    final music = meta.music;
    if (music != null && music.buckets.isNotEmpty) {
      charts.add(
        ExportChart(
          title: 'Music cutoff',
          subtitle: 'reward-driven low-pass cutoff',
          lines: [
            ExportChartLine(
              'cutoff',
              const Color(0xFF66BB6A),
              [for (final b in music.buckets) b.cutoffHz],
            ),
          ],
        ),
      );
    }
    return charts;
  }
}

/// Resolve where an export should land:
///  * Desktop: the history folder itself (writes into its `export/` subdir).
///  * Android: the history folder when it is SAF-backed, otherwise a freshly
///    picked SAF folder (used only for this export). Returns null when the
///    user cancels the folder picker.
Future<SessionStorage?> resolveExportStorage(SessionStorage history) async {
  if (!Platform.isAndroid || history is SafSessionStorage) {
    return history;
  }
  final uri = await SafSessionStorage.pickFolder();
  if (uri == null) {
    return null;
  }
  return SafSessionStorage(uri);
}

// ── Chart rendering (offscreen rasterization) ─────────────────────────────

/// Render an [ExportChart] to a PNG byte blob without a live widget tree.
Future<Uint8List> rasterizeChart(
  ExportChart chart, {
  double width = 1200,
  double height = 480,
  double pixelRatio = 1.5,
}) async {
  final widget = Directionality(
    textDirection: TextDirection.ltr,
    child: CustomPaint(
      size: Size(width, height),
      painter: ExportChartPainter(chart),
    ),
  );
  final image = await _renderOffscreen(widget, Size(width, height), pixelRatio);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('PNG encoding failed');
    }
    return byteData.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Rasterizes a widget without attaching it to the live tree. Uses a private
/// [BuildOwner]/[PipelineOwner] so the render pipeline runs exactly once for
/// this image.
Future<ui.Image> _renderOffscreen(
  Widget widget,
  Size size,
  double pixelRatio,
) async {
  final buildOwner = BuildOwner(focusManager: FocusManager());
  final pipelineOwner = PipelineOwner();
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: ui.PlatformDispatcher.instance.views.first,
    child: boundary,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      devicePixelRatio: pixelRatio,
    ),
  );
  pipelineOwner.rootNode = renderView;
  renderView.prepareInitialFrame();
  final element = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: widget,
  ).attachToRenderTree(buildOwner);
  buildOwner.buildScope(element);
  pipelineOwner.flushLayout();
  pipelineOwner.flushCompositingBits();
  pipelineOwner.flushPaint();
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  element.detachRenderObject();
  pipelineOwner.rootNode = null;
  pipelineOwner.dispose();
  buildOwner.finalizeTree();
  return image;
}

/// Painter for exported charts: title, legend, axes, grid and polylines.
/// Kept dependency-free (pure [CustomPainter]) so both the PNG rasterizer and
/// any vector re-renderer can share the geometry.
class ExportChartPainter extends CustomPainter {
  const ExportChartPainter(this.chart);

  final ExportChart chart;

  static const _bg = Color(0xFFFFFFFF);
  static const _grid = Color(0xFFE5E7EB);
  static const _axis = Color(0xFF6B7280);
  static const _text = Color(0xFF111827);

  @override
  void paint(Canvas canvas, Size size) {
    final chart = this.chart.resolveScale();
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg);

    const padL = 64.0, padR = 20.0, padT = 56.0, padB = 44.0;
    final plot = Rect.fromLTRB(padL, padT, size.width - padR, size.height - padB);

    final titleStyle = TextStyle(
      color: _text,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      inherit: false,
    );
    _drawText(
      canvas,
      chart.title,
      Offset(padL, 12),
      style: titleStyle,
    );
    if (chart.subtitle != null) {
      _drawText(
        canvas,
        chart.subtitle!,
        Offset(padL, 30 + titleStyle.fontSize!),
        style: TextStyle(color: _axis, fontSize: 14, inherit: false),
      );
    }

    final yMin = chart.yMin!;
    final yMax = chart.yMax!;

    final xMax = chart.lines.fold<double>(0, (m, l) {
      final n = l.values.length - 1;
      return n > m ? n.toDouble() : m;
    });
    final minutes = xMax * chart.xStepSeconds / 60;

    // Grid + y labels (5 rows).
    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: _axis, fontSize: 13, inherit: false);
    for (var i = 0; i <= 4; i++) {
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final v = yMax - (yMax - yMin) * i / 4;
      _drawText(
        canvas,
        v.abs() < 1e-9 ? '0' : v.toStringAsFixed(2),
        Offset(padL - 6, y - 7),
        style: labelStyle,
        alignRight: true,
      );
    }
    // x labels (up to 6, in minutes).
    final xTicks = mathMin(6, xMax.floor() + 1);
    for (var i = 0; i <= xTicks; i++) {
      final t = xMax * i / xTicks;
      final x = plot.left + plot.width * t / xMax;
      if (i > 0) {
        canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      }
      _drawText(
        canvas,
        '${(t * chart.xStepSeconds / 60).toStringAsFixed(0)}m',
        Offset(x - 14, plot.bottom + 8),
        style: labelStyle,
      );
    }
    if (minutes > 0) {
      _drawText(
        canvas,
        'minutes',
        Offset(plot.right - 60, plot.bottom + 8),
        style: labelStyle,
      );
    }

    // Series polylines.
    for (final line in chart.lines) {
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;
      final path = Path();
      var first = true;
      for (var i = 0; i < line.values.length; i++) {
        final x = plot.left + plot.width * i / xMax;
        final y = plot.bottom - plot.height * (line.values[i] - yMin) / (yMax - yMin);
        final p = Offset(x, y);
        if (first) {
          path.moveTo(p.dx, p.dy);
          first = false;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
      if (line.threshold != null) {
        final y = plot.bottom -
            plot.height * (line.threshold! - yMin) / (yMax - yMin);
        final dash = Paint()
          ..color = line.color
          ..strokeWidth = 1.5;
        for (var x = plot.left; x < plot.right; x += 12) {
          canvas.drawLine(Offset(x, y), Offset(x + 6, y), dash);
        }
      }
    }

    // Legend.
    var lx = plot.left;
    for (final line in chart.lines) {
      final swatch = Paint()..color = line.color;
      canvas.drawRect(Rect.fromLTWH(lx, plot.bottom + 14, 18, 4), swatch);
      lx += 24;
      lx += _drawText(
        canvas,
        line.label,
        Offset(lx, plot.bottom + 8),
        style: TextStyle(color: _text, fontSize: 13, inherit: false),
      );
      lx += 20;
    }
  }

  double _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    TextStyle style = const TextStyle(color: _text, fontSize: 13),
    bool alignRight = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, alignRight ? offset.translate(-painter.width, 0) : offset);
    final w = painter.width;
    painter.dispose();
    return w;
  }

  @override
  bool shouldRepaint(covariant ExportChartPainter oldDelegate) =>
      oldDelegate.chart != chart;
}

double mathMin(double a, double b) => a < b ? a : b;
double mathMax(double a, double b) => a > b ? a : b;