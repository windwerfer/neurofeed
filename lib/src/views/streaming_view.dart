import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:muse_ml/src/streaming/streaming_controller.dart';
import 'package:muse_ml/src/streaming/streaming_models.dart';

/// '192.168.200.34' → '192.168.200'; null unless the IP is private-ranged and
/// well-formed (the cases that make sense as a LAN destination hint).
String? subnetOfPrivateIp(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;
  final octets = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p);
    if (v == null || v < 0 || v > 255) return null;
    octets.add(v);
  }
  final private = octets[0] == 10 ||
      (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
      (octets[0] == 192 && octets[1] == 168);
  if (!private) return null;
  return octets.take(3).join('.');
}

/// Streams live sensor data to a PC over one of the supported network
/// protocols. The protocol is chosen here; streaming starts automatically as
/// soon as a Muse connects and the selected protocol is enabled.
class StreamingView extends ConsumerStatefulWidget {
  const StreamingView({super.key});

  @override
  ConsumerState<StreamingView> createState() => _StreamingViewState();
}

class _StreamingViewState extends ConsumerState<StreamingView> {
  final _oscIpCtrl = TextEditingController();
  final _oscPortCtrl = TextEditingController();
  final _oscPrefixCtrl = TextEditingController();
  final _lslPrefixCtrl = TextEditingController();

  /// The device's own LAN IP once detected (used for the helper text).
  String? _localIp;

  @override
  void initState() {
    super.initState();
    _syncFromSettings(ref.read(settingsProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) => _autofillOscIpIfUnset());
  }

  Future<String?> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (subnetOfPrivateIp(addr.address) != null) return addr.address;
        }
      }
    } catch (_) {
      // Interface enumeration may fail on some platforms; the field keeps its
      // built-in example then.
    }
    return null;
  }

  /// First run: the OS hasn't handed out a real receiver IP yet, so fill the
  /// example with a free address on the device's own subnet (e.g. the phone
  /// is at 192.168.200.34 → default 192.168.200.100).
  Future<void> _autofillOscIpIfUnset() async {
    final settings = ref.read(settingsProvider);
    if (settings.oscIpUserSet) return;
    final ip = await _detectLocalIp();
    final subnet = ip == null ? null : subnetOfPrivateIp(ip);
    if (!mounted || subnet == null) return;
    setState(() => _localIp = ip);
    await settings.setOscIp('$subnet.100');
    if (mounted) _syncFromSettings(ref.read(settingsProvider));
  }

  void _syncFromSettings(Settings s) {
    _oscIpCtrl.text = s.oscIp;
    _oscPortCtrl.text = s.oscPort.toString();
    _oscPrefixCtrl.text = s.oscPrefix;
    _lslPrefixCtrl.text = s.lslPrefix;
  }

  Future<void> _persistAndReconfigure(Future<void> Function() persist) async {
    await persist();
    if (mounted) {
      _syncFromSettings(ref.read(settingsProvider));
    }
    await ref.read(streamingControllerProvider.notifier).reconfigure();
  }

  Future<void> _switchProtocol(StreamProtocol next) async {
    final controller = ref.read(streamingControllerProvider.notifier);
    final streaming = ref.read(streamingControllerProvider).streaming;
    if (streaming && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Switch protocol?'),
          content: Text(
            'Switching to ${next.label} stops the current '
            '${ref.read(streamingControllerProvider).protocol.label} stream.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final settings = ref.read(settingsProvider);
    await settings.setStreamProtocolName(next.name);
    await controller.reconfigure();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final state = ref.watch(streamingControllerProvider);
    final protocol = StreamProtocol.fromName(settings.streamProtocolName);
    final isOsc = protocol == StreamProtocol.osc;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Streaming', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        _protocolCard(theme, protocol),
        const SizedBox(height: 12),
        _settingsCard(theme, settings, protocol, isOsc),
        const SizedBox(height: 12),
        _statusCard(theme, state, settings, protocol),
      ],
    );
  }

  Widget _protocolCard(ThemeData theme, StreamProtocol protocol) {
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
                  Icons.network_ping,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Protocol', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<StreamProtocol>(
              initialValue: protocol,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final p in StreamProtocol.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (next) {
                if (next != null && next != protocol) {
                  _switchProtocol(next);
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              protocol.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsCard(
      ThemeData theme, Settings settings, StreamProtocol protocol, bool isOsc) {
    final enabled = isOsc ? settings.oscEnabled : settings.lslEnabled;
    final separate = isOsc
        ? settings.oscSeparateGroups
        : settings.lslSeparateGroups;

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
                  isOsc ? Icons.wifi_tethering : Icons.dns_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Settings', style: theme.textTheme.titleMedium),
              ],
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.play_circle_outline),
              title: Text('Stream ${protocol.label}'),
              subtitle: Text(
                'Starts automatically when a Muse connects. '
                'Shown on this screen while not streaming.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: enabled,
              onChanged: (on) => _persistAndReconfigure(
                () => isOsc
                    ? settings.setOscEnabled(on)
                    : settings.setLslEnabled(on),
              ),
            ),
            const Divider(height: 24),
            if (isOsc) ...[
              TextField(
                controller: _oscIpCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'IP to stream to (the PC)',
                  border: OutlineInputBorder(),
                  isDense: true,
                )
                    .copyWith(
                      helperText: _localIp == null
                          ? 'The receiving computer\'s LAN address, '
                              'e.g. 192.168.1.100'
                          : 'Your subnet is ${subnetOfPrivateIp(_localIp!)}.x '
                              '— pick a free address on the PC, '
                              'e.g. ${subnetOfPrivateIp(_localIp!)}.100',
                    ),
                onSubmitted: (v) => _persistAndReconfigure(
                  () => settings.setOscIp(v.trim()),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _oscPortCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Port',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (v) {
                  final port = int.tryParse(v);
                  if (port != null) {
                    _persistAndReconfigure(() => settings.setOscPort(port));
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _oscPrefixCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address prefix',
                  border: OutlineInputBorder(),
                  isDense: true,
                  helperText: 'Messages go to /muse/eeg, /muse/ppg, …',
                ),
                onSubmitted: (v) => _persistAndReconfigure(() {
                  var prefix = v.trim();
                  if (!prefix.startsWith('/')) prefix = '/$prefix';
                  return settings.setOscPrefix(prefix);
                }),
              ),
              const Divider(height: 24),
            ] else ...[
              TextField(
                controller: _lslPrefixCtrl,
                decoration: const InputDecoration(
                  labelText: 'Stream name prefix',
                  border: OutlineInputBorder(),
                  isDense: true,
                  helperText: 'Streams are named <prefix>EEG, <prefix>PPG, … '
                      'and auto-discovered — no IP/port needed. Receive with '
                      'LabRecorder or another LSL client.',
                ),
                onSubmitted: (v) => _persistAndReconfigure(
                  () => settings.setLslPrefix(v.trim()),
                ),
              ),
              const Divider(height: 24),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.view_stream_outlined),
              title: const Text('Stream each sensor group separately'),
              subtitle: Text(
                'One stream per group (EEG, PPG, IMU, Bands). When off only '
                'the EEG stream is sent — the other groups have different '
                'sample rates and cannot share one stream.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: separate,
              onChanged: (on) => _persistAndReconfigure(
                () => isOsc
                    ? settings.setOscSeparateGroups(on)
                    : settings.setLslSeparateGroups(on),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(ThemeData theme, StreamingUiState state,
      Settings settings, StreamProtocol protocol) {
    final isOsc = protocol == StreamProtocol.osc;
    final destination = isOsc
        ? '${settings.oscIp}:${settings.oscPort}'
        : 'local network (auto-discovery)';

    final (Color color, String text) = switch ((state.connected,
        state.enabled, state.streaming)) {
      (_, _, true) => (Colors.green, 'Streaming to $destination'),
      (true, false, _) => (theme.disabledColor, 'Streaming disabled'),
      (true, true, false) => (Colors.orange, 'Stream not running'),
      (false, _, _) => (
          Colors.orange,
          state.enabled ? 'Waiting for a device…' : 'No device connected',
        ),
    };

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_heart, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('Status', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.circle, size: 14, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
            if (state.error != null) ...[
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (state.streaming) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Text('Elapsed', style: theme.textTheme.bodyMedium),
                  const Spacer(),
                  Text(
                    _formatDuration(state.elapsed),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('Packets sent', style: theme.textTheme.bodyMedium),
                  const Spacer(),
                  Text(
                    '${state.packetsSent}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('Data sent', style: theme.textTheme.bodyMedium),
                  const Spacer(),
                  Text(
                    _formatBytes(state.bytesSent),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
              const Divider(height: 24),
              Text('Channels', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final g in state.groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${g.name} (${g.channelCount} ch, '
                    '${g.nominalRate.toInt()} Hz): ${g.channelNames.join(', ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration? d) {
    if (d == null) return '—';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}