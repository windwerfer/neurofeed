import 'package:flutter/material.dart';

/// Connected but no EEG samples yet. Disconnected uses empty axes only —
/// the status bar already has `Not connected — tap to connect`.
class MonitorWaitingSignal extends StatelessWidget {
  const MonitorWaitingSignal({super.key});

  static const String copy = 'Waiting for signal';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Center(
        child: Text(
          copy,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Connected to a headset without PPG (Crown / Notion). Nav entry stays.
class MonitorNoPpg extends StatelessWidget {
  const MonitorNoPpg({super.key});

  static const String copy = 'No PPG on this device';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Center(
        child: Text(
          copy,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
