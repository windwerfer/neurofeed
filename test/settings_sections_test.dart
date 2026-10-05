import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/audio/calibration_clips.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/reve/model_engine.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/monitor/monitor_state.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/views/settings_sections.dart';
import 'package:neurofeed/src/views/settings_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('empty and whitespace queries match nothing', () {
    final hits = settingsSearchHits(includeAudio: false);
    expect(filterSettingsSearch(hits, ''), isEmpty);
    expect(filterSettingsSearch(hits, '   '), isEmpty);
  });

  test('every token must match, and audio is hidden off Android', () {
    final hits = settingsSearchHits(includeAudio: false);
    expect(filterSettingsSearch(hits, 'crown').map((hit) => hit.cardId), [
      'crown',
    ]);
    expect(filterSettingsSearch(hits, 'aux').map((hit) => hit.cardId), [
      'muse',
      'recording',
    ]);
    expect(filterSettingsSearch(hits, 'save folder').map((hit) => hit.cardId), [
      'folder',
    ]);
    expect(filterSettingsSearch(hits, 'calibration').map((hit) => hit.cardId), [
      'calibration',
    ]);
    expect(filterSettingsSearch(hits, 'stutter'), isEmpty);
    expect(
      filterSettingsSearch(
        settingsSearchHits(includeAudio: true),
        'stutter',
      ).map((hit) => hit.cardId),
      ['audio'],
    );
  });

  test('appearance defaults to the device and round-trips', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'nope'});
    final unknown = await Settings.load();
    expect(unknown.appearance, AppAppearance.system);
    expect(unknown.themeMode, ThemeMode.system);

    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    expect(settings.themeMode, ThemeMode.system);
    await settings.setAppearance(AppAppearance.dark);
    expect(settings.appearance, AppAppearance.dark);
    expect(settings.themeMode, ThemeMode.dark);
    await settings.setAppearance(AppAppearance.light);
    expect(settings.themeMode, ThemeMode.light);
    await settings.setAppearance(AppAppearance.system);
    expect(settings.themeMode, ThemeMode.system);
  });

  testWidgets('wide pane shows the selected section beside the list', (
    tester,
  ) async {
    final settings = (await tester.runAsync(_loadSettings))!;
    await _pump(tester, settings, const Size(1000, 800));

    expect(find.text('General'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(
      find.text('Choose a light or dark theme, or follow this device.'),
      findsOneWidget,
    );
    expect(find.text('Subject'), findsOneWidget);
    expect(find.text('Crown'), findsNothing);
    expect(find.text('Debug mode'), findsNothing);

    await tester.tap(find.byKey(const Key('settings_section_devices')));
    await tester.pump();

    expect(find.text('Muse'), findsOneWidget);
    expect(find.text('Muse Aux channels'), findsOneWidget);
    expect(find.text('Crown'), findsWidgets);
    expect(find.text('Subject'), findsNothing);
    expect(find.text('Appearance'), findsNothing);
    expect(
      find.text('Choose a light or dark theme, or follow this device.'),
      findsNothing,
    );
  });

  testWidgets('narrow pane drills into a section and back', (tester) async {
    final settings = (await tester.runAsync(_loadSettings))!;
    await _pump(tester, settings, const Size(420, 800));

    expect(find.text('Subject'), findsNothing);
    expect(find.byTooltip('Search settings'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_section_recording')));
    await tester.pump();

    expect(find.text('Save files to folder'), findsOneWidget);
    expect(find.text('Session recording'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('PPG'), 200);
    expect(find.text('PPG'), findsOneWidget);
    expect(find.text('PPG optical / fNIRS'), findsNothing);
    await tester.scrollUntilVisible(find.text('Gesture markers'), 400);
    expect(find.text('Gesture markers'), findsOneWidget);
    expect(find.text('Subject'), findsNothing);

    await tester.tap(find.byKey(const Key('settings_back')));
    await tester.pump();

    expect(find.text('Save files to folder'), findsNothing);
    expect(find.text('General'), findsOneWidget);
  });

  testWidgets('search opens a hit, and closing restores the section', (
    tester,
  ) async {
    final settings = (await tester.runAsync(_loadSettings))!;
    await _pump(tester, settings, const Size(1000, 800));

    await tester.tap(find.byKey(const Key('settings_search')));
    await tester.pump();
    expect(find.text('Type to search settings'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('settings_search_field')),
      'debug',
    );
    await tester.pump();
    expect(find.text('About · Debug mode'), findsOneWidget);
    expect(find.text('Subject'), findsNothing);

    await tester.tap(find.byKey(const Key('settings_search_close')));
    await tester.pump();
    expect(find.text('Subject'), findsOneWidget);
    expect(find.text('About · Debug mode'), findsNothing);
    expect(find.byKey(const Key('settings_search_field')), findsNothing);

    await tester.tap(find.byKey(const Key('settings_search')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('settings_search_field')),
      'crown',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('settings_hit_crown')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Crown'), findsWidgets);
    expect(find.byKey(const Key('settings_search_field')), findsNothing);
    expect(find.text('Subject'), findsNothing);
  });

  testWidgets('Appearance dark is persisted from General', (tester) async {
    final settings = (await tester.runAsync(_loadSettings))!;
    await _pump(tester, settings, const Size(1000, 800));

    await tester.tap(find.byKey(const Key('appearance_dropdown')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('appearance_dark')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(settings.appearance, AppAppearance.dark);
    expect(settings.themeMode, ThemeMode.dark);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsNothing);
  });

  test('calibration method defaults to the feature choice', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    expect(settings.calibrationMethod, CalibrationMethod.byFeature);

    SharedPreferences.setMockInitialValues({'calibration_method': 'nope'});
    final unknown = await Settings.load();
    expect(unknown.calibrationMethod, CalibrationMethod.byFeature);

    await settings.setCalibrationMethod(CalibrationMethod.alwaysStaged);
    expect(settings.calibrationMethod, CalibrationMethod.alwaysStaged);

    SharedPreferences.setMockInitialValues({
      'calibration_method': 'always_staged',
    });
    final saved = await Settings.load();
    expect(saved.calibrationMethod, CalibrationMethod.alwaysStaged);
  });

  test('muse aux defaults off and record aux defaults on', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    expect(settings.museAuxEnabled, isFalse);
    expect(settings.recordAux, isTrue);

    SharedPreferences.setMockInitialValues({'record_aux_channels': false});
    final savedOff = await Settings.load();
    expect(savedOff.recordAux, isFalse);
  });

  testWidgets('AI section shows Calibration after the guardrail engine', (
    tester,
  ) async {
    final settings = (await tester.runAsync(_loadSettings))!;
    await _pump(
      tester,
      settings,
      const Size(420, 800),
      extraOverrides: [
        modelEngineNotifierProvider.overrideWith(_QuietModelEngine.new),
        modelFolderProvider.overrideWith((ref) async => '/tmp/models'),
        modelInstalledProvider.overrideWith((ref, kind) async => false),
      ],
    );

    await tester.tap(find.byKey(const Key('settings_section_ai')));
    await tester.pump();

    expect(find.text('Guardrail AI engine'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Calibration'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.text('Default calibration method for neurofeedback.'),
      findsOneWidget,
    );
    expect(settings.calibrationMethod, CalibrationMethod.byFeature);

    final engine = tester.getTopLeft(find.text('Guardrail AI engine'));
    final calibration = tester.getTopLeft(find.text('Calibration'));
    expect(calibration.dy, greaterThan(engine.dy));

    await tester.tap(find.byKey(const Key('calibration_method_info')));
    await tester.pump();
    expect(find.textContaining('15 seconds'), findsOneWidget);
    expect(find.textContaining('30 seconds'), findsOneWidget);
    expect(find.textContaining('45 seconds'), findsOneWidget);
    expect(find.textContaining('60 seconds'), findsOneWidget);
    expect(find.textContaining('50 seconds'), findsNothing);
    expect(find.textContaining('12 seconds'), findsNothing);
    await tester.tap(find.text('Got it'));
    await tester.pump();

    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Always staged'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('calibration_method_always_staged')),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('calibration_method_always_staged')));
    await tester.pump();
    expect(settings.calibrationMethod, CalibrationMethod.alwaysStaged);
  });

  testWidgets('record AUX stays on but disabled until Muse Aux is enabled', (
    tester,
  ) async {
    final settings = (await tester.runAsync(_loadSettings))!;
    await _pump(tester, settings, const Size(420, 800));

    await tester.tap(find.byKey(const Key('settings_section_recording')));
    await tester.pump();
    await _scrollToRecordAux(tester);
    final blocked = tester.widget<SwitchListTile>(
      find.byKey(const Key('record_aux_switch')),
    );
    expect(blocked.value, isTrue);
    expect(blocked.onChanged, isNull);
    expect(find.textContaining('Turn on Muse Aux channels'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings_back')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('settings_section_devices')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('muse_aux_switch')));
    await tester.pump();
    expect(settings.museAuxEnabled, isTrue);

    await tester.tap(find.byKey(const Key('settings_back')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('settings_section_recording')));
    await tester.pump();
    await _scrollToRecordAux(tester);
    final open = tester.widget<SwitchListTile>(
      find.byKey(const Key('record_aux_switch')),
    );
    expect(open.value, isTrue);
    expect(open.onChanged, isNotNull);
  });

  test('folder change refuses an open session or recording', () {
    expect(
      folderChangeBlock(
        phase: FeedbackPhase.playing,
        unsavedSession: false,
        capture: CaptureKind.idle,
        pendingRecording: false,
      ),
      FolderChangeBlock.session,
    );
    expect(
      folderChangeBlock(
        phase: FeedbackPhase.ended,
        unsavedSession: true,
        capture: CaptureKind.idle,
        pendingRecording: false,
      ),
      FolderChangeBlock.session,
    );
    expect(
      folderChangeBlock(
        phase: FeedbackPhase.idle,
        unsavedSession: false,
        capture: CaptureKind.recording,
        pendingRecording: false,
      ),
      FolderChangeBlock.recording,
    );
    expect(
      folderChangeBlock(
        phase: FeedbackPhase.idle,
        unsavedSession: false,
        capture: CaptureKind.idle,
        pendingRecording: true,
      ),
      FolderChangeBlock.recording,
    );
    expect(
      folderChangeBlock(
        phase: FeedbackPhase.idle,
        unsavedSession: false,
        capture: CaptureKind.tmp,
        pendingRecording: false,
      ),
      FolderChangeBlock.none,
    );
    expect(
      folderChangeBlockTitle(FolderChangeBlock.session),
      'Session in progress',
    );
    expect(
      folderChangeBlockBody(FolderChangeBlock.recording),
      'Finish the recording before changing the save folder.',
    );
  });

  test('folder-change body names cache, export, and models when they move', () {
    expect(
      folderChangeMoveBody(1, 0, export: true, cache: true, models: true),
      'Move 1 session(s) and 0 recording(s), export, cache, AI models into '
      'the new folder? Choosing No leaves them in the current folder.',
    );
    expect(
      folderChangeMoveBody(0, 0, cache: true),
      'Move cache into the new folder? Choosing No leaves them in the '
      'current folder.',
    );
  });

  testWidgets('the save folder path is shown', (tester) async {
    final src = await _tempDir(tester, 'nf_ui_path_');
    final settings = (await tester.runAsync(
      () => _loadSettings(folder: src.path),
    ))!;
    await _pump(
      tester,
      settings,
      const Size(1000, 800),
      useStorageOverride: false,
    );
    await tester.tap(find.byKey(const Key('settings_section_recording')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Save files to folder'), findsOneWidget);
    expect(find.text(src.path), findsOneWidget);
    expect(find.byKey(const Key('reset_folder')), findsOneWidget);
  });

  testWidgets('nothing to move switches the folder without a dialog', (
    tester,
  ) async {
    final src = await _tempDir(tester, 'nf_ui_empty_');
    final dst = await _tempDir(tester, 'nf_ui_empty_dst_');
    await tester.runAsync(() async {
      await Directory('${src.path}/.cache').create();
      await File('${src.path}/.cache/tmp_only.neurofeed').writeAsBytes([1]);
    });
    final settings = (await tester.runAsync(
      () => _loadSettings(folder: src.path),
    ))!;
    await tester.runAsync(() async {
      final models = Directory('${src.path}/ai_models');
      if (await models.exists()) await models.delete(recursive: true);
    });
    await _pump(
      tester,
      settings,
      const Size(1000, 800),
      pickFolder: () async => dst.path,
      useStorageOverride: false,
    );
    await tester.tap(find.byKey(const Key('settings_section_recording')));
    await tester.pump();
    await tester.tap(find.text('Save files to folder'));
    await _flushRealIo(tester);

    expect(find.text('Move existing files?'), findsNothing);
    expect(settings.sessionFolder, dst.path);
    expect(File('${src.path}/.cache/tmp_only.neurofeed').existsSync(), isFalse);
  });

  testWidgets('a session file opens a Move dialog and No leaves the file', (
    tester,
  ) async {
    final src = await _tempDir(tester, 'nf_ui_move_');
    final dst = await _tempDir(tester, 'nf_ui_move_dst_');
    await tester.runAsync(
      () => File('${src.path}/session_a.neurofeed').writeAsBytes([1, 2, 3]),
    );
    final settings = (await tester.runAsync(
      () => _loadSettings(folder: src.path),
    ))!;
    await _pump(
      tester,
      settings,
      const Size(1000, 800),
      pickFolder: () async => dst.path,
      useStorageOverride: false,
    );
    await tester.tap(find.byKey(const Key('settings_section_recording')));
    await tester.pump();
    await tester.tap(find.text('Save files to folder'));
    await _flushRealIo(tester);

    expect(find.text('Move existing files?'), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);
    expect(find.text('No'), findsOneWidget);
    await tester.tap(find.text('No'));
    await _flushRealIo(tester);

    expect(settings.sessionFolder, dst.path);
    expect(File('${src.path}/session_a.neurofeed').existsSync(), isTrue);
    expect(File('${dst.path}/session_a.neurofeed').existsSync(), isFalse);
  });

  testWidgets('Move copies the session and Reset asks before moving', (
    tester,
  ) async {
    final src = await _tempDir(tester, 'nf_ui_reset_');
    final picked = await _tempDir(tester, 'nf_ui_reset_pick_');
    final fallback = await _tempDir(tester, 'nf_ui_reset_def_');
    await tester.runAsync(
      () => File('${src.path}/session_a.neurofeed').writeAsBytes([4, 5]),
    );
    final settings = (await tester.runAsync(
      () => _loadSettings(folder: src.path),
    ))!;
    await _pump(
      tester,
      settings,
      const Size(1000, 800),
      pickFolder: () async => picked.path,
      defaultFolder: () async => fallback,
      useStorageOverride: false,
    );
    await tester.tap(find.byKey(const Key('settings_section_recording')));
    await tester.pump();
    await tester.tap(find.text('Save files to folder'));
    await _flushRealIo(tester);
    await tester.tap(find.byKey(const Key('folder_move_confirm')));
    await _flushRealIo(tester, rounds: 16);

    expect(settings.sessionFolder, picked.path);
    expect(File('${picked.path}/session_a.neurofeed').existsSync(), isTrue);
    expect(File('${src.path}/session_a.neurofeed').existsSync(), isFalse);

    await tester.runAsync(
      () => File('${picked.path}/recording_b.neurofeed').writeAsBytes([6]),
    );
    await tester.tap(find.byKey(const Key('reset_folder')));
    await _flushRealIo(tester);
    expect(find.text('Move existing files?'), findsOneWidget);
    await tester.tap(find.text('No'));
    await _flushRealIo(tester);

    expect(settings.sessionFolder, isNull);
    expect(File('${picked.path}/recording_b.neurofeed').existsSync(), isTrue);
    expect(
      File('${fallback.path}/recording_b.neurofeed').existsSync(),
      isFalse,
    );
  });
}

Future<Directory> _tempDir(WidgetTester tester, String prefix) async {
  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp(prefix),
  ))!;
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

Future<void> _flushRealIo(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  }
  await tester.pump();
}

Future<Settings> _loadSettings({String? folder}) async {
  SharedPreferences.setMockInitialValues({
    if (folder != null) 'session_folder': folder,
  });
  return Settings.load();
}

Future<void> _scrollToRecordAux(WidgetTester tester) {
  return tester.scrollUntilVisible(
    find.byKey(const Key('record_aux_switch')),
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
}

class _QuietModelEngine extends ModelEngineNotifier {
  @override
  ModelEngineState build() => const ModelEngineNotInstalled();
}

Future<void> _pump(
  WidgetTester tester,
  Settings settings,
  Size size, {
  Future<String?> Function()? pickFolder,
  Future<Directory> Function()? defaultFolder,
  bool useStorageOverride = true,
  List<Override> extraOverrides = const [],
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        if (useStorageOverride)
          sessionStorageProvider.overrideWith(
            (ref) async => FileSystemSessionStorage(Directory.systemTemp),
          ),
        ...extraOverrides,
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SettingsView(
            pickFolderForTest: pickFolder,
            defaultFolderForTest: defaultFolder,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
