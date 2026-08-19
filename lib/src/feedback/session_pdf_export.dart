import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:muse_ml/src/charts/session_reader.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_chart_data.dart';
import 'package:muse_ml/src/feedback/session_export.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds the vector PDF report page for one session, or null when the
/// session file cannot be read. All charts share [SessionExporter.chartsFor]
/// so the PDF matches the PNG export and the on-screen dashboard.
Future<Uint8List?> buildPdfPage(SessionSummary session, SessionStore store) async {
  final body = await store.readMuse(session.id);
  if (body == null) {
    return null;
  }
  final data = await SessionReader.readRaw(body);
  final meta = session.metadata;
  final protocol = ProtocolInfo.forType(meta.protocol);
  final prepared = prepareChartData(
    data,
    trainingStartOffset: meta.calibration?.trainingStartOffsetSecs,
    metric: protocol.rewardMetric,
    conditions: protocol.conditions,
  );
  final charts = SessionExporter.chartsFor(prepared, meta);

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: pw.Font.helvetica()),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Text(
          '${meta.protocol.name} — session report',
          style: const pw.TextStyle(
            fontSize: 20,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          _infoLines(meta).join('  ·  '),
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        if (meta.notes.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            'Notes: ${meta.notes}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
        pw.SizedBox(height: 14),
        for (final chart in charts) ...[
          pw.Text(
            chart.title,
            style: const pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (chart.subtitle != null)
            pw.Text(
              chart.subtitle!,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          pw.SizedBox(height: 4),
          _pdfChart(chart),
          pw.SizedBox(height: 16),
        ],
      ],
    ),
  );
  return doc.save();
}

List<String> _infoLines(SessionMetadata meta) {
  final t = meta.savedAt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final when = '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
  final minutes = meta.durationMinutes > 0
      ? '${meta.durationMinutes} min'
      : '${meta.elapsedSeconds}s';
  return [
    when,
    'duration $minutes',
    'sound ${meta.feedbackSound ?? meta.sound}',
    if (meta.deviceName != null) meta.deviceName!,
  ];
}

const _padL = 46.0, _padR = 10.0, _padT = 8.0, _padB = 26.0;
const _chartHeight = 150.0;
const _legendTop = _chartHeight - 16.0;

pw.Widget _pdfChart(ExportChart chart) {
  final resolved = chart.resolveScale();
  return pw.SizedBox(
    height: _chartHeight,
    child: pw.Stack(
      children: [
        pw.Positioned.fill(
          child: pw.CustomPaint(
            painter: (PdfGraphics canvas, PdfPoint size) =>
                _paintPdfChart(canvas, size, resolved),
          ),
        ),
        for (var i = 0; i <= 4; i++)
          pw.Positioned(
            left: 2,
            top: _chartHeight -
                _padB -
                (_chartHeight - _padT - _padB) * i / 4 -
                5,
            child: pw.Text(
              _yLabel(resolved, i),
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          ),
        pw.Positioned(
          left: _padL,
          top: _legendTop,
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              for (final line in resolved.lines) ...[
                pw.Container(
                  width: 12,
                  height: 3,
                  color: PdfColor.fromInt(line.color.toARGB32()),
                ),
                pw.SizedBox(width: 3),
                pw.Text(
                  line.label,
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey900,
                  ),
                ),
                pw.SizedBox(width: 12),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

String _yLabel(ExportChart chart, int i) {
  final v = chart.yMax! - (chart.yMax! - chart.yMin!) * i / 4;
  return v.abs() < 1e-9 ? '0' : v.toStringAsFixed(2);
}

/// Grid + polylines + threshold. Coordinate origin is the bottom-left of the
/// painter box (pdf's CustomPaint transform), so y grows upward.
void _paintPdfChart(
  PdfGraphics canvas,
  PdfPoint size,
  ExportChart chart,
) {
  final plotW = size.x - _padL - _padR;
  final plotH = size.y - _padT - _padB;
  final xMax = chart.lines.fold<double>(0, (m, l) {
    final n = l.values.length - 1;
    return n > m ? n.toDouble() : m;
  });
  if (xMax <= 0) {
    return;
  }

  canvas
    ..drawRect(0, 0, size.x, size.y)
    ..setColor(PdfColors.white)
    ..fillPath();

  final gridColor = PdfColor.fromInt(const Color(0xFFE5E7EB).toARGB32());
  final yMin = chart.yMin!, yMax = chart.yMax!;
  for (var i = 0; i <= 4; i++) {
    final y = _padB + plotH * i / 4;
    canvas
      ..drawLine(_padL, y, _padL + plotW, y)
      ..setColor(gridColor)
      ..setLineWidth(0.5)
      ..strokePath();
  }

  for (final line in chart.lines) {
    final color = PdfColor.fromInt(line.color.toARGB32());
    canvas
      ..setColor(color)
      ..setLineWidth(1.2);
    var first = true;
    for (var i = 0; i < line.values.length; i++) {
      final x = _padL + plotW * i / xMax;
      final y =
          _padB + plotH * (line.values[i] - yMin) / (yMax - yMin);
      if (first) {
        canvas.moveTo(x, y);
        first = false;
      } else {
        canvas.lineTo(x, y);
      }
    }
    canvas.strokePath();
    final threshold = line.threshold;
    if (threshold != null) {
      final y = _padB + plotH * (threshold - yMin) / (yMax - yMin);
      canvas
        ..setColor(color)
        ..setLineWidth(0.8)
        ..setLineDashPattern([3, 2])
        ..drawLine(_padL, y, _padL + plotW, y)
        ..strokePath();
    }
  }
}