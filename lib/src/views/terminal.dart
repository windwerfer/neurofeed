import 'package:flutter/material.dart';

/// Waterfall view: raw event / control log streamed from the headset.
class SpectrogramView extends StatelessWidget {
  const SpectrogramView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Spectrogram\n(raw event/control log will be shown here)'),
    );
  }
}
