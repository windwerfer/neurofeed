import 'dart:convert';
import 'dart:typed_data';

class TestEdfSignal {
  const TestEdfSignal(this.label, this.samplesPerRecord, this.data);
  final String label;
  final int samplesPerRecord;
  final List<double> data;
}

String _pad(String s, int w) =>
    s.length >= w ? s.substring(0, w) : s + ' ' * (w - s.length);

Uint8List buildTestEdf({
  required List<TestEdfSignal> signals,
  double recordDuration = 1.0,
  List<double>? recordStarts,
  List<({double onset, double duration, String text})> annotations = const [],
  String patientId = 'X X X X',
}) {
  final records = signals
      .map((s) => (s.data.length / s.samplesPerRecord).ceil())
      .fold<int>(1, (a, b) => a > b ? a : b);
  final starts =
      recordStarts ?? [for (var r = 0; r < records; r++) r * recordDuration];
  final tals = <List<int>>[];
  for (var r = 0; r < records; r++) {
    final b = BytesBuilder();
    b.add(ascii.encode('+${_num(starts[r])}\x14\x14\x00'));
    for (final a in annotations) {
      if (a.onset >= starts[r] && a.onset < starts[r] + recordDuration) {
        final dur = a.duration > 0 ? '\x15${_num(a.duration)}' : '';
        b.add(ascii.encode('+${_num(a.onset)}$dur\x14${a.text}\x14\x00'));
      }
    }
    tals.add(b.toBytes());
  }
  final annSamples =
      (tals.map((t) => t.length).fold<int>(2, (a, b) => a > b ? a : b) + 1) ~/
      2;
  final ns = signals.length + 1;
  final h = StringBuffer()
    ..write(_pad('0', 8))
    ..write(_pad(patientId, 80))
    ..write(_pad('Startdate X X X X', 80))
    ..write('25.09.26')
    ..write('10.00.00')
    ..write(_pad('${256 * (ns + 1)}', 8))
    ..write(_pad(recordStarts != null ? 'EDF+D' : 'EDF+C', 44))
    ..write(_pad('$records', 8))
    ..write(_pad(_num(recordDuration), 8))
    ..write(_pad('$ns', 4));
  final labels = [...signals.map((s) => s.label), 'EDF Annotations'];
  for (final l in labels) {
    h.write(_pad(l, 16));
  }
  for (var i = 0; i < ns; i++) {
    h.write(_pad('', 80));
  }
  for (var i = 0; i < ns; i++) {
    h.write(_pad(i < signals.length ? 'uV' : '', 8));
  }
  for (var i = 0; i < ns; i++) {
    h.write(_pad(i < signals.length ? '-3276.8' : '-1', 8));
  }
  for (var i = 0; i < ns; i++) {
    h.write(_pad(i < signals.length ? '3276.7' : '1', 8));
  }
  for (var i = 0; i < ns; i++) {
    h.write(_pad('-32768', 8));
  }
  for (var i = 0; i < ns; i++) {
    h.write(_pad('32767', 8));
  }
  for (var i = 0; i < ns; i++) {
    h.write(_pad('', 80));
  }
  for (final s in signals) {
    h.write(_pad('${s.samplesPerRecord}', 8));
  }
  h.write(_pad('$annSamples', 8));
  for (var i = 0; i < ns; i++) {
    h.write(_pad('', 32));
  }
  final out = BytesBuilder()..add(ascii.encode(h.toString()));
  for (var r = 0; r < records; r++) {
    for (final s in signals) {
      final bd = ByteData(s.samplesPerRecord * 2);
      for (var i = 0; i < s.samplesPerRecord; i++) {
        final idx = r * s.samplesPerRecord + i;
        final v = idx < s.data.length ? s.data[idx] : 0.0;
        bd.setInt16(
          i * 2,
          (v * 10).round().clamp(-32768, 32767),
          Endian.little,
        );
      }
      out.add(bd.buffer.asUint8List());
    }
    final t = Uint8List(annSamples * 2)..setAll(0, tals[r]);
    out.add(t);
  }
  return out.toBytes();
}

String _num(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
