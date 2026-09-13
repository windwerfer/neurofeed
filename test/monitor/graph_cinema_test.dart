import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/graph_cinema.dart';

Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('graphCinemaIsMobile is Android and iOS only', () {
    expect(graphCinemaIsMobile(TargetPlatform.android), isTrue);
    expect(graphCinemaIsMobile(TargetPlatform.iOS), isTrue);
    expect(graphCinemaIsMobile(TargetPlatform.linux), isFalse);
    expect(graphCinemaIsMobile(TargetPlatform.windows), isFalse);
    expect(graphCinemaIsMobile(TargetPlatform.macOS), isFalse);
  });

  testWidgets('mobile landscape hides chrome; portrait does not', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.android, () async {
      _size(tester, const Size(800, 400));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) =>
                Text(GraphCinema.of(context) ? 'cinema' : 'chrome'),
          ),
        ),
      );
      expect(find.text('cinema'), findsOneWidget);

      _size(tester, const Size(400, 800));
      await tester.pump();
      expect(find.text('chrome'), findsOneWidget);
    });
  });

  testWidgets('desktop landscape keeps chrome', (tester) async {
    await _withPlatform(TargetPlatform.linux, () async {
      _size(tester, const Size(1600, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) =>
                Text(GraphCinema.of(context) ? 'cinema' : 'chrome'),
          ),
        ),
      );
      expect(find.text('chrome'), findsOneWidget);
    });
  });

  testWidgets('F11 toggles cinema on desktop', (tester) async {
    await _withPlatform(TargetPlatform.linux, () async {
      _size(tester, const Size(1600, 900));
      await tester.pumpWidget(
        const GraphCinema(child: MaterialApp(home: _CinemaLabel())),
      );
      expect(find.text('chrome'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pump();
      expect(find.text('cinema'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pump();
      expect(find.text('chrome'), findsOneWidget);
    });
  });

  testWidgets('F11 is ignored on mobile', (tester) async {
    await _withPlatform(TargetPlatform.android, () async {
      _size(tester, const Size(400, 800));
      await tester.pumpWidget(
        const GraphCinema(child: MaterialApp(home: _CinemaLabel())),
      );
      expect(find.text('chrome'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pump();
      expect(find.text('chrome'), findsOneWidget);
    });
  });
}

class _CinemaLabel extends StatelessWidget {
  const _CinemaLabel();

  @override
  Widget build(BuildContext context) {
    return Text(GraphCinema.of(context) ? 'cinema' : 'chrome');
  }
}
