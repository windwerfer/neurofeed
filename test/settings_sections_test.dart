import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
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
}

Future<Settings> _loadSettings() async {
  SharedPreferences.setMockInitialValues({});
  return Settings.load();
}

Future<void> _pump(WidgetTester tester, Settings settings, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        sessionStorageProvider.overrideWith(
          (ref) async => FileSystemSessionStorage(Directory.systemTemp),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: SettingsView())),
    ),
  );
  await tester.pump();
}
