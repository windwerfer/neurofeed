import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/monitor/monitor_controller.dart';
import 'package:muse_ml/src/monitor/monitor_state.dart';

final monitorControllerProvider =
    NotifierProvider<MonitorController, MonitorState>(MonitorController.new);
