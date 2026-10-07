/// Catalog protocol ids and the legacy-id alias map.
///
/// Kept free of Flutter / Rust imports so the calibration manifest, settings
/// and pure-Dart tests can resolve ids without pulling in the bridge.
library;

/// Frozen catalog protocol ids (on-disk `protocol` string in `.neurofeed`).
/// Order matches `assets/protocols.json`.
const List<String> catalogProtocolIds = [
  'sleepGuard',
  'restAwake',
  'openMonitor',
  'alertOpen',
  'alertClosed',
  'concentrate',
  'calibrateRecord',
];

/// The catalog ids before the 2026-10 evidence rewrite, in their old freeze
/// order. Only settings migration reads this.
const List<String> legacyCatalogProtocolIds = [
  'drowsiness',
  'twilight',
  'alertnessOpen',
  'alertnessClosed',
  'mindfulness',
  'concentration',
  'relaxedConcentration',
  'recordOnly',
  'guardrailOnly',
];

/// Retired catalog ids → current catalog id.
///
/// Old ids live on in saved sessions (`protocol` / `protocolJson`), SQLite
/// history rows, settings maps keyed by protocol id, import/export and agent
/// calls. Resolve them through [canonicalProtocolId] so old sessions still
/// open and show a sensible protocol name.
///
/// The first six are renames of the same job (recipe updated). `twilight`
/// (TAR reward) and `relaxedConcentration` (ATR + beta/delta ceilings) were
/// dropped; they map to `restAwake` for display / selection fallback only.
/// `recordOnly` (no lanes, optional single baseline) was dropped in favour of
/// `calibrateRecord`, the one catalog row without reward or guard; it maps
/// there for display / selection fallback only (calibrateRecord's staged,
/// required calibration is not what an old recordOnly session ran).
/// Their recipes differ, so anything that recomputes from the recipe (charts,
/// export) must prefer the session's saved `protocolJson` snapshot first
/// (see `savedProtocolDocument`).
const Map<String, String> legacyProtocolAliases = {
  'drowsiness': 'restAwake',
  'mindfulness': 'openMonitor',
  'alertnessOpen': 'alertOpen',
  'alertnessClosed': 'alertClosed',
  'concentration': 'concentrate',
  'guardrailOnly': 'sleepGuard',
  'twilight': 'restAwake',
  'relaxedConcentration': 'restAwake',
  'recordOnly': 'calibrateRecord',
};

/// Legacy ids whose recipe was carried over (rename, not a merge). Per-protocol
/// settings (explicit AI guard choice, inhibit ceiling overrides) migrate only
/// for these.
const Set<String> legacyProtocolRenames = {
  'drowsiness',
  'mindfulness',
  'alertnessOpen',
  'alertnessClosed',
  'concentration',
  'guardrailOnly',
};

/// [id] with a retired catalog id mapped to its current id. Unknown and user
/// (`user.*`) ids pass through unchanged.
String canonicalProtocolId(String id) => legacyProtocolAliases[id] ?? id;

/// Whether [id] is a retired catalog id.
bool isLegacyProtocolId(String id) => legacyProtocolAliases.containsKey(id);
