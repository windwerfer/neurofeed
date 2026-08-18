import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/streaming/streaming_controller.dart';

const _liveColor = Color(0xFF4CAF50);
const _armedColor = Color(0xFFFFB300);

/// Small colored dot for the sidebar: green while streaming, amber when the
/// protocol is enabled but no device is streaming, nothing when off.
class StreamDot extends ConsumerWidget {
  const StreamDot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = streamBadgeOf(ref.watch(streamingControllerProvider));
    if (badge == StreamBadgeState.off) return const SizedBox.shrink();
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: badge == StreamBadgeState.live ? _liveColor : _armedColor,
      ),
    );
  }
}

/// Dot + protocol label for the status bar, e.g. a green dot with "OSC" while
/// streaming live or an amber dot with "LSL" while armed without a device.
class StreamIndicator extends ConsumerWidget {
  const StreamIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(streamingControllerProvider);
    final badge = streamBadgeOf(state);
    if (badge == StreamBadgeState.off) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 10,
          color: badge == StreamBadgeState.live ? _liveColor : _armedColor,
        ),
        const SizedBox(width: 5),
        Text(
          state.protocol.label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: badge == StreamBadgeState.live ? _liveColor : _armedColor,
          ),
        ),
      ],
    );
  }
}