import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/connection_provider.dart';
import 'package:neurofeed/src/monitor/device_montage.dart';
import 'package:neurofeed/src/streaming/streaming_indicator.dart';

const _kMuseSignalSymbols = ['/', '‾', '‾', '\\'];

/// One glyph per head pad: the Muse head outline for 4 pads, dots otherwise.
@visibleForTesting
List<String> padSymbols(int count) => count == _kMuseSignalSymbols.length
    ? _kMuseSignalSymbols
    : List.filled(count, '•');

/// Pad quality glyphs for the connected device's [padCount] head pads.
@visibleForTesting
Widget signalQualityRow(List<double>? qualities, int padCount) {
  if (qualities == null) return const SizedBox.shrink();
  final symbols = padSymbols(padCount);
  final children = <Widget>[];
  for (int i = 0; i < symbols.length; i++) {
    final score = i < qualities.length ? qualities[i] : 0.0;
    final color = score >= 80
        ? const Color(0xFF4CAF50)
        : score >= 40
        ? const Color(0xFFFF9800)
        : const Color(0xFFF44336);
    children.add(
      Text(
        symbols[i],
        style: TextStyle(
          color: color,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
    );
    if (i < symbols.length - 1) children.add(const SizedBox(width: 2));
  }
  return Row(mainAxisSize: MainAxisSize.min, children: children);
}

/// Top status bar: hamburger menu (left), device/battery/signal (center),
/// disconnect button (right, only when connected).
///
/// [showMenu] hides the hamburger when a pushed route already provides its
/// own back navigation (feedback session steps) — the user leaves via the
/// app bar's back button instead.
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key, this.showMenu = true});

  final bool showMenu;

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
          if (showMenu)
            IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Menu',
              onPressed: notifier.toggleSidebar,
            ),
          // Center: device info / tap to open connect window.
          Expanded(
            child: GestureDetector(
              onTap: notifier.toggleConnectWindow,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: state.disconnecting
                    ? const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Disconnecting…'),
                          ],
                        ),
                      )
                    : connected
                    ? Row(
                        children: [
                          const Icon(Icons.bluetooth_connected, size: 18),
                          const SizedBox(width: 8),
                          // Device name yields space before signal quality.
                          Flexible(
                            child: Text(
                              state.status.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.battery_full, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '${(state.batteryLevel < 1 ? state.batteryLevel * 100 : state.batteryLevel).toInt()}%',
                          ),
                          const SizedBox(width: 12),
                          signalQualityRow(
                            state.signalQuality,
                            channelCountForKind(state.lastConnectedKind),
                          ),
                          const SizedBox(width: 12),
                          const StreamIndicator(),
                        ],
                      )
                    : state.connectingTo != null
                    ? Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Connecting to ${state.connectingTo}…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        ],
                      )
                    : const Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Not connected — tap to connect'),
                            SizedBox(width: 12),
                            StreamIndicator(),
                          ],
                        ),
                      ),
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
