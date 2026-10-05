import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/connection_provider.dart';
import 'package:neurofeed/src/monitor/device_montage.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/streaming/streaming_indicator.dart';

const _kMuseHeadSymbols = ['/', '‾', '‾', '\\'];

/// One status-bar pad: the glyph and the electrode whose score colours it.
class SignalPad {
  const SignalPad(this.glyph, this.electrode);

  final String glyph;
  final int electrode;
}

/// Muse head outline `/‾‾\`, with AUX dots between the overlines when AUX
/// is streaming (`/‾•‾\` … `/‾••••‾\`). Any other head count is one `•`
/// per pad. AUX count is capped at [kMuseAuxElectrodeNames]. Crown's eight
/// are laid out by [_crownQualityRing].
@visibleForTesting
List<SignalPad> signalPads({required int headCount, int auxChannels = 0}) {
  if (headCount != _kMuseHeadSymbols.length) {
    return [for (var i = 0; i < headCount; i++) SignalPad('•', i)];
  }
  final aux = auxChannels.clamp(0, kMuseAuxElectrodeNames.length);
  return [
    const SignalPad('/', 0),
    const SignalPad('‾', 1),
    for (var i = 0; i < aux; i++)
      SignalPad('•', kMuseElectrodeNames.length + i),
    const SignalPad('‾', 2),
    const SignalPad('\\', 3),
  ];
}

Color _signalColor(double score) => score >= 80
    ? const Color(0xFF4CAF50)
    : score >= 40
    ? const Color(0xFFFF9800)
    : const Color(0xFFF44336);

/// Top-down Crown ring, nose up: F5 F6, C3 C4, CP3 CP4, PO3 PO4.
/// Each cell is the bullet's ink (~7px). The 18px glyph overflows the
/// cell, so the ring stays about as tall as the Muse line.
Widget _crownQualityRing(List<double> qualities) {
  Widget mark(int electrode) {
    final score = electrode < qualities.length ? qualities[electrode] : 0.0;
    return SizedBox(
      width: 7,
      height: 7,
      child: OverflowBox(
        maxWidth: 22,
        maxHeight: 22,
        child: Text(
          '•',
          style: TextStyle(
            color: _signalColor(score),
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            height: 1,
          ),
        ),
      ),
    );
  }

  const gap = SizedBox.shrink();
  return Table(
    defaultColumnWidth: const FixedColumnWidth(7),
    children: [
      TableRow(children: [gap, mark(2), mark(5), gap]),
      TableRow(children: [mark(1), gap, gap, mark(6)]),
      TableRow(children: [mark(0), gap, gap, mark(7)]),
      TableRow(children: [gap, mark(3), mark(4), gap]),
    ],
  );
}

/// Pad quality glyphs. [headCount] is the device head montage. [auxChannels]
/// is the Muse AUX count on this connection (0 for Crown).
@visibleForTesting
Widget signalQualityRow(
  List<double>? qualities,
  int headCount, {
  int auxChannels = 0,
}) {
  if (qualities == null) return const SizedBox.shrink();
  if (headCount == kCrownElectrodeNames.length) {
    return _crownQualityRing(qualities);
  }
  final pads = signalPads(headCount: headCount, auxChannels: auxChannels);
  final children = <Widget>[];
  for (var i = 0; i < pads.length; i++) {
    final pad = pads[i];
    final score = pad.electrode < qualities.length
        ? qualities[pad.electrode]
        : 0.0;
    children.add(
      Text(
        pad.glyph,
        style: TextStyle(
          color: _signalColor(score),
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
    );
    if (i < pads.length - 1) children.add(const SizedBox(width: 2));
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
                            auxChannels: displayedAuxChannels(
                              kind: state.lastConnectedKind,
                              hardwareAux: state.status.auxChannels,
                              museAuxEnabled: ref.watch(
                                settingsProvider.select((s) => s.museAuxEnabled),
                              ),
                            ),
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
