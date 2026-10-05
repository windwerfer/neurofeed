import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
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
    expect(filterSettingsSearch(hits, 'save folder').map((hit) => hit.cardId), [
      'folder',
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

Future<void> _pump(
  WidgetTester tester,
  Settings settings,
  Size size, {
  Future<String?> Function()? pickFolder,
  Future<Directory> Function()? defaultFolder,
  bool useStorageOverride = true,
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
