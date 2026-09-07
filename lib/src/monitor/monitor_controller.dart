import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/monitor/cache/band_cache.dart';
import 'package:muse_ml/src/monitor/monitor_state.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

class MonitorController extends Notifier<MonitorState> {
  final BandCache bandCache = BandCache();
  StreamSubscription<MuseEventDto>? _eventSub;

  @override
  MonitorState build() {
    final app = ref.read(appStateProvider.notifier);
    _eventSub ??= app.eventStream.listen(_onEvent);
    ref.listen(
      appStateProvider.select((s) => (s.status.connected, s.lastConnectedKind)),
      (prev, next) {
        state = MonitorState.idle(deviceKind: next.$2);
      },
    );
    ref.onDispose(() {
      _eventSub?.cancel();
      _eventSub = null;
    });
    final current = ref.read(appStateProvider);
    if (current.status.connected) {
      debugPrint(
        '[monitor] hydrate connected kind=${current.lastConnectedKind}',
      );
    }
    return MonitorState.idle(deviceKind: current.lastConnectedKind);
  }

  void _onEvent(MuseEventDto event) {
    switch (event) {
      case MuseEventDto_Bands():
        bandCache.appendBands(event.field0);
      default:
        break;
    }
  }
}
