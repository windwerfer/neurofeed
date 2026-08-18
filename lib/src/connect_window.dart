import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';

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

/// A dropdown panel shown beneath the status bar that lists discovered Muse
/// devices. Selecting one connects to it.
class ConnectWindow extends ConsumerWidget {
  const ConnectWindow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.watch(appStateProvider.notifier);

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
                  'Connect to a Muse device',
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
            if (state.devices.isEmpty && !state.scanning)
              const Text('No Muse devices found. Make sure the headset is on.')
            else ...[
              ...state.devices.map(
                (d) => Material(
                  type: MaterialType.card,
                  color: const Color(0xFF1E212A),
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth),
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
