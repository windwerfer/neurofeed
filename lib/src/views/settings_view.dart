import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/connect_source.dart';
import 'package:neurofeed/src/connection_provider.dart';
import 'package:neurofeed/src/device_type_switch.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';
import 'package:neurofeed/src/feedback/session_store.dart';
import 'package:neurofeed/src/reve/reve_card.dart';
import 'package:neurofeed/src/rust/api/device_config.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/views/about_view.dart';
import 'package:neurofeed/src/views/music_settings_panel.dart';
import 'package:neurofeed/src/views/settings_sections.dart';

/// Folder-change confirm copy. Counts both `session_` and `recording_` prefixes.
String folderChangeMoveBody(int sessions, int recordings) =>
    'Move $sessions session(s) and $recordings recording(s) into the new '
    'folder? Choosing No leaves them in the current folder.';

/// Settings view. Wide panes keep a section list beside the cards. Narrow
/// panes show the list, then one section.
class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  SettingsSection _section = SettingsSection.general;
  bool _showDetail = false;
  bool _searching = false;
  SettingsSection _sectionBeforeSearch = SettingsSection.general;
  bool _detailBeforeSearch = false;
  String? _pendingScrollId;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _cardKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  GlobalKey _cardKey(String id) => _cardKeys.putIfAbsent(id, GlobalKey.new);

  void _openSearch() {
    _searchController.clear();
    setState(() {
      _sectionBeforeSearch = _section;
      _detailBeforeSearch = _showDetail;
      _searching = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searching) _searchFocus.requestFocus();
    });
  }

  void _closeSearch({bool restore = true}) {
    _searchController.clear();
    setState(() {
      _searching = false;
      if (restore) {
        _section = _sectionBeforeSearch;
        _showDetail = _detailBeforeSearch;
      }
      _pendingScrollId = null;
    });
  }

  void _selectSection(SettingsSection section) {
    _searchController.clear();
    setState(() {
      _searching = false;
      _section = section;
      _showDetail = true;
      _pendingScrollId = null;
    });
  }

  void _openHit(SettingsSearchHit hit) {
    _searchController.clear();
    setState(() {
      _searching = false;
      _section = hit.section;
      _showDetail = true;
      _pendingScrollId = hit.cardId;
    });
    _scheduleScroll();
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = _pendingScrollId;
      if (id == null) return;
      final target = _cardKeys[id]?.currentContext;
      if (target == null) return;
      _pendingScrollId = null;
      Scrollable.ensureVisible(
        target,
        alignment: 0.05,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<String?> _pickFolder() async {
    if (Platform.isAndroid) {
      return SafSessionStorage.pickFolder();
    }
    final dir = await getDirectoryPath(
      initialDirectory: null,
      confirmButtonText: 'Choose this folder',
    );
    return dir;
  }

  Future<void> _applyFolder(
    WidgetRef ref,
    String? folder, {
    required bool migrate,
  }) async {
    if (folder == null) {
      return;
    }
    final settings = ref.read(settingsProvider);
    final current = ref.read(sessionStorageProvider);
    final oldStorage = current.valueOrNull;

    if (migrate && oldStorage != null) {
      final store = await ref.read(sessionStoreProvider.future);
      await store.moveAllTo(resolveStorageFromFolder(folder));
    }

    await settings.setSessionFolder(folder);
    ref.invalidate(sessionStorageProvider);
    ref.invalidate(sessionStoreProvider);
    ref.invalidate(sessionListProvider);
  }

  Future<void> _resetFolder(WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    await settings.clearSessionFolder();
    ref.invalidate(sessionStorageProvider);
    ref.invalidate(sessionStoreProvider);
    ref.invalidate(sessionListProvider);
  }

  Future<void> _onPickFolder(
    WidgetRef ref,
    BuildContext context,
    Settings settings,
  ) async {
    final folder = await _pickFolder();
    if (folder == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final current = ref.read(sessionStorageProvider);
    final existing = current.valueOrNull;
    final counted = existing == null
        ? (sessions: 0, recordings: 0)
        : countHistoryContainers(await existing.listFiles());
    if (!context.mounted) {
      return;
    }
    final total = counted.sessions + counted.recordings;
    final migrate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy existing files?'),
        content: Text(
          total > 0
              ? folderChangeMoveBody(counted.sessions, counted.recordings)
              : 'Choose this folder for saved files?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(total > 0 ? 'Copy' : 'Yes'),
          ),
        ],
      ),
    );
    if (migrate != null) {
      await _applyFolder(ref, folder, migrate: migrate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= kSettingsRailBreakpoint;
        if (_searching) return _searchScaffold(wide: wide);
        if (!wide && !_showDetail) return _narrowIndex();
        if (!wide) return _narrowDetail(settings);
        return _wide(settings);
      },
    );
  }

  Widget _searchIcon() {
    return IconButton(
      key: const Key('settings_search'),
      tooltip: 'Search settings',
      onPressed: _openSearch,
      icon: const Icon(Icons.search),
    );
  }

  Widget _sectionTile(
    SettingsSection section, {
    required bool selected,
    required bool showChevron,
  }) {
    return ListTile(
      key: Key('settings_section_${section.name}'),
      selected: selected,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Text(settingsSectionLabel(section)),
      trailing: showChevron ? const Icon(Icons.chevron_right) : null,
      onTap: () => _selectSection(section),
    );
  }

  Widget _narrowIndex() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings', style: theme.textTheme.headlineSmall),
        Align(alignment: Alignment.centerLeft, child: _searchIcon()),
        for (final section in settingsSections)
          _sectionTile(section, selected: false, showChevron: true),
      ],
    );
  }

  Widget _narrowDetail(Settings settings) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('settings_back'),
              tooltip: 'Back',
              onPressed: () => setState(() => _showDetail = false),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                settingsSectionLabel(_section),
                style: theme.textTheme.titleLarge,
              ),
            ),
            _searchIcon(),
          ],
        ),
        Expanded(child: _sectionBody(settings)),
      ],
    );
  }

  Widget _wide(Settings settings) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text('Settings', style: theme.textTheme.headlineSmall),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: kSettingsRailWidth, child: _rail(selected: true)),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: theme.dividerColor,
              ),
              Expanded(child: _sectionBody(settings)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rail({required bool selected, bool showSearch = true}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      children: [
        if (showSearch)
          Align(alignment: Alignment.centerLeft, child: _searchIcon()),
        for (final section in settingsSections)
          _sectionTile(
            section,
            selected: selected && section == _section,
            showChevron: false,
          ),
      ],
    );
  }

  Widget _searchScaffold({required bool wide}) {
    final theme = Theme.of(context);
    final hits = filterSettingsSearch(
      settingsSearchHits(includeAudio: Platform.isAndroid),
      _searchController.text,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 0),
          child: Row(
            children: [
              IconButton(
                key: const Key('settings_search_close'),
                tooltip: 'Close search',
                onPressed: () => _closeSearch(),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(child: _searchField()),
            ],
          ),
        ),
        Expanded(
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: kSettingsRailWidth,
                      child: _rail(selected: true, showSearch: false),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: theme.dividerColor,
                    ),
                    Expanded(child: _searchResults(hits)),
                  ],
                )
              : _searchResults(hits),
        ),
      ],
    );
  }

  Widget _searchField() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _closeSearch(),
      },
      child: TextField(
        key: const Key('settings_search_field'),
        controller: _searchController,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search settings',
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: _searchController.clear,
                  icon: const Icon(Icons.close),
                ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _searchResults(List<SettingsSearchHit> hits) {
    final theme = Theme.of(context);
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return Center(
        child: Text(
          'Type to search settings',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (hits.isEmpty) {
      return Center(
        child: Text(
          'No matching settings',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final hit in hits)
          ListTile(
            key: Key('settings_hit_${hit.cardId}'),
            title: Text(hit.resultLabel),
            onTap: () => _openHit(hit),
          ),
      ],
    );
  }

  Widget _sectionBody(Settings settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _sectionCards(settings),
    );
  }

  Widget _keyed(String id, Widget child) {
    return RepaintBoundary(key: _cardKey(id), child: child);
  }

  List<Widget> _sectionCards(Settings settings) {
    switch (_section) {
      case SettingsSection.general:
        return [
          _keyed(
            'appearance',
            _AppearanceCard(
              appearance: settings.appearance,
              onChanged: (value) {
                settings.setAppearance(value);
              },
            ),
          ),
          const SizedBox(height: 16),
          _keyed('subject', _SubjectCard(settings: settings)),
          const SizedBox(height: 16),
          _keyed('music', _MusicCard(settings: settings)),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 16),
            _keyed('audio', _AudioCard(settings: settings)),
          ],
        ];
      case SettingsSection.devices:
        return [
          _keyed(
            'crown',
            _CrownCard(
              qualitySource: settings.crownQualitySource,
              onQualitySource: (source) async {
                await settings.setCrownQualitySource(source);
                if (mounted) setState(() {});
              },
            ),
          ),
        ];
      case SettingsSection.ai:
        return [_keyed('ai', const AiEngineCard())];
      case SettingsSection.recording:
        final storage = ref.watch(sessionStorageProvider);
        final streams = settings.recordStreams;
        Future<void> toggle(RecordingStream stream, bool on) async {
          final next = {...streams};
          if (on) {
            next.add(stream);
          } else {
            next.remove(stream);
          }
          await settings.setRecordStreams(next);
          if (mounted) setState(() {});
        }

        return [
          _keyed('folder', _saveFolderCard(settings, storage)),
          const SizedBox(height: 16),
          _keyed(
            'recording',
            _RecordingCard(
              streams: streams,
              onToggle: toggle,
              recordAux: settings.recordAux,
              onRecordAux: (on) async {
                await settings.setRecordAux(on);
                if (mounted) setState(() {});
              },
            ),
          ),
          const SizedBox(height: 16),
          _keyed('gestures', _GesturesCard(settings: settings)),
        ];
      case SettingsSection.about:
        return [
          _keyed('about', const _AboutCard()),
          const SizedBox(height: 40),
          _keyed('debug', _DebugCard(settings: settings)),
        ];
    }
  }

  Widget _saveFolderCard(
    Settings settings,
    AsyncValue<SessionStorage> storage,
  ) {
    final theme = Theme.of(context);
    final folder = settings.sessionFolder;
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Save files to folder'),
              subtitle: storage.maybeWhen(
                data: (s) =>
                    Text(s.displayName, style: theme.textTheme.bodySmall),
                orElse: () => const Text('Resolving storage…'),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _onPickFolder(ref, context, settings),
            ),
            const Divider(height: 24),
            Text(
              folder == null
                  ? 'Using the default folder. Tap to choose where '
                        'session and recording files are stored.'
                  : 'Files are saved to the folder above. Cache/temp '
                        'files live in a hidden .cache subfolder.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (folder != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _resetFolder(ref),
                icon: const Icon(Icons.autorenew),
                label: const Text('Reset to default folder'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({required this.appearance, required this.onChanged});

  final AppAppearance appearance;
  final ValueChanged<AppAppearance> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Appearance', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Choose a light or dark theme, or follow this device.',
                    style: muted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            DropdownButtonHideUnderline(
              child: DropdownButton<AppAppearance>(
                key: const Key('appearance_dropdown'),
                value: appearance,
                borderRadius: BorderRadius.circular(8),
                onChanged: (value) {
                  if (value != null) onChanged(value);
                },
                items: const [
                  DropdownMenuItem(
                    key: Key('appearance_system'),
                    value: AppAppearance.system,
                    child: Text('System'),
                  ),
                  DropdownMenuItem(
                    key: Key('appearance_light'),
                    value: AppAppearance.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(
                    key: Key('appearance_dark'),
                    value: AppAppearance.dark,
                    child: Text('Dark'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anonymous subject identity: stable id (read-only) + optional nickname.
class _SubjectCard extends StatefulWidget {
  const _SubjectCard({required this.settings});

  final Settings settings;

  @override
  State<_SubjectCard> createState() => _SubjectCardState();
}

class _SubjectCardState extends State<_SubjectCard> {
  late final TextEditingController _nickname;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(
      text: widget.settings.subjectNickname ?? '',
    );
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _saveNickname() async {
    await widget.settings.setSubjectNickname(_nickname.text);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = widget.settings.subjectId;

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.badge_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Subject', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Anonymous id used in saved session files. Nickname is optional '
              'and never filled from the id.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fingerprint),
              title: const Text('Subject id'),
              subtitle: SelectableText(
                id.isEmpty ? '(not generated)' : id,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            TextField(
              controller: _nickname,
              decoration: const InputDecoration(
                labelText: 'Nickname (optional)',
                hintText: 'Display name for this device',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onEditingComplete: _saveNickname,
              onSubmitted: (_) => _saveNickname(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _saveNickname,
                child: const Text('Save nickname'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// App credits — bundled third-party notices opened as a sub-screen.
class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('About', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Third-party notices'),
              subtitle: Text(
                'Credits and licenses for the libraries, model engine, and '
                'bundled audio this app includes.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AboutView())),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gesture detection options: eye up/down markers (experimental) and whether
/// gesture markers are persisted into saved feedback sessions.
class _GesturesCard extends StatefulWidget {
  const _GesturesCard({required this.settings});

  final Settings settings;

  @override
  State<_GesturesCard> createState() => _GesturesCardState();
}

class _GesturesCardState extends State<_GesturesCard> {
  late bool _eye;
  late bool _persist;

  @override
  void initState() {
    super.initState();
    _eye = widget.settings.eyeMarkersEnabled;
    _persist = widget.settings.markersInFeedbackEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Gesture markers', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Blink twice, clench twice, or look up/down to drop a marker '
              'during a feedback session. Detection runs in Rust at 1 Hz.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.visibility_outlined),
              title: const Text('Eye up/down markers'),
              subtitle: Text(
                'Experimental on a 4-electrode Muse — eye direction is '
                'estimated from frontal-vs-rear EEG. Off by default.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: _eye,
              onChanged: (on) async {
                setState(() => _eye = on);
                await widget.settings.setEyeMarkersEnabled(on);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.bookmark_add_outlined),
              title: const Text('Add markers to feedback sessions'),
              subtitle: Text(
                'Persist double-blink / double-clench / eye markers in the '
                'session metadata (.neurofeed). Detection still runs when '
                'off, markers are just not saved.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: _persist,
              onChanged: (on) async {
                setState(() => _persist = on);
                await widget.settings.setMarkersInFeedbackEnabled(on);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Music-feedback options: the folder that plays through the reward-driven
/// low-pass filter, the cutoff range it sweeps, and the mapping polarity.
/// The options themselves live in the shared [MusicSettingsPanel] (also used
/// by the feedback-session music bubble).
class _MusicCard extends ConsumerStatefulWidget {
  const _MusicCard({required this.settings});

  final Settings settings;

  @override
  ConsumerState<_MusicCard> createState() => _MusicCardState();
}

class _MusicCardState extends ConsumerState<_MusicCard> {
  late final MusicSettingsPanel _panel;

  @override
  void initState() {
    super.initState();
    _panel = MusicSettingsPanel(settings: widget.settings);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.music_note_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Music feedback', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Play a user-provided music folder through a low-pass filter '
              'whose cutoff follows your reward. Higher scores open the '
              'filter (brighter music) unless inverted.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            _panel,
          ],
        ),
      ),
    );
  }
}

/// Audio engine profile (Android only): conservative mode trades ~0.1 s of
/// output latency for fewer dropouts when the CPU is busy — e.g. music
/// feedback while the AI sleep guardrail scores every second. The card is not
/// shown on other platforms because the profile is a no-op there.
class _AudioCard extends ConsumerWidget {
  const _AudioCard({required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.volume_down_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Audio', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  const Expanded(child: Text('Reduce audio stutter')),
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 20),
                    tooltip: 'What does this do?',
                    onPressed: () => _showInfo(context),
                  ),
                ],
              ),
              subtitle: const Text(
                'Prevents dropouts — adds ~0.1 s sound delay',
              ),
              trailing: Switch(
                value: settings.audioStableMode,
                onChanged: (on) => settings.setAudioStableMode(on),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reduce audio stutter'),
        content: const Text(
          'The audio engine normally uses the lowest-latency path (AAudio '
          'MMAP on Android). When the CPU is busy — e.g. music feedback '
          'while the AI sleep guardrail scores every second — that tight '
          'schedule can make the sound stutter.\n\n'
          'This setting gives the audio engine more headroom so dropouts are '
          'rare, at the cost of about 0.1 s of sound latency: chimes, music, '
          'and warnings all sound slightly later.\n\n'
          'Turn it off if your device is fast and you prefer snappier '
          'feedback.\n\n'
          'Applies from the next session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

/// Debug-only switch: Simulator in the connect dropdown.
class _DebugCard extends ConsumerWidget {
  const _DebugCard({required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bug_report_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Debug mode', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Adds Simulator to the connect dropdown. Simulated headsets '
              'run on this device — no Bluetooth or OSC.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.science_outlined),
              title: const Text('Debug mode'),
              subtitle: Text(
                'Simulator catalog and sim:* autoconnect.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: settings.enableSimulatedDevices,
              onChanged: (on) async {
                final notifier = ref.read(appStateProvider.notifier);
                if (!on &&
                    ref.read(appStateProvider).connectSource ==
                        ConnectSource.simulator) {
                  final block = ref.read(deviceTypeSwitchBlockProvider);
                  if (block != DeviceTypeSwitchBlock.none) {
                    final app = ref.read(appStateProvider);
                    final name = app.status.connected
                        ? app.status.name
                        : (app.connectingTo ?? '');
                    final ok = await confirmDeviceTypeChange(
                      context,
                      block: block,
                      deviceName: name,
                      nextTypeLabel: ConnectSource.muse.displayName,
                    );
                    if (!ok || !context.mounted) return;
                  }
                  final switched = await notifier.onDebugModeChanged(false);
                  if (!switched || !context.mounted) return;
                }
                await settings.setEnableSimulatedDevices(on);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Neurosity Crown options.
class _CrownCard extends StatelessWidget {
  const _CrownCard({
    required this.qualitySource,
    required this.onQualitySource,
  });

  final QualitySource qualitySource;
  final void Function(QualitySource source) onQualitySource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('Crown', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Signal quality source for the pad dots, recordings and which '
              'pads feed the training features. Applies on the next connect.',
              style: muted,
            ),
            const Divider(height: 24),
            RadioGroup<QualitySource>(
              groupValue: qualitySource,
              onChanged: (v) {
                if (v != null) onQualitySource(v);
              },
              child: Column(
                children: [
                  RadioListTile<QualitySource>(
                    key: const Key('crown_quality_source_crown'),
                    contentPadding: EdgeInsets.zero,
                    value: QualitySource.crown,
                    title: const Text('Crown'),
                    subtitle: Text(
                      "The Crown's own per-pad signal quality, averaged each "
                      'second. Seconds without it use the app score.',
                      style: muted,
                    ),
                  ),
                  RadioListTile<QualitySource>(
                    key: const Key('crown_quality_source_app'),
                    contentPadding: EdgeInsets.zero,
                    value: QualitySource.app,
                    title: const Text('App'),
                    subtitle: Text(
                      "NeuroFeed's own score from the raw signal (same as Muse).",
                      style: muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which sensor data streams get persisted into each session file.
class _RecordingCard extends StatelessWidget {
  const _RecordingCard({
    required this.streams,
    required this.onToggle,
    required this.recordAux,
    required this.onRecordAux,
  });

  final Set<RecordingStream> streams;
  final void Function(RecordingStream stream, bool on) onToggle;
  final bool recordAux;
  final void Function(bool on) onRecordAux;

  static const Map<RecordingStream, (String, String)> _labels = {
    RecordingStream.eeg: (
      'Raw EEG samples',
      'Full-resolution waveforms per electrode (largest data)',
    ),
    RecordingStream.bands: (
      'Band powers',
      'Delta/theta/alpha/beta/gamma power per channel (ATR uses this)',
    ),
    RecordingStream.ppg: (
      'PPG optical / fNIRS',
      'Raw light channels (incl. Athena fNIRS optical data)',
    ),
    RecordingStream.pulse: (
      'Pulse / heart rate',
      'BPM estimate derived from PPG',
    ),
    RecordingStream.spo2: (
      'Blood oxygen (SpO2)',
      'Estimated SpO2 % from PPG IR + Red channels',
    ),
    RecordingStream.imu: (
      'Accelerometer + gyroscope',
      'Raw 3-axis motion and gyro samples',
    ),
    RecordingStream.movement: (
      'Movement score',
      'Derived motion magnitude from accelerometer',
    ),
    RecordingStream.peakAlpha: (
      'Peak alpha',
      'Dominant alpha frequency/power (parabolic-interpolated)',
    ),
    RecordingStream.telemetry: (
      'Telemetry',
      'Battery, voltage, temperature snapshots',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.dataset_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Session recording', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose which data is included when a session is saved. Streams '
              'are stored per-type in the file, so disabled ones simply leave '
              'smaller sessions.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            for (final entry in _labels.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.multiline_chart_outlined),
                title: Text(entry.value.$1),
                subtitle: Text(
                  entry.value.$2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                value: streams.contains(entry.key),
                onChanged: (on) => onToggle(entry.key, on),
              ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.settings_input_component_outlined),
              title: const Text('Record AUX channels'),
              subtitle: Text(
                'Muse auxiliary inputs as extra channels (Classic firmware: '
                'AUX1; Athena: AUX1–AUX4). Off records only TP9/AF7/AF8/TP10. '
                'Applies on the next connect.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: recordAux,
              onChanged: onRecordAux,
            ),
            const Divider(height: 24),
            Text(
              'Note: blood-oxygen (SpO2) and fNIRS metrics (HbO/HbR) are not '
              'currently derived — the raw optical light channels above are '
              'what the sensor provides, on both Classic and Athena firmware.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
