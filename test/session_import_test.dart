import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/import/csv_import.dart';
import 'package:neurofeed/src/feedback/session_chart_data.dart';
import 'package:neurofeed/src/feedback/import/edf_import.dart';
import 'package:neurofeed/src/feedback/import/import_types.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/feedback/session_sqlite.dart';
import 'package:neurofeed/src/monitor/recording/recording_store.dart';
import 'package:neurofeed/src/feedback/import/publish_import.dart';
import 'package:neurofeed/src/rust/api/edf_export.dart';
import 'package:neurofeed/src/rust/api/muse.dart';
import 'package:neurofeed/src/rust/api/session_format.dart';
import 'package:neurofeed/src/rust/frb_generated.dart';
import 'package:neurofeed/src/settings.dart';

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
        for (var el = 0; el < 2; el++) {
          events.addAll(
            encodeSessionEvent(
              event: MuseEventDto.eeg(
                EegDto(
                  index: pkt,
                  electrode: el,
                  timestamp: ts,
                  samples: Float64List.fromList(
                    List<double>.filled(12, el == 0 ? 50.0 : -50.0),
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
        channelLabels: const ['TP9', 'AF7'],
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
            EdfExportAnnotation(onsetSeconds: 0.5, text: 'double_blink'),
          ],
        ),
      );

      final decoded = decodeEdfImport(bytes: edf);
      expect(decoded.signals.length, 2);
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
      expect(device['channelLabels'], ['TP9', 'AF7']);
      expect(device['model'], 'imported');

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
    });
  });

  group('Mind Monitor CSV', () {
    final oneHzCsv = '''
TimeStamp,Delta_TP9,Delta_AF7,Delta_AF8,Delta_TP10,Theta_TP9,Theta_AF7,Theta_AF8,Theta_TP10,Alpha_TP9,Alpha_AF7,Alpha_AF8,Alpha_TP10,Beta_TP9,Beta_AF7,Beta_AF8,Beta_TP10,Gamma_TP9,Gamma_AF7,Gamma_AF8,Gamma_TP10,RAW_TP9,RAW_AF7,RAW_AF8,RAW_TP10
2026-09-25 10:00:00.000,1.1,1.2,1.3,1.4,2.1,2.2,2.3,2.4,3.1,3.2,3.3,3.4,4.1,4.2,4.3,4.4,5.1,5.2,5.3,5.4,100.0,101.0,102.0,103.0
2026-09-25 10:00:01.000,1.1,1.2,1.3,1.4,2.1,2.2,2.3,2.4,3.1,3.2,3.3,3.4,4.1,4.2,4.3,4.4,5.1,5.2,5.3,5.4,110.0,111.0,112.0,113.0
2026-09-25 10:00:02.000,1.1,1.2,1.3,1.4,2.1,2.2,2.3,2.4,3.1,3.2,3.3,3.4,4.1,4.2,4.3,4.4,5.1,5.2,5.3,5.4,120.0,121.0,122.0,123.0
''';

    test('detects 1 Hz subset and builds NFED6', () {
      final parsed = parseMindMonitorCsv(oneHzCsv);
      expect(parsed.rate, CsvRecordingRate.oneHz);
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
      expect(data.bands.length, greaterThan(0));
      expect(data.eeg.length, greaterThan(0));
      // 4 electrodes × 3 seconds of 1-sample packets.
      expect(data.eeg.length, 12);
    });

    test('Constant-rate RAW packs into EEG packets', () {
      final buf = StringBuffer(
        'TimeStamp,RAW_TP9,RAW_AF7,Delta_TP9,Delta_AF7,Theta_TP9,Theta_AF7,'
        'Alpha_TP9,Alpha_AF7,Beta_TP9,Beta_AF7,Gamma_TP9,Gamma_AF7\n',
      );
      // ~256 Hz for 0.1 s → 26 rows; bands only on first of each 10.
      final start = DateTime(2026, 9, 25, 10, 0, 0);
      for (var i = 0; i < 26; i++) {
        final t = start.add(Duration(microseconds: (i * 1e6 / 256).round()));
        final ts =
            '${t.year.toString().padLeft(4, '0')}-'
            '${t.month.toString().padLeft(2, '0')}-'
            '${t.day.toString().padLeft(2, '0')} '
            '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}:'
            '${t.second.toString().padLeft(2, '0')}.'
            '${t.millisecond.toString().padLeft(3, '0')}';
        final band = i % 10 == 0 ? '1.0,1.1,2.0,2.1,3.0,3.1,4.0,4.1,5.0,5.1' : ',,,,,,,,,';
        buf.writeln('$ts,${800 + i}.0,${900 + i}.0,$band');
      }
      final parsed = parseMindMonitorCsv(buf.toString());
      expect(parsed.rate, CsvRecordingRate.constant);
      expect(parsed.medianDeltaSeconds, lessThan(0.01));

      final imported = importCsvText(
        csvText: buf.toString(),
        subject: subject,
        recordingId: 'csv_const',
      );
      final raw = extractRaw(bytes: imported.containerBytes);
      final data = sessionParseBody(bytes: raw);
      expect(data.eeg.length, greaterThan(0));
      final samples = data.eeg
          .where((r) => r.electrode == 0)
          .fold<int>(0, (n, r) => n + r.samples.length);
      expect(samples, 26);
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

    test('optional fuller headers stream ACC/Gyro and map Elements doubles', () {
      final csv = '''
TimeStamp,Delta_TP9,Theta_TP9,Alpha_TP9,Beta_TP9,Gamma_TP9,RAW_TP9,Accelerometer_X,Accelerometer_Y,Accelerometer_Z,Gyro_X,Gyro_Y,Gyro_Z,Battery,Elements
2026-09-25 10:00:00.000,1,2,3,4,5,100,0.1,0.2,0.9,1.0,2.0,3.0,0.9,Blink
2026-09-25 10:00:01.000,1,2,3,4,5,101,0.1,0.2,0.9,1.0,2.0,3.0,0.9,Blink
2026-09-25 10:00:02.000,1,2,3,4,5,102,0.1,0.2,0.9,1.0,2.0,3.0,0.9,
''';
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
      expect(
        imported.warnings.any((w) => w.message.contains('not yet imported')),
        isFalse,
      );
      final streams = imported.metadataJson['streams'] as Map;
      expect((streams['imu'] as Map)['enabled'], isTrue);
      final anns = imported.metadataJson['annotations'] as List;
      expect(
        anns.any((a) => (a as Map)['type'] == 'double_blink'),
        isTrue,
      );
    });

    test('Constant CSV with ACC enables imu stream', () {
      final buf = StringBuffer(
        'TimeStamp,RAW_TP9,Accelerometer_X,Accelerometer_Y,Accelerometer_Z,'
        'Delta_TP9,Theta_TP9,Alpha_TP9,Beta_TP9,Gamma_TP9\n',
      );
      final start = DateTime(2026, 9, 25, 10, 0, 0);
      for (var i = 0; i < 26; i++) {
        final t = start.add(Duration(microseconds: (i * 1e6 / 256).round()));
        final ts =
            '${t.year.toString().padLeft(4, '0')}-'
            '${t.month.toString().padLeft(2, '0')}-'
            '${t.day.toString().padLeft(2, '0')} '
            '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}:'
            '${t.second.toString().padLeft(2, '0')}.'
            '${t.millisecond.toString().padLeft(3, '0')}';
        final band = i % 10 == 0 ? '1.0,2.0,3.0,4.0,5.0' : ',,,,';
        buf.writeln('$ts,${800 + i}.0,0.1,0.2,0.98,$band');
      }
      final imported = importCsvText(
        csvText: buf.toString(),
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


  group('publish', () {
    test('writes recording_*.neurofeed and sqlite row', () async {
      final tmp = await Directory.systemTemp.createTemp('nf_import_pub_');
      addTearDown(() => tmp.delete(recursive: true));
      final storage = FileSystemSessionStorage(tmp);
      final cache = await Directory('${tmp.path}/cache').create();
      final sqlite = await SessionSqlite.open(cacheDirectory: cache);
      final store = RecordingStore(storage: storage, sqlite: sqlite);

      final imported = importCsvText(
        csvText: '''
TimeStamp,Delta_TP9,Theta_TP9,Alpha_TP9,Beta_TP9,Gamma_TP9,RAW_TP9
2026-09-25 10:00:00.000,1,2,3,4,5,100
2026-09-25 10:00:01.000,1,2,3,4,5,101
''',
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
