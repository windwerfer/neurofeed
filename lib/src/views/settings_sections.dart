enum SettingsSection { general, devices, ai, recording, about }

const List<SettingsSection> settingsSections = <SettingsSection>[
  SettingsSection.general,
  SettingsSection.devices,
  SettingsSection.ai,
  SettingsSection.recording,
  SettingsSection.about,
];

const double kSettingsRailWidth = 180;
const double kSettingsRailBreakpoint = 640;

String settingsSectionLabel(SettingsSection section) => switch (section) {
  SettingsSection.general => 'General',
  SettingsSection.devices => 'Devices',
  SettingsSection.ai => 'AI',
  SettingsSection.recording => 'Recording',
  SettingsSection.about => 'About',
};

class SettingsSearchHit {
  const SettingsSearchHit({
    required this.section,
    required this.cardId,
    required this.title,
    required this.terms,
    this.androidOnly = false,
  });

  final SettingsSection section;
  final String cardId;
  final String title;
  final List<String> terms;
  final bool androidOnly;

  String get resultLabel => '${settingsSectionLabel(section)} · $title';
}

const List<SettingsSearchHit> settingsSearchCatalog = <SettingsSearchHit>[
  SettingsSearchHit(
    section: SettingsSection.general,
    cardId: 'appearance',
    title: 'Appearance',
    terms: ['theme', 'system', 'light', 'dark', 'brightness'],
  ),
  SettingsSearchHit(
    section: SettingsSection.general,
    cardId: 'subject',
    title: 'Subject',
    terms: ['subject id', 'nickname', 'anonymous'],
  ),
  SettingsSearchHit(
    section: SettingsSection.general,
    cardId: 'music',
    title: 'Music feedback',
    terms: ['music folder', 'cutoff', 'invert', 'shuffle'],
  ),
  SettingsSearchHit(
    section: SettingsSection.general,
    cardId: 'audio',
    title: 'Reduce audio stutter',
    terms: ['audio', 'stutter', 'latency', 'dropout'],
    androidOnly: true,
  ),
  SettingsSearchHit(
    section: SettingsSection.devices,
    cardId: 'muse',
    title: 'Muse',
    terms: ['aux', 'auxiliary', 'aux1'],
  ),
  SettingsSearchHit(
    section: SettingsSection.devices,
    cardId: 'crown',
    title: 'Crown',
    terms: ['quality source', 'signal quality', 'pads'],
  ),
  SettingsSearchHit(
    section: SettingsSection.ai,
    cardId: 'ai',
    title: 'Guardrail AI engine',
    terms: ['spur', 'cbramod', 'reve', 'model'],
  ),
  SettingsSearchHit(
    section: SettingsSection.ai,
    cardId: 'calibration',
    title: 'Calibration',
    terms: ['default', 'always', 'staged', 'simple', 'baseline', 'artifacts'],
  ),
  SettingsSearchHit(
    section: SettingsSection.recording,
    cardId: 'folder',
    title: 'Save files to folder',
    terms: ['folder', 'storage', 'reset to default folder'],
  ),
  SettingsSearchHit(
    section: SettingsSection.recording,
    cardId: 'recording',
    title: 'Session recording',
    terms: [
      'raw eeg',
      'band powers',
      'ppg',
      'pulse',
      'spo2',
      'accelerometer',
      'gyroscope',
      'movement',
      'peak alpha',
      'telemetry',
      'aux',
    ],
  ),
  SettingsSearchHit(
    section: SettingsSection.recording,
    cardId: 'gestures',
    title: 'Gesture markers',
    terms: ['eye', 'blink', 'clench', 'markers'],
  ),
  SettingsSearchHit(
    section: SettingsSection.about,
    cardId: 'about',
    title: 'Third-party notices',
    terms: ['about', 'licenses', 'credits'],
  ),
  SettingsSearchHit(
    section: SettingsSection.about,
    cardId: 'debug',
    title: 'Debug mode',
    terms: ['simulator', 'sim'],
  ),
];

List<SettingsSearchHit> settingsSearchHits({required bool includeAudio}) {
  if (includeAudio) return settingsSearchCatalog;
  return [
    for (final hit in settingsSearchCatalog)
      if (!hit.androidOnly) hit,
  ];
}

List<SettingsSearchHit> filterSettingsSearch(
  List<SettingsSearchHit> hits,
  String query,
) {
  final tokens = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return const [];
  return [
    for (final hit in hits)
      if (tokens.every((token) => _searchBlob(hit).contains(token))) hit,
  ];
}

String _searchBlob(SettingsSearchHit hit) =>
    '${settingsSectionLabel(hit.section)} ${hit.title} ${hit.terms.join(' ')}'
        .toLowerCase();
