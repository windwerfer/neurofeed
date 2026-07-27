import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';

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
                (d) => ListTile(
                  tileColor: const Color(0xFF1E212A),
                  leading: const Icon(Icons.bluetooth),
                  title: Text(d.name),
                  subtitle: Text(d.id),
                  enabled: state.connectingTo == null,
                  onTap: state.connectingTo != null
                      ? null
                      : () => notifier.connectTo(d),
                ),
              ),
              if (state.scanning)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
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
