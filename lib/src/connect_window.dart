import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/rust/api/device_config.dart';
import 'package:muse_ml/src/settings.dart';

/// Display name for DeviceKind enum
extension DeviceKindDisplayName on DeviceKind {
  String get displayName => switch (this) {
    DeviceKind.muse => 'Muse',
    DeviceKind.neurosity => 'Neurosity',
    DeviceKind.simulatedMuse => 'Muse (Simulated)',
    DeviceKind.simulatedNeurosity => 'Neurosity (Simulated)',
  };
}

/// Full-body overlay behind the [ConnectWindow]: the dropdown panel over an
/// opaque tap barrier. While the window is open, tapping anywhere on the
/// screen outside the panel hides it again (same effect as the status-bar
/// toggle).
class ConnectOverlay extends ConsumerWidget {
  const ConnectOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.watch(appStateProvider.notifier);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: notifier.toggleConnectWindow,
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: const ConnectWindow()),
      ],
    );
  }
}

/// A dropdown panel shown beneath the status bar that lists discovered devices.
/// Selecting one connects to it.
class ConnectWindow extends ConsumerWidget {
  const ConnectWindow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.watch(appStateProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final showSimulate = settings.enableSimulatedDevices;

    return Material(
      elevation: 8,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Connect to a device',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (!state.scanning)
                  TextButton.icon(
                    onPressed: notifier.openConnectWindowAndScan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Rescan'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Device kind dropdown
            DropdownButtonFormField<DeviceKind>(
              value: state.connectDeviceKind,
              decoration: const InputDecoration(
                labelText: 'Device type',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: DeviceKind.values.map((kind) {
                return DropdownMenuItem(
                  value: kind,
                  child: Text(kind.displayName),
                );
              }).toList(),
              onChanged: (kind) {
                if (kind != null) {
                  notifier.setConnectDeviceKind(kind);
                }
              },
            ),
            // Experimental banner for Neurosity (Crown/Notion)
            if (state.connectDeviceKind == DeviceKind.neurosity &&
                !state.connectSimulate) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.tertiary,
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Experimental: Neurosity Crown/Notion support is untested on real hardware. '
                        'Please report bugs on GitHub.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Simulate toggle (only visible when enabled in settings)
            if (showSimulate) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.science_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Simulator (Debug)',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use built-in simulator instead of real hardware. '
                      'Produces realistic EEG, bands, IMU, and SpO₂ data.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Enable Simulator'),
                      subtitle: Text(
                        state.connectSimulate
                            ? 'Simulating ${state.connectDeviceKind.displayName}'
                            : 'Real hardware will be used',
                      ),
                      value: state.connectSimulate,
                      onChanged: (value) {
                        notifier.setConnectSimulate(value);
                      },
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (state.devices.isEmpty && !state.scanning)
              Text('No ${state.connectDeviceKind.displayName} devices found. ${state.connectSimulate ? 'Simulator ready.' : 'Make sure the headset is on.'}')
            else ...[
              ...state.devices.map(
                (d) => Material(
                  type: MaterialType.card,
                  color: const Color(0xFF1E212A),
                  child: ListTile(
                    leading: Icon(d.kind == DeviceKind.muse ? Icons.bluetooth : Icons.headphones),
                    title: Text(d.name),
                    subtitle: Text(d.id),
                    enabled: state.connectingTo == null,
                    onTap: state.connectingTo != null
                        ? null
                        : () => notifier.connectTo(d),
                  ),
                ),
              ),
              if (state.scanning)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      BrailleSpinner(),
                      SizedBox(width: 8),
                      Text('Scanning…'),
                    ],
                  ),
                ),
            ],
            if (state.scanMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                state.scanMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Low-CPU scanning indicator: a braille-pattern spinner advanced by a
/// [Timer.periodic] at 5 fps instead of every animation frame, wrapped in a
/// [RepaintBoundary] so each tick re-rasterizes only this tiny layer — parent
/// and sibling widgets are painted once and never repainted.
class BrailleSpinner extends StatefulWidget {
  const BrailleSpinner({super.key});

  @override
  State<BrailleSpinner> createState() => _BrailleSpinnerState();
}

class _BrailleSpinnerState extends State<BrailleSpinner> {
  static const _frames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      setState(() => _index = (_index + 1) % _frames.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Text(
        _frames[_index],
        style: const TextStyle(fontSize: 18, fontFamily: 'monospace'),
      ),
    );
  }
}
