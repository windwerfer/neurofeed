import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/monitor/monitor_controller.dart';
import 'package:muse_ml/src/monitor/monitor_state.dart';

export 'package:muse_ml/src/monitor/recording/recording_store.dart'
    show recordingStoreProvider;

final monitorControllerProvider =
    NotifierProvider<MonitorController, MonitorState>(MonitorController.new);
