import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

mixin FrameCoalescedNotify on ChangeNotifier {
  bool _scheduled = false;

  void notifyListenersCoalesced() {
    if (!hasListeners) return;
    SchedulerBinding? binding;
    try {
      binding = SchedulerBinding.instance;
    } catch (_) {
      binding = null;
    }
    if (binding == null) {
      notifyListeners();
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    binding.scheduleFrameCallback((_) {
      _scheduled = false;
      notifyListeners();
    });
    binding.scheduleFrame();
    binding.ensureVisualUpdate();
  }
}
