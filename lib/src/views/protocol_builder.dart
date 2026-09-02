import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:muse_ml/src/audio/guardrail_sound.dart';
import 'package:muse_ml/src/audio/output_ids.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/feedback/feature_catalog.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/protocol_catalog.dart';
import 'package:muse_ml/src/feedback/user_protocol_store.dart';

const List<int> _builderColors = [
  16738533,
  16743594,
  16764672,
  16757115,
  16744519,
  16741088,
  16746561,
  16745547,
  16745905,
];

const List<String> _museElectrodes = ['TP9', 'AF7', 'AF8', 'TP10'];
const List<String> _crownElectrodes = [
  'CP3',
  'C3',
  'F5',
  'PO3',
  'PO4',
  'F6',
  'C4',
  'CP4',
];

/// Form over a [ProtocolDocument]. Writes app-support `protocols/user.<slug>.json`.
class ProtocolBuilderView extends ConsumerStatefulWidget {
  const ProtocolBuilderView({super.key, this.existing});

  final ProtocolDocument? existing;

  @override
  ConsumerState<ProtocolBuilderView> createState() =>
      _ProtocolBuilderViewState();
}

class _ProtocolBuilderViewState extends ConsumerState<ProtocolBuilderView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _slug;
  late final TextEditingController _catchPhrase;
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late final TextEditingController _guide;
  late final TextEditingController _algorithm;
  late final TextEditingController _delay;
  late final TextEditingController _metadata;
  late final TextEditingController _guardCopy;

  bool _slugEdited = false;
  bool _saving = false;

  late int _color;
  late String _calibration;
  late BackgroundKind _background;

  bool _hasReward = true;
  String? _rewardFeature;
  RewardOutputId _rewardOutput = RewardOutputId.chime;
  final List<_InhibitDraft> _inhibit = [];
  final Set<String> _rewardElectrodes = {};

  bool _hasGuard = false;
  String? _guardFeature;
  GuardrailSound _guardOutput = GuardrailSound.softBowl;
  bool _muffleReward = false;
  final Set<String> _guardElectrodes = {};

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) {
      _slug = TextEditingController();
      _catchPhrase = TextEditingController();
      _title = TextEditingController();
      _subtitle = TextEditingController();
      _guide = TextEditingController();
      _algorithm = TextEditingController();
      _delay = TextEditingController();
      _metadata = TextEditingController();
      _guardCopy = TextEditingController();
      _color = _builderColors.first;
      _calibration = builderCalibrationIds.first;
      _background = BackgroundKind.drone;
      _rewardFeature = 'band.atr';
    } else {
      final slug = existing.id.startsWith('user.')
          ? existing.id.substring('user.'.length)
          : existing.id;
      _slug = TextEditingController(text: slug);
      _slugEdited = true;
      _catchPhrase = TextEditingController(text: existing.copy.catchPhrase);
      _title = TextEditingController(text: existing.copy.title);
      _subtitle = TextEditingController(text: existing.copy.subtitle);
      _guide = TextEditingController(text: existing.copy.guideText);
      _algorithm = TextEditingController(
        text: existing.copy.algorithmDescription,
      );
      _delay = TextEditingController(text: existing.copy.expectedDelay);
      _metadata = TextEditingController(
        text: existing.copy.metadataDescription ?? '',
      );
      _guardCopy = TextEditingController(text: existing.guard?.copy ?? '');
      _color = existing.colorValue;
      _calibration = builderCalibrationIds.contains(existing.calibration)
          ? existing.calibration
          : builderCalibrationIds.first;
      _background = BackgroundKind.values.firstWhere(
        (k) => k.name == existing.background.kind,
        orElse: () => BackgroundKind.drone,
      );
      _hasReward = existing.reward != null;
      _rewardFeature = existing.reward?.feature ?? 'band.atr';
      _rewardOutput = rewardOutputIdFromStored(existing.reward?.output);
      for (final c in existing.reward?.inhibit ?? const <TargetCondition>[]) {
        if (c is BetaCeiling) {
          _inhibit.add(
            _InhibitDraft(type: 'betaCeiling', max: _fmtMax(c.maxBetaRel)),
          );
        } else if (c is DeltaCeiling) {
          _inhibit.add(
            _InhibitDraft(type: 'deltaCeiling', max: _fmtMax(c.maxDeltaRel)),
          );
        }
      }
      _rewardElectrodes.addAll(existing.reward?.electrodes ?? const []);
      _hasGuard = existing.guard != null;
      _guardFeature = existing.guard?.feature ?? 'band.delta';
      _guardOutput = GuardrailSound.fromName(existing.guard?.output);
      _muffleReward = existing.guard?.muffleReward ?? false;
      _guardElectrodes.addAll(existing.guard?.electrodes ?? const []);
    }
    _catchPhrase.addListener(_onCatchPhraseChanged);
  }

  @override
  void dispose() {
    _catchPhrase.removeListener(_onCatchPhraseChanged);
    _slug.dispose();
    _catchPhrase.dispose();
    _title.dispose();
    _subtitle.dispose();
    _guide.dispose();
    _algorithm.dispose();
    _delay.dispose();
    _metadata.dispose();
    _guardCopy.dispose();
    super.dispose();
  }

  void _onCatchPhraseChanged() {
    if (_editing || _slugEdited) return;
    final suggested = suggestUserProtocolSlug(_catchPhrase.text);
    if (suggested.length >= 3 && suggested != _slug.text) {
      _slug.text = suggested;
    }
  }

  Set<String>? _availableIds() {
    final kind = ref.read(appStateProvider).listingDeviceKind;
    if (kind == null) return null;
    final infos = ref.read(availableFeaturesProvider(kind)).valueOrNull;
    if (infos == null) return null;
    return {
      for (final f in infos)
        if (f.available) f.id,
    };
  }

  List<FeatureCatalogEntry> _rewardItems(FeatureCatalog catalog) {
    final items = catalog.rewardChoices(availableIds: _availableIds());
    return _withCurrent(catalog, items, _rewardFeature, reward: true);
  }

  List<FeatureCatalogEntry> _guardItems(FeatureCatalog catalog) {
    final items = catalog.guardChoices(availableIds: _availableIds());
    return _withCurrent(catalog, items, _guardFeature, reward: false);
  }

  List<FeatureCatalogEntry> _withCurrent(
    FeatureCatalog catalog,
    List<FeatureCatalogEntry> items,
    String? current, {
    required bool reward,
  }) {
    if (current == null || items.any((e) => e.id == current)) return items;
    final extra = catalog[current];
    if (extra == null) return items;
    if (reward ? extra.usableAsReward() : extra.usableAsGuard()) {
      return [extra, ...items];
    }
    return items;
  }

  List<String> _electrodeChoices() {
    final kind = ref.read(appStateProvider).listingDeviceKind;
    final base = kind == null
        ? [..._museElectrodes, ..._crownElectrodes]
        : deviceKindIsCrown(kind)
        ? _crownElectrodes
        : _museElectrodes;
    final extra = {..._rewardElectrodes, ..._guardElectrodes};
    return [
      ...base,
      for (final n in extra)
        if (!base.contains(n)) n,
    ];
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final catalog =
        ref.read(protocolCatalogProvider).valueOrNull ?? ProtocolCatalog.empty;
    final features = catalog.features.byId.isEmpty
        ? await FeatureCatalog.load()
        : catalog.features;

    final slug = _slug.text.trim();
    final id = 'user.$slug';
    final rewardItems = features.rewardChoices(availableIds: _availableIds());
    final guardItems = features.guardChoices(availableIds: _availableIds());

    String? rewardFeature = _rewardFeature;
    if (_hasReward) {
      rewardFeature ??= rewardItems.isNotEmpty ? rewardItems.first.id : null;
      if (rewardFeature == null) {
        _toast('Pick a reward feature.');
        return;
      }
      final entry = features[rewardFeature];
      if (entry == null || !entry.usableAsReward()) {
        _toast(
          'Reward feature "$rewardFeature" is not listed for the reward lane.',
        );
        return;
      }
    }

    String? guardFeature = _guardFeature;
    if (_hasGuard) {
      guardFeature ??= guardItems.isNotEmpty ? guardItems.first.id : null;
      if (guardFeature == null) {
        _toast('Pick a guard feature.');
        return;
      }
      final entry = features[guardFeature];
      if (entry == null || !entry.usableAsGuard()) {
        _toast(
          'Guard feature "$guardFeature" is not listed for the guard lane.',
        );
        return;
      }
    }

    final inhibit = <TargetCondition>[];
    for (final row in _inhibit) {
      final max = double.tryParse(row.max.trim());
      if (max == null || max < 0 || max > 1) {
        _toast('Inhibit max must be a number between 0 and 1.');
        return;
      }
      inhibit.add(
        row.type == 'deltaCeiling' ? DeltaCeiling(max) : BetaCeiling(max),
      );
    }

    final doc = ProtocolDocument(
      id: id,
      origin: 'user',
      schemaVersion: 1,
      copy: ProtocolCopy(
        catchPhrase: _catchPhrase.text.trim(),
        title: _title.text.trim(),
        subtitle: _subtitle.text.trim(),
        guideText: _guide.text.trim(),
        algorithmDescription: _algorithm.text.trim(),
        expectedDelay: _delay.text.trim(),
        metadataDescription: _metadata.text.trim(),
      ),
      colorValue: _color,
      calibration: _calibration,
      background: ProtocolBackground(kind: _background.name),
      reward: _hasReward
          ? ProtocolReward(
              feature: rewardFeature!,
              output: _rewardOutput.name,
              policy: 'percentileUptrain',
              inhibit: inhibit,
              electrodes: _rewardElectrodes.isEmpty
                  ? null
                  : _rewardElectrodes.toList(),
              locked: const [],
            )
          : null,
      guard: _hasGuard
          ? ProtocolGuard(
              feature: guardFeature!,
              output: _guardOutput.name,
              policy: 'percentileWarn',
              muffleReward: _muffleReward,
              defaultEnabled: true,
              electrodes: _guardElectrodes.isEmpty
                  ? null
                  : _guardElectrodes.toList(),
              copy: _guardCopy.text.trim().isEmpty
                  ? null
                  : _guardCopy.text.trim(),
              locked: const [],
            )
          : null,
    );

    setState(() => _saving = true);
    try {
      final store = await UserProtocolStore.open(features);
      await store.save(doc, overwriteId: widget.existing?.id);
      ref.invalidate(protocolCatalogProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on UserProtocolException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalogAsync = ref.watch(protocolCatalogProvider);
    final catalog = catalogAsync.valueOrNull ?? ProtocolCatalog.empty;
    final features = catalog.features;
    final kind = ref.watch(appStateProvider).listingDeviceKind;
    if (kind != null) {
      ref.watch(availableFeaturesProvider(kind));
    }
    final rewardItems = _rewardItems(features);
    final guardItems = _guardItems(features);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit program' : 'New program'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              theme,
              title: 'Identity',
              children: [
                TextFormField(
                  controller: _slug,
                  enabled: !_editing,
                  decoration: const InputDecoration(
                    labelText: 'Id slug',
                    prefixText: 'user.',
                    helperText: '3–64 lowercase letters, digits, hyphens',
                    border: OutlineInputBorder(),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]')),
                    LengthLimitingTextInputFormatter(64),
                  ],
                  onChanged: (_) => _slugEdited = true,
                  validator: (v) {
                    final slug = (v ?? '').trim();
                    if (!RegExp(r'^[a-z0-9-]{3,64}$').hasMatch(slug)) {
                      return 'Need 3–64 characters: a–z, 0–9, hyphen';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _catchPhrase,
                  decoration: const InputDecoration(
                    labelText: 'Catch phrase',
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                Text('Color', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _builderColors)
                      _ColorDot(
                        color: c,
                        selected: _color == c,
                        onTap: () => setState(() => _color = c),
                      ),
                  ],
                ),
              ],
            ),
            _card(
              theme,
              title: 'Copy',
              children: [
                TextFormField(
                  controller: _subtitle,
                  decoration: const InputDecoration(
                    labelText: 'Subtitle',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _guide,
                  decoration: const InputDecoration(
                    labelText: 'Guide text',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 4,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _algorithm,
                  decoration: const InputDecoration(
                    labelText: 'Algorithm description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _delay,
                  decoration: const InputDecoration(
                    labelText: 'Expected delay (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _metadata,
                  decoration: const InputDecoration(
                    labelText: 'Metadata description',
                    helperText: 'Written into saved session metadata',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: _required,
                ),
              ],
            ),
            _card(
              theme,
              title: 'Calibration & background',
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(_calibration),
                  initialValue: _calibration,
                  decoration: const InputDecoration(
                    labelText: 'Calibration',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final id in builderCalibrationIds)
                      DropdownMenuItem(
                        value: id,
                        child: Text(
                          id == 'eyes-open-01' ? 'Eyes Open' : 'Eyes Closed',
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _calibration = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<BackgroundKind>(
                  key: ValueKey(_background),
                  initialValue: _background,
                  decoration: const InputDecoration(
                    labelText: 'Background',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final k in BackgroundKind.values)
                      DropdownMenuItem(
                        value: k,
                        child: Text(soundNameFromBackgroundKind(k)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _background = v);
                  },
                ),
              ],
            ),
            _card(
              theme,
              title: 'Reward',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reward lane'),
                  subtitle: const Text(
                    'Omit for a record-only or guard-only program',
                  ),
                  value: _hasReward,
                  onChanged: (on) => setState(() => _hasReward = on),
                ),
                if (_hasReward) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey('reward-$_rewardFeature'),
                    initialValue: rewardItems.any((e) => e.id == _rewardFeature)
                        ? _rewardFeature
                        : (rewardItems.isEmpty ? null : rewardItems.first.id),
                    decoration: const InputDecoration(
                      labelText: 'Feature',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final e in rewardItems)
                        DropdownMenuItem(
                          value: e.id,
                          child: Text('${e.label} (${e.id})'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _rewardFeature = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<RewardOutputId>(
                    key: ValueKey(_rewardOutput),
                    initialValue: _rewardOutput,
                    decoration: const InputDecoration(
                      labelText: 'Output',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final o in RewardOutputId.values)
                        DropdownMenuItem(value: o, child: Text(o.label)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _rewardOutput = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('Inhibit', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'AND-gates on the reward verdict. Never a warning.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  for (var i = 0; i < _inhibit.length; i++)
                    _InhibitRow(
                      draft: _inhibit[i],
                      onChanged: () => setState(() {}),
                      onRemove: () => setState(() => _inhibit.removeAt(i)),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(
                        () => _inhibit.add(
                          _InhibitDraft(type: 'betaCeiling', max: '0.25'),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add inhibit'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Electrodes (optional — empty uses the Rust default)',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _ElectrodeChips(
                    names: _electrodeChoices(),
                    selected: _rewardElectrodes,
                    onToggle: (n) => setState(() {
                      if (!_rewardElectrodes.remove(n)) {
                        _rewardElectrodes.add(n);
                      }
                    }),
                  ),
                ],
              ],
            ),
            _card(
              theme,
              title: 'Guard',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Guard lane'),
                  subtitle: const Text(
                    'Independent warning. Does not change the reward.',
                  ),
                  value: _hasGuard,
                  onChanged: (on) => setState(() => _hasGuard = on),
                ),
                if (_hasGuard) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey('guard-$_guardFeature'),
                    initialValue: guardItems.any((e) => e.id == _guardFeature)
                        ? _guardFeature
                        : (guardItems.isEmpty ? null : guardItems.first.id),
                    decoration: const InputDecoration(
                      labelText: 'Feature',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final e in guardItems)
                        DropdownMenuItem(
                          value: e.id,
                          child: Text('${e.label} (${e.id})'),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _guardFeature = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<GuardrailSound>(
                    key: ValueKey(_guardOutput),
                    initialValue: _guardOutput,
                    decoration: const InputDecoration(
                      labelText: 'Output',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final s in GuardrailSound.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _guardOutput = v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Muffle reward while warning'),
                    value: _muffleReward,
                    onChanged: (on) => setState(() => _muffleReward = on),
                  ),
                  TextFormField(
                    controller: _guardCopy,
                    decoration: InputDecoration(
                      labelText: 'Guard copy (optional)',
                      hintText: features[_guardFeature ?? '']?.guardCopy,
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Electrodes (optional — empty uses the Rust default)',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  _ElectrodeChips(
                    names: _electrodeChoices(),
                    selected: _guardElectrodes,
                    onToggle: (n) => setState(() {
                      if (!_guardElectrodes.remove(n)) {
                        _guardElectrodes.add(n);
                      }
                    }),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(
    ThemeData theme, {
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

String? _required(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Required' : null;

String _fmtMax(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

class _InhibitDraft {
  _InhibitDraft({required this.type, required this.max});
  String type;
  String max;
}

class _InhibitRow extends StatelessWidget {
  const _InhibitRow({
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });

  final _InhibitDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              key: ValueKey(draft.type),
              initialValue: draft.type,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'betaCeiling',
                  child: Text('Beta ceiling'),
                ),
                DropdownMenuItem(
                  value: 'deltaCeiling',
                  child: Text('Delta ceiling'),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                draft.type = v;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: draft.max,
              decoration: const InputDecoration(
                labelText: 'Max',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (v) => draft.max = v,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _ElectrodeChips extends StatelessWidget {
  const _ElectrodeChips({
    required this.names,
    required this.selected,
    required this.onToggle,
  });

  final List<String> names;
  final Set<String> selected;
  final void Function(String name) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final n in names)
          FilterChip(
            label: Text(n),
            selected: selected.contains(n),
            onSelected: (_) => onToggle(n),
          ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shown = Color(color | 0xFF000000);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: shown,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }
}
