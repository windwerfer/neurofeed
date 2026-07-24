import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';

const _kSignalSymbols = ['/', '‾', '‾', '\\'];

Widget _signalQualityRow(List<double>? qualities) {
  if (qualities == null) return const SizedBox.shrink();
  final children = <Widget>[];
  for (int i = 0; i < 4; i++) {
    final score = i < qualities.length ? qualities[i] : 0.0;
    final color = score >= 80
        ? const Color(0xFF4CAF50)
        : score >= 40
            ? const Color(0xFFFF9800)
            : const Color(0xFFF44336);
    children.add(Text(
      _kSignalSymbols[i],
      style: TextStyle(
        color: color,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      ),
    ));
    if (i < 3) children.add(const SizedBox(width: 2));
  }
  return Row(mainAxisSize: MainAxisSize.min, children: children);
}

/// Top status bar: hamburger menu (left), device/battery/signal (center),
/// disconnect button (right, only when connected).
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.watch(appStateProvider.notifier);
    final connected = state.status.connected;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: notifier.toggleSidebar,
          ),
          // Center: device info / tap to open connect window.
          Expanded(
            child: GestureDetector(
              onTap: notifier.toggleConnectWindow,
              child: Center(
                child: state.disconnecting
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          const Text('Disconnecting…'),
                        ],
                      )
                    : connected
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bluetooth_connected, size: 18),
                              const SizedBox(width: 8),
                              Text(state.status.name),
                              const SizedBox(width: 16),
                              const Icon(Icons.battery_full, size: 18),
                              const SizedBox(width: 4),
                              Text('${(state.batteryLevel < 1 ? state.batteryLevel * 100 : state.batteryLevel).toInt()}%'),
                              const SizedBox(width: 16),
                              _signalQualityRow(state.signalQuality),
                            ],
                          )
                        : state.connectingTo != null
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('Connecting to ${state.connectingTo}…'),
                                ],
                              )
                            : const Text('Not connected — tap to connect'),
              ),
            ),
          ),
          if (connected)
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: 'Disconnect',
              onPressed: notifier.disconnectDevice,
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}
