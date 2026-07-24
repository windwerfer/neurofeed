import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';

class ChartController extends ChangeNotifier {
  double timeWindowSecs = 10;
  double visibleEnd = 0;
  bool autoScroll = true;

  void snapToLive(EegDataSource source) {
    final latest = source.latestTimestamp;
    if (latest > 0) visibleEnd = latest;
  }

  void ensureBounds(EegDataSource source) {
    final latest = source.latestTimestamp;
    final oldest = source.oldestTimestamp;
    final maxWindow = source.maxTimeWindowSecs;
    timeWindowSecs = timeWindowSecs.clamp(2.0, maxWindow);

    if (autoScroll) {
      visibleEnd = latest;
    }
    if (latest <= 0 || oldest <= 0) return;
    final minEnd = oldest + timeWindowSecs;
    final maxEnd = latest;
    if (minEnd < maxEnd) {
      visibleEnd = visibleEnd.clamp(minEnd, maxEnd);
    } else {
      visibleEnd = latest;
    }
  }

  void onScaleUpdate(ScaleUpdateDetails d, double maxWindow, double widgetWidth) {
    final prevWindow = timeWindowSecs;
    timeWindowSecs = (prevWindow / d.scale).clamp(2.0, maxWindow);
    if (d.focalPointDelta.dx.abs() > 0.5) {
      final effectiveDelta = d.focalPointDelta.dx * timeWindowSecs / widgetWidth;
      visibleEnd -= effectiveDelta;
      autoScroll = false;
    }
    notifyListeners();
  }

  void onPointerSignal(PointerScrollEvent event, double maxWindow) {
    final factor = event.scrollDelta.dy < 0 ? 1.0 / 1.2 : 1.2;
    timeWindowSecs = (timeWindowSecs * factor).clamp(2.0, maxWindow);
    notifyListeners();
  }

  void zoomIn(double maxWindow) {
    timeWindowSecs = (timeWindowSecs / 1.5).clamp(2.0, maxWindow);
    notifyListeners();
  }

  void zoomOut(double maxWindow) {
    timeWindowSecs = (timeWindowSecs * 1.5).clamp(2.0, maxWindow);
    notifyListeners();
  }

  void enableAutoScroll(EegDataSource source) {
    autoScroll = true;
    snapToLive(source);
    notifyListeners();
  }

  void forceNotify() => notifyListeners();
}
