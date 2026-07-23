import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/charts/eeg_chart.dart';
import 'package:muse_ml/src/connection_provider.dart';

class RawEegView extends ConsumerWidget {
  const RawEegView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appStateProvider.notifier);
    return EegChartWidget(source: notifier.liveCache);
  }
}
