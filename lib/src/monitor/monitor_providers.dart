import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/monitor/monitor_controller.dart';
import 'package:neurofeed/src/monitor/monitor_state.dart';

export 'package:neurofeed/src/monitor/recording/recording_store.dart'
    show recordingStoreProvider;

final monitorControllerProvider =
    NotifierProvider<MonitorController, MonitorState>(MonitorController.new);
