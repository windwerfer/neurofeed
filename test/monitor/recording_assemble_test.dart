import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/monitor/monitor_controller.dart';
import 'package:muse_ml/src/monitor/monitor_providers.dart';
import 'package:muse_ml/src/monitor/monitor_state.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';
import 'package:muse_ml/src/rust/frb_generated.dart';
import 'package:muse_ml/src/session_v5/placeholder_webp.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

final String _rustLibPath =
    '${Directory.current.path}/rust/target/debug/librust_lib_muse_ml.so';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_rustLibPath));
  });

  late Directory history;
  late Directory scratch;
  late Settings settings;
  late AppStateNotifier app;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await Settings.load();
    history = await Directory.systemTemp.createTemp('muse_rec_hist_');
    final storage = FileSystemSessionStorage(history);
    scratch = scratchDirectory(storage);
    app = AppStateNotifier.forTest(settings);
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        appStateProvider.overrideWith((ref) => app),
        sessionStorageProvider.overrideWith((ref) => storage),
        monitorControllerProvider.overrideWith(() => MonitorController()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    if (await history.exists()) {
      await history.delete(recursive: true);
    }
  });

  Future<void> settle() =>
      container.read(monitorControllerProvider.notifier).pendingOps;

  List<File> scratchNamed(String prefix) {
    if (!scratch.existsSync()) return const [];
    return scratch
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith(prefix))
        .toList();
  }

  test(
    'Stop assembles recording_\$ts.muse.feedback with placeholder WebP',
    () async {
      container.read(monitorControllerProvider);
      app.debugSetConnected();
      await settle();
      final notifier = container.read(monitorControllerProvider.notifier);
      await notifier.startRecording();
      await settle();

      final file = await notifier.stopRecording(promptSave: true);
      await settle();
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
      expect(
        file.uri.pathSegments.last,
        matches(RegExp(r'^recording_\d+\.muse\.feedback$')),
      );
      expect(file.lengthSync(), greaterThan(placeholderWebP.length));

      final head = v5ParseHead(
        bytes: Uint8List.fromList(file.readAsBytesSync()),
      );
      final meta = jsonDecode(utf8.decode(head.metadataJson)) as Map;
      expect(meta['kind'], 'recording');
      expect(container.read(monitorControllerProvider).kind, CaptureKind.idle);
      expect(
        container.read(monitorControllerProvider).pendingScratchPath,
        file.path,
      );
      expect(
        scratchNamed('recording_').where((f) => f.path.endsWith('.raw')),
        isEmpty,
      );
    },
  );

  test('Discard deletes scratch; Save copies to history root', () async {
    container.read(monitorControllerProvider);
    app.debugSetConnected();
    await settle();
    final notifier = container.read(monitorControllerProvider.notifier);
    await notifier.startRecording();
    await settle();
    final scratchV5 = await notifier.stopRecording(promptSave: true);
    await settle();
    expect(scratchV5, isNotNull);

    await notifier.discardPendingRecording();
    await settle();
    expect(scratchV5!.existsSync(), isFalse);
    expect(
      container.read(monitorControllerProvider).pendingScratchPath,
      isNull,
    );
    expect(container.read(monitorControllerProvider).kind, CaptureKind.tmp);

    await notifier.startRecording();
    await settle();
    final saved = await notifier.stopRecording(promptSave: true);
    await settle();
    final name = saved!.uri.pathSegments.last;
    await notifier.savePendingRecording();
    await settle();
    expect(saved.existsSync(), isFalse);
    final published = File('${history.path}/$name');
    expect(published.existsSync(), isTrue);
    expect(container.read(monitorControllerProvider).kind, CaptureKind.tmp);
  });
}
