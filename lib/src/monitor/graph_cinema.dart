import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool graphCinemaIsMobile([TargetPlatform? platform]) {
  final p = platform ?? defaultTargetPlatform;
  return p == TargetPlatform.android || p == TargetPlatform.iOS;
}

/// Hide graph chrome: mobile landscape, or desktop F11 fullscreen.
bool graphCinema(BuildContext context, {required bool fullscreen}) {
  if (fullscreen) return true;
  if (!graphCinemaIsMobile()) return false;
  return MediaQuery.orientationOf(context) == Orientation.landscape;
}

class GraphCinema extends StatefulWidget {
  const GraphCinema({super.key, required this.child});

  final Widget child;

  static bool of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_GraphCinemaScope>();
    return graphCinema(context, fullscreen: scope?.fullscreen ?? false);
  }

  @override
  State<GraphCinema> createState() => _GraphCinemaState();
}

class _GraphCinemaState extends State<GraphCinema> {
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.f11) return false;
    if (graphCinemaIsMobile()) return false;
    setState(() => _fullscreen = !_fullscreen);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return _GraphCinemaScope(fullscreen: _fullscreen, child: widget.child);
  }
}

class _GraphCinemaScope extends InheritedWidget {
  const _GraphCinemaScope({required this.fullscreen, required super.child});

  final bool fullscreen;

  @override
  bool updateShouldNotify(_GraphCinemaScope old) =>
      fullscreen != old.fullscreen;
}
