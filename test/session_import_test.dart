import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/import/csv_import.dart';
import 'package:neurofeed/src/feedback/session_chart_data.dart';
import 'package:neurofeed/src/feedback/import/edf_import.dart';
import 'package:neurofeed/src/feedback/import/import_types.dart';
import 'package:neurofeed/src/feedback/import/montage_match.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/feedback/session_sqlite.dart';
import 'package:neurofeed/src/monitor/recording/recording_store.dart';
import 'package:neurofeed/src/feedback/import/publish_import.dart';
import 'package:neurofeed/src/rust/api/edf_export.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';
import 'package:neurofeed/src/rust/frb_generated.dart';
import 'package:neurofeed/src/session_format/models.dart';
import 'package:neurofeed/src/settings.dart';

import 'support/edf_writer.dart';

const _muse = ['TP9', 'AF7', 'AF8', 'TP10'];
const _bandNames = ['Delta', 'Theta', 'Alpha', 'Beta', 'Gamma'];

String _ts(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}.'
    '${t.millisecond.toString().padLeft(3, '0')}';

/// Mind Monitor style CSV: 4 Muse band + RAW columns, rows every [dtSeconds].
/// [bandEvery] fills band cells on every n-th row only (Constant files).
String _museCsv({
  required int rows,
  required double dtSeconds,
  int bandEvery = 1,
  double Function(int row)? alpha,
  List<String> extraHeaders = const [],
  List<String> Function(int row)? extra,
  double Function(int row)? secondsAt,
}) {
  final b = StringBuffer('TimeStamp');
  for (final band in _bandNames) {
    for (final ch in _muse) {
      b.write(',${band}_$ch');
    }
  }
  for (final ch in _muse) {
    b.write(',RAW_$ch');
  }
  for (final h in extraHeaders) {
    b.write(',$h');
  }
  b.writeln();
  final start = DateTime(2026, 9, 25, 10, 0, 0);
  for (var i = 0; i < rows; i++) {
    final secs = secondsAt?.call(i) ?? i * dtSeconds;
    final t = start.add(Duration(microseconds: (secs * 1e6).round()));
    b.write(_ts(t));
    final withBands = i % bandEvery == 0;
    for (var bi = 0; bi < 5; bi++) {
      for (var c = 0; c < 4; c++) {
        final v = bi == 2 && alpha != null ? alpha(i) : 1.0 + bi;
        b.write(withBands ? ',$v' : ',');
      }
    }
    for (var c = 0; c < 4; c++) {
      b.write(',${800 + i + c}.0');
    }
    for (final v in extra?.call(i) ?? const <String>[]) {
      b.write(',$v');
    }
    b.writeln();
  }
  return b.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        '${Directory.current.path}/rust/target/debug/librust_lib_neurofeed.so',
      ),
    );
  });

  const subject = SubjectInfo(id: 'test-subject-uuid');

  group('edfPatientCode / annotation map', () {
    test('extracts code and skips X', () {
      expect(edfPatientCode('abc123 X X X'), 'abc123');
      expect(edfPatientCode('X X X X'), isNull);
      expect(edfPatientCode(''), isNull);
    });

    test('maps locked TAL texts', () {
      expect(mapImportAnnotationType('double_blink'), 'double_blink');
      expect(mapImportAnnotationType('Double blink'), 'double_blink');
      expect(mapImportAnnotationType('Calibration start'), isNull);
      expect(mapImportAnnotationType('eye_up'), 'eye_up');
    });
  });

  group('EDF round-trip', () {
    Uint8List buildEdfBody() {
      final events = <int>[];
      for (var pkt = 0; pkt < 20; pkt++) {
        final ts = pkt * 12 * 1000.0 / 256.0;
        for (var el = 0; el < 4; el++) {
          events.addAll(
            encodeSessionEvent(
              event: MuseEventDto.eeg(
                EegDto(
                  index: pkt,
                  electrode: el,
                  timestamp: ts,
                  samples: Float64List.fromList(
                    List<double>.filled(12, el.isEven ? 50.0 : -50.0),
                  ),
                ),
              ),
            ),
          );
        }
      }
      final header = sessionHeaderBytes();
      final frame = sessionFrameBytes(data: events);
      return Uint8List.fromList([...header, ...frame]);
    }

    test('encode → decodeEdfImport → NFED6 preserves channels/samples/start', () {
      final body = buildEdfBody();
      final edf = encodeEdfExport(
        body: body,
        channelLabels: const ['TP9', 'AF7', 'AF8', 'TP10'],
        params: const EdfExportParams(
          patientId: 'subj-import X X X',
          recordingId: 'rec',
          year: 2026,
          month: 9,
          day: 25,
          hour: 4,
          minute: 0,
          second: 0,
          annotations: [
            EdfExportAnnotation(
              onsetSeconds: 0.5,
              durationSeconds: 0,
              text: 'double_blink',
            ),
          ],
          prefiltering: 'HP:DC N:none',
        ),
      );

      final decoded = decodeEdfImport(bytes: edf);
      expect(decoded.signals.map((s) => s.prefiltering).toSet(), {
        'HP:DC N:none',
      });
      expect(decoded.signals.length, 4);
      expect(decoded.signals[0].label, 'TP9');
      expect(decoded.signals[1].label, 'AF7');
      expect(decoded.year, 2026);
      expect(decoded.month, 9);
      expect(decoded.day, 25);
      expect(decoded.hour, 4);
      expect(decoded.signals[0].data.length, greaterThanOrEqualTo(12 * 20));
      expect(
        decoded.annotations.any((a) => a.text == 'double_blink'),
        isTrue,
      );

      final imported = importEdfBytes(
        bytes: edf,
        fallbackSubject: subject,
        recordingId: 'edf_rt_1',
        timeZone: 'Etc/UTC',
      );
      expect(imported.metadataJson['kind'], 'recording');
      expect(imported.metadataJson['formatVersion'], 6);
      expect(
        (imported.metadataJson['subject'] as Map)['id'],
        'subj-import',
      );
      final device = imported.metadataJson['device'] as Map;
      expect(device['channelLabels'], ['TP9', 'AF7', 'AF8', 'TP10']);
      expect(device['model'], 'imported');
      final prov = imported.metadataJson['import'] as Map;
      expect(prov['sourceFormat'], 'edf+');
      expect(prov['lossy'], isFalse);
      expect(prov['resampled'], isFalse);
      expect(prov['droppedChannels'], isEmpty);
      expect((prov['prefiltering'] as Map)['AF7'], 'HP:DC N:none');
      final conditioning = device['conditioning'] as Map;
      expect(conditioning['highPassHz'], 0.5);
      expect(conditioning['notchQ'], 30);

      final anns = imported.metadataJson['annotations'] as List;
      expect(anns.any((a) => (a as Map)['type'] == 'double_blink'), isTrue);

      // Round-trip: parse NFED6 raw EEG sample count.
      final raw = extractRaw(bytes: imported.containerBytes);
      final data = sessionParseBody(bytes: raw);
      expect(data.eeg.length, greaterThan(0));
      expect(data.eeg.first.electrode, 0);
      final totalSamples = data.eeg.fold<int>(
        0,
        (n, r) => n + r.samples.length,
      );
      expect(totalSamples, greaterThanOrEqualTo(12 * 20));
      // Stored RAW is the decoded EDF data, not the conditioned signal.
      final tp9 = data.eeg.where((r) => r.electrode == 0).first;
      for (var i = 0; i < tp9.samples.length; i++) {
        expect(tp9.samples[i], closeTo(decoded.signals[0].data[i], 1e-3));
      }
    });

    test('TAL duration round-trips into SessionAnnotation.duration', () {
      final events = <int>[];
      for (var pkt = 0; pkt < 30; pkt++) {
        final ts = pkt * 12 * 1000.0 / 256.0;
        for (var el = 0; el < 4; el++) {
          events.addAll(
            encodeSessionEvent(
              event: MuseEventDto.eeg(
                EegDto(
                  index: pkt,
                  electrode: el,
                  timestamp: ts,
                  samples: Float64List.fromList(List<double>.filled(12, 10.0)),
                ),
              ),
            ),
          );
        }
      }
      final header = sessionHeaderBytes();
      final frame = sessionFrameBytes(data: events);
      final body = Uint8List.fromList([...header, ...frame]);
      final edf = encodeEdfExport(
        body: body,
        channelLabels: const ['TP9', 'AF7', 'AF8', 'TP10'],
        params: const EdfExportParams(
          patientId: 'dur-subj X X X',
          recordingId: 'rec',
          year: 2026,
          month: 9,
          day: 25,
          hour: 4,
          minute: 0,
          second: 0,
          annotations: [
            EdfExportAnnotation(
              onsetSeconds: 0.5,
              durationSeconds: 15.0,
              text: 'bad_quality',
            ),
            EdfExportAnnotation(
              onsetSeconds: 0.8,
              durationSeconds: 0,
              text: 'double_blink',
            ),
          ],
          prefiltering: '',
        ),
      );
      final imported = importEdfBytes(
        bytes: edf,
        fallbackSubject: subject,
        recordingId: 'edf_dur',
      );
      final anns = imported.metadataJson['annotations'] as List;
      final bq = anns.cast<Map>().firstWhere((a) => a['type'] == 'bad_quality');
      expect((bq['duration'] as num).toDouble(), closeTo(15.0, 1e-6));
      final db =
          anns.cast<Map>().firstWhere((a) => a['type'] == 'double_blink');
      expect((db['duration'] as num).toDouble(), 0);
    });

    test('EDF+D timekeeping gap becomes disconnect and shifts raw', () {
      final edf = buildTestEdf(
        signals: [
          for (final l in const ['TP9', 'AF7', 'AF8', 'TP10'])
            TestEdfSignal(l, 256, List<double>.filled(512, 5.0)),
        ],
        recordStarts: const [0, 5],
      );
      final decoded = decodeEdfImport(bytes: edf);
      expect(decoded.recordStartsSeconds.toList(), [0.0, 5.0]);
      final imported = importEdfBytes(
        bytes: edf,
        fallbackSubject: subject,
        recordingId: 'edf_d',
      );
      final anns = (imported.metadataJson['annotations'] as List).cast<Map>();
      final disc = anns.firstWhere((a) => a['type'] == 'disconnect');
      expect((disc['onset'] as num).toDouble(), closeTo(1.0, 1e-9));
      expect((disc['duration'] as num).toDouble(), closeTo(4.0, 1e-9));
      final data = sessionParseBody(
        bytes: extractRaw(bytes: imported.containerBytes),
      );
      final last =
          data.eeg.map((r) => r.timestamp).reduce((a, b) => a > b ? a : b);
      expect(last, greaterThanOrEqualTo(5000.0));
      expect(imported.metadataJson['durationS'], 6);
    });
  });

  group('Mind Monitor CSV', () {
    final oneHzCsv = '''
TimeStamp,Delta_TP9,Delta_AF7,Delta_AF8,Delta_TP10,Theta_TP9,Theta_AF7,Theta_AF8,Theta_TP10,Alpha_TP9,Alpha_AF7,Alpha_AF8,Alpha_TP10,Beta_TP9,Beta_AF7,Beta_AF8,Beta_TP10,Gamma_TP9,Gamma_AF7,Gamma_AF8,Gamma_TP10,RAW_TP9,RAW_AF7,RAW_AF8,RAW_TP10
2026-09-25 10:00:00.000,1.1,1.2,1.3,1.4,2.1,2.2,2.3,2.4,3.1,3.2,3.3,3.4,4.1,4.2,4.3,4.4,5.1,5.2,5.3,5.4,100.0,101.0,102.0,103.0
2026-09-25 10:00:01.000,1.1,1.2,1.3,1.4,2.1,2.2,2.3,2.4,3.1,3.2,3.3,3.4,4.1,4.2,4.3,4.4,5.1,5.2,5.3,5.4,110.0,111.0,112.0,113.0
2026-09-25 10:00:02.000,1.1,1.2,1.3,1.4,2.1,2.2,2.3,2.4,3.1,3.2,3.3,3.4,4.1,4.2,4.3,4.4,5.1,5.2,5.3,5.4,120.0,121.0,122.0,123.0
''';

    test('1 s interval CSV imports bands only, no RAW', () {
      final parsed = parseMindMonitorCsv(oneHzCsv);
      expect(parsed.rate, CsvRecordingRate.interval);
      expect(parsed.channelLabels, ['TP9', 'AF7', 'AF8', 'TP10']);
      expect(parsed.medianDeltaSeconds, closeTo(1.0, 0.05));

      final imported = importCsvText(
        csvText: oneHzCsv,
        subject: subject,
        recordingId: 'csv_1hz',
        timeZone: 'Asia/Bangkok',
      );
      expect(imported.metadataJson['kind'], 'recording');
      expect(imported.metadataJson['formatVersion'], 6);
      expect(
        (imported.metadataJson['subject'] as Map)['id'],
        'test-subject-uuid',
      );
      expect(imported.metadataJson['timeZone'], 'Asia/Bangkok');
      expect(imported.metadataJson.containsKey('feedback'), isFalse);

      final raw = extractRaw(bytes: imported.containerBytes);
      final data = sessionParseBody(bytes: raw);
      expect(data.eeg, isEmpty);
      // One band record per row per electrode, at the real row times.
      expect(data.bands.length, 12);
      final streams = imported.metadataJson['streams'] as Map;
      expect((streams['eeg'] as Map)['enabled'], isFalse);
      final prov = imported.metadataJson['import'] as Map;
      expect(prov['sourceFormat'], 'mind_monitor_csv');
      expect(prov['rawPresent'], isFalse);
      expect(prov['recordingInterval'], 1.0);
      expect(prov['originalRateHz'], isNull);
      expect(prov['reference'], 'FPz');
      expect(prov['lossy'], isTrue);
      expect(
        imported.warnings.any((w) => w.message.contains('Recording interval 1 s')),
        isTrue,
      );
    });

    test('Constant CSV keeps RAW and every band value', () {
      final csv = _museCsv(
        rows: 26,
        dtSeconds: 1 / 256,
        bandEvery: 10,
        alpha: (i) => 3.0 + i / 100,
      );
      final parsed = parseMindMonitorCsv(csv);
      expect(parsed.rate, CsvRecordingRate.constant);
      expect(parsed.medianDeltaSeconds, lessThan(0.01));

      final imported = importCsvText(
        csvText: csv,
        subject: subject,
        recordingId: 'csv_const',
      );
      final data = sessionParseBody(
        bytes: extractRaw(bytes: imported.containerBytes),
      );
      final samples = data.eeg
          .where((r) => r.electrode == 0)
          .fold<int>(0, (n, r) => n + r.samples.length);
      expect(samples, 26);
      // Rows 0, 10, 20 carry bands → three records per electrode (not one
      // per second).
      expect(data.bands.where((b) => b.electrode == 0).length, 3);
      final prov = imported.metadataJson['import'] as Map;
      expect(prov['originalRateHz'], 256);
      expect(prov['recordingInterval'], isNull);
      expect(prov['resampled'], isFalse);
      expect(prov['lossy'], isFalse);
    });

    test('MU-01 Constant CSV at 220 Hz is resampled to 256 Hz', () {
      final csv = _museCsv(rows: 440, dtSeconds: 1 / 220, bandEvery: 22);
      final imported = importCsvText(
        csvText: csv,
        subject: subject,
        recordingId: 'csv_220',
      );
      final data = sessionParseBody(
        bytes: extractRaw(bytes: imported.containerBytes),
      );
      final samples = data.eeg
          .where((r) => r.electrode == 0)
          .fold<int>(0, (n, r) => n + r.samples.length);
      expect(samples, closeTo(512, 2));
      final prov = imported.metadataJson['import'] as Map;
      expect(prov['originalRateHz'], 220);
      expect(prov['resampled'], isTrue);
      expect(prov['lossy'], isTrue);
    });

    test('0.5 s interval: computed frames average the rows of each second', () {
      final csv = _museCsv(
        rows: 8,
        dtSeconds: 0.5,
        alpha: (i) => i.isEven ? 1.0 : 2.0,
      );
      final imported = importCsvText(
        csvText: csv,
        subject: subject,
        recordingId: 'csv_half',
      );
      final frames = extractComputed(bytes: imported.containerBytes);
      expect(frames.map((f) => f.t).toList(), [0, 1, 2, 3]);
      // Mean of 10^1 and 10^2 in linear power.
      expect(frames.first.bands[0][2], closeTo(55.0, 1e-3));
      expect(
        (imported.metadataJson['import'] as Map)['recordingInterval'],
        0.5,
      );
      final data = sessionParseBody(
        bytes: extractRaw(bytes: imported.containerBytes),
      );
      expect(data.eeg, isEmpty);
      expect(data.bands.where((b) => b.electrode == 0).length, 8);
    });

    test('60 s interval: sparse frames at the real row times', () {
      final csv = _museCsv(rows: 3, dtSeconds: 60);
      final imported = importCsvText(
        csvText: csv,
        subject: subject,
        recordingId: 'csv_60',
      );
      final frames = extractComputed(bytes: imported.containerBytes);
      expect(frames.map((f) => f.t).toList(), [0, 60, 120]);
      expect(imported.metadataJson['durationS'], 120);
    });

    group('interval coverage warning', () {
      ImportProvenance importAt(String csv) =>
          importCsvText(csvText: csv, subject: subject, recordingId: 'cov')
              .provenance;

      test('1 s interval: full coverage, no warning', () {
        final p = importAt(_museCsv(rows: 6, dtSeconds: 1));
        expect(p.recordingInterval, 1.0);
        expect(p.intervalCoverage, 1.0);
        expect(intervalCoverageWarning(p), isNull);
      });

      test('2 s interval: 50% coverage and a warning', () {
        final imported = importCsvText(
          csvText: _museCsv(rows: 6, dtSeconds: 2),
          subject: subject,
          recordingId: 'cov2',
        );
        final prov = imported.metadataJson['import'] as Map;
        expect(prov['recordingInterval'], 2.0);
        expect(prov['intervalCoverage'], 0.5);
        final warning = intervalCoverageWarning(imported.provenance);
        expect(
          warning,
          'This Mind Monitor file was recorded with one row every 2 seconds, '
          'so it covers only about 50% of the session. Short events can be '
          'missed, so expect lower result quality. For better results, set '
          "Mind Monitor's recording interval to 1 second.",
        );
      });

      test('10 s interval: 10% coverage', () {
        final p = importAt(_museCsv(rows: 4, dtSeconds: 10));
        expect(p.recordingInterval, 10.0);
        expect(p.intervalCoverage, 0.1);
        expect(intervalCoverageWarning(p), contains('every 10 seconds'));
        expect(intervalCoverageWarning(p), contains('about 10%'));
      });

      test('jittery timestamps use the median gap', () {
        const jitter = [0.0, 0.04, -0.03, 0.05, -0.02, 0.03, -0.05, 0.01, 0.0];
        final twoSec = importAt(
          _museCsv(rows: 9, dtSeconds: 2, secondsAt: (i) => i * 2 + jitter[i]),
        );
        expect(twoSec.recordingInterval, 2.0);
        expect(twoSec.intervalCoverage, 0.5);
        expect(intervalCoverageWarning(twoSec), contains('about 50%'));

        final oneSec = importAt(
          _museCsv(rows: 9, dtSeconds: 1, secondsAt: (i) => i + jitter[i]),
        );
        expect(oneSec.recordingInterval, 1.0);
        expect(intervalCoverageWarning(oneSec), isNull);
      });

      test('Constant CSV has no interval, coverage or warning', () {
        final imported = importCsvText(
          csvText: _museCsv(rows: 26, dtSeconds: 1 / 256, bandEvery: 10),
          subject: subject,
          recordingId: 'cov_const',
        );
        final prov = imported.metadataJson['import'] as Map;
        expect(prov['recordingInterval'], isNull);
        expect(prov.containsKey('intervalCoverage'), isTrue);
        expect(prov['intervalCoverage'], isNull);
        expect(intervalCoverageWarning(imported.provenance), isNull);
      });
    });

    test('AUX columns become AUX1…; Optics dropped with a warning', () {
      final csv = _museCsv(
        rows: 26,
        dtSeconds: 1 / 256,
        bandEvery: 10,
        extraHeaders: const ['AUX_RIGHT', 'Optics1', 'Optics2'],
        extra: (i) => ['${i + 5}.0', '1.0', '2.0'],
      );
      final imported = importCsvText(
        csvText: csv,
        subject: subject,
        recordingId: 'csv_aux',
      );
      final device = imported.metadataJson['device'] as Map;
      expect(device['channelLabels'], [..._muse, 'AUX1']);
      final data = sessionParseBody(
        bytes: extractRaw(bytes: imported.containerBytes),
      );
      expect(data.eeg.any((r) => r.electrode == 4), isTrue);
      final prov = imported.metadataJson['import'] as Map;
      expect(prov['droppedChannels'], ['Optics1', 'Optics2']);
      expect(prov['originalChannels'], [..._muse, 'AUX_RIGHT']);
      expect(imported.warnings.any((w) => w.message.contains('Optics')), isTrue);
      final streams = imported.metadataJson['streams'] as Map;
      expect((streams['ppg'] as Map)['enabled'], isFalse);
    });

    test('CSV without all four Muse channels is refused', () {
      const csv =
          'TimeStamp,Delta_TP9,Theta_TP9,Alpha_TP9,Beta_TP9,Gamma_TP9,RAW_TP9\n'
          '2026-09-25 10:00:00.000,1,2,3,4,5,100\n'
          '2026-09-25 10:00:01.000,1,2,3,4,5,101\n';
      expect(
        () => importCsvText(csvText: csv, subject: subject),
        throwsA(isA<ImportRefused>()),
      );
    });

    test('1 Hz CSV with bands fills computed section', () {
      final imported = importCsvText(
        csvText: oneHzCsv,
        subject: subject,
        recordingId: 'csv_computed',
      );
      final frames = extractComputed(bytes: imported.containerBytes);
      expect(frames, isNotEmpty);
      expect(frames.first.bands.length, 4);
      // Bel 3.1 → linear 10^3.1
      expect(frames.first.bands[0][2], closeTo(1258.925, 1.0));
      final prepared = prepareChartDataFromComputed(frames);
      expect(prepared.alphaRel, isNotEmpty);
      expect(imported.metadataJson.containsKey('feedback'), isFalse);
    });

    test('interval CSV skips IMU snapshots and maps Elements doubles', () {
      final csv = _museCsv(
        rows: 3,
        dtSeconds: 1,
        extraHeaders: const [
          'Accelerometer_X',
          'Accelerometer_Y',
          'Accelerometer_Z',
          'Gyro_X',
          'Gyro_Y',
          'Gyro_Z',
          'Battery',
          'Elements',
        ],
        extra: (i) => [
          '0.1', '0.2', '0.9', '1.0', '2.0', '3.0', '0.9',
          i < 2 ? 'Blink' : '',
        ],
      );
      final parsed = parseMindMonitorCsv(csv);
      expect(parsed.hasAcc, isTrue);
      expect(parsed.hasGyro, isTrue);
      expect(parsed.hasBattery, isTrue);
      expect(parsed.hasElements, isTrue);
      final imported = importCsvText(
        csvText: csv,
        subject: subject,
        recordingId: 'csv_imu_el',
      );
      final streams = imported.metadataJson['streams'] as Map;
      expect((streams['imu'] as Map)['enabled'], isFalse);
      expect(
        imported.warnings.any((w) => w.message.contains('RAW/IMU')),
        isTrue,
      );
      final anns = imported.metadataJson['annotations'] as List;
      expect(
        anns.any((a) => (a as Map)['type'] == 'double_blink'),
        isTrue,
      );
    });

    test('Constant CSV with ACC enables imu stream', () {
      final csv = _museCsv(
        rows: 26,
        dtSeconds: 1 / 256,
        bandEvery: 10,
        extraHeaders: const [
          'Accelerometer_X',
          'Accelerometer_Y',
          'Accelerometer_Z',
        ],
        extra: (_) => ['0.1', '0.2', '0.98'],
      );
      final imported = importCsvText(
        csvText: csv,
        subject: subject,
        recordingId: 'csv_const_acc',
      );
      final streams = imported.metadataJson['streams'] as Map;
      expect((streams['imu'] as Map)['enabled'], isTrue);
      final frames = extractComputed(bytes: imported.containerBytes);
      expect(frames, isNotEmpty);
    });

    test('Elements singles warn; markers skipped', () {
      final mapped = mapElementsToAnnotations([
        const ElementMark(onsetSeconds: 0.0, raw: 'Blink'),
        const ElementMark(onsetSeconds: 5.0, raw: 'Jaw_Clench'),
        const ElementMark(onsetSeconds: 6.0, raw: '1'),
      ]);
      expect(mapped.annotations, isEmpty);
      expect(mapped.warnings.any((w) => w.message.contains('single')), isTrue);
      expect(mapped.warnings.any((w) => w.message.contains('marker')), isTrue);
    });
  });


  group('EDF import policy', () {
    List<double> sine(double hz, int rate, int n) => [
      for (var i = 0; i < n; i++) 20 * math.sin(2 * math.pi * hz * i / rate),
    ];

    test('label normalization accepts EEG prefix and reference suffixes', () {
      expect(normalizeEegLabel('EEG Fp1-REF'), 'FP1');
      expect(normalizeEegLabel('eeg tp9-Ref'), 'TP9');
      expect(normalizeEegLabel('AF7-LE'), 'AF7');
      expect(normalizeEegLabel('TP10-AVG'), 'TP10');
      expect(normalizeEegLabel(' af8 '), 'AF8');
    });

    test('10-10 cap at 512 Hz: Muse subset kept, resampled, lossy', () {
      const cap = [
        'Fp1', 'Fp2', 'AF7', 'AF8', 'F5', 'F6', 'C3', 'C4', 'Cz',
        'TP9', 'TP10', 'O1', 'O2', 'Pz', 'T7', 'T8',
      ];
      final edf = buildTestEdf(
        signals: [
          for (final l in cap)
            TestEdfSignal('EEG $l-REF', 512, sine(10, 512, 512 * 4)),
        ],
      );
      final imported = importEdfBytes(
        bytes: edf,
        fallbackSubject: subject,
        sourceFileName: 'cap.edf',
        recordingId: 'edf_cap',
      );
      final device = imported.metadataJson['device'] as Map;
      expect(device['channelLabels'], _muse);
      final prov = imported.metadataJson['import'] as Map;
      expect(prov['sourceFileName'], 'cap.edf');
      expect(prov['originalChannels'], hasLength(cap.length));
      expect(prov['droppedChannels'], hasLength(cap.length - 4));
      expect(prov['originalRateHz'], 512);
      expect(prov['resampled'], isTrue);
      expect(prov['reference'], 'REF');
      expect(prov['lossy'], isTrue);
      final data = sessionParseBody(
        bytes: extractRaw(bytes: imported.containerBytes),
      );
      final tp9 = data.eeg
          .where((r) => r.electrode == 0)
          .fold<int>(0, (n, r) => n + r.samples.length);
      expect(tp9, closeTo(1024, 2));
      // Bands from our own FFT, one per electrode per second.
      expect(data.bands.where((b) => b.electrode == 0).length, 4);
      final frames = extractComputed(bytes: imported.containerBytes);
      expect(frames, hasLength(4));
      expect(frames.first.bands[0][2], greaterThan(frames.first.bands[0][0]));
    });

    test('native Crown 8 ch at 256 Hz is not lossy', () {
      const crown = ['CP3', 'C3', 'F5', 'PO3', 'PO4', 'F6', 'C4', 'CP4'];
      final edf = buildTestEdf(
        signals: [
          for (final l in crown) TestEdfSignal(l, 256, sine(10, 256, 512)),
        ],
      );
      final imported = importEdfBytes(
        bytes: edf,
        fallbackSubject: subject,
        recordingId: 'edf_crown',
      );
      expect((imported.metadataJson['device'] as Map)['channelLabels'], crown);
      final prov = imported.metadataJson['import'] as Map;
      expect(prov['lossy'], isFalse);
      expect(prov.containsKey('reference'), isFalse);
    });

    test('no complete supported montage is refused', () {
      final edf = buildTestEdf(
        signals: [
          for (final l in const ['Fp1', 'Fp2', 'Cz', 'TP9', 'AF7'])
            TestEdfSignal(l, 256, sine(10, 256, 256)),
        ],
      );
      expect(
        () => importEdfBytes(bytes: edf, fallbackSubject: subject),
        throwsA(
          isA<ImportRefused>().having(
            (e) => e.message,
            'message',
            contains('No supported headset montage'),
          ),
        ),
      );
    });

    test('lossy import summary and export notice', () {
      final edf = buildTestEdf(
        signals: [
          for (final l in const ['TP9', 'AF7', 'AF8', 'TP10', 'ECG'])
            TestEdfSignal(l, 256, sine(10, 256, 512)),
        ],
      );
      final imported = importEdfBytes(
        bytes: edf,
        fallbackSubject: subject,
        sourceFileName: 'with_ecg.edf',
      );
      final summary = importSummary(imported);
      expect(summary.kept.first, 'Channels: TP9, AF7, AF8, TP10');
      expect(summary.lost.any((l) => l.contains('ECG')), isTrue);
      expect(
        importLossNotice(imported.provenance),
        'Imported from with_ecg.edf — already lost on import: '
        'dropped 1 channel(s)',
      );
    });
  });

  group('publish', () {
    test('writes recording_*.neurofeed and sqlite row', () async {
      final tmp = await Directory.systemTemp.createTemp('nf_import_pub_');
      addTearDown(() => tmp.delete(recursive: true));
      final storage = FileSystemSessionStorage(tmp);
      final cache = await Directory('${tmp.path}/cache').create();
      final sqlite = await SessionSqlite.open(cacheDirectory: cache);
      final store = RecordingStore(storage: storage, sqlite: sqlite);

      final imported = importCsvText(
        csvText: _museCsv(rows: 2, dtSeconds: 1),
        subject: subject,
        recordingId: 'pub1',
      );
      await publishImportResult(
        result: imported,
        store: store,
        storage: storage,
      );

      final hist = File('${tmp.path}/recording_pub1.neurofeed');
      expect(await hist.exists(), isTrue);
      final rows = await sqlite.listSessions();
      expect(rows.any((r) => r.id == 'pub1' && r.kind == 'recording'), isTrue);
    });
  });
}
