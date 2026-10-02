import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';
import 'package:neurofeed/src/feedback/session_leave.dart';

void main() {
  test('sessionBackAsksToEnd only while a session is in progress', () {
    expect(sessionBackAsksToEnd(FeedbackPhase.calibrating), isTrue);
    expect(sessionBackAsksToEnd(FeedbackPhase.playing), isTrue);
    expect(sessionBackAsksToEnd(FeedbackPhase.paused), isTrue);
    expect(sessionBackAsksToEnd(FeedbackPhase.interrupted), isTrue);
    expect(sessionBackAsksToEnd(FeedbackPhase.idle), isFalse);
    expect(sessionBackAsksToEnd(FeedbackPhase.ended), isFalse);
  });

  testWidgets('idle back leaves without asking or ending', (tester) async {
    final ends = _Ends();
    await _open(tester, phase: FeedbackPhase.idle, onEnd: ends.call);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('End session?'), findsNothing);
    expect(ends.count, 0);
    expect(find.text('protocols'), findsOneWidget);

    await _open(tester, phase: FeedbackPhase.idle, onEnd: ends.call);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('End session?'), findsNothing);
    expect(ends.count, 0);
    expect(find.text('protocols'), findsOneWidget);
  });

  testWidgets('in-progress back asks, and cancel keeps the session', (
    tester,
  ) async {
    final ends = _Ends();
    for (final phase in const [
      FeedbackPhase.calibrating,
      FeedbackPhase.playing,
      FeedbackPhase.paused,
      FeedbackPhase.interrupted,
    ]) {
      await _open(tester, phase: phase, onEnd: ends.call);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('End session?'), findsOneWidget);
      expect(
        find.text('Going back stops this feedback session.'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('End session'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('End session?'), findsNothing);
      expect(find.text('running'), findsOneWidget);
      expect(ends.count, 0);
    }
  });

  testWidgets('End session calls onEnd once and does not pop', (tester) async {
    final ends = _Ends();
    await _open(tester, phase: FeedbackPhase.playing, onEnd: ends.call);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    expect(ends.count, 1);
    expect(find.text('End session?'), findsNothing);
    expect(find.text('running'), findsOneWidget);
    expect(find.text('protocols'), findsNothing);
  });

  testWidgets('system back asks, and a second back is cancel', (tester) async {
    final ends = _Ends();
    await _open(tester, phase: FeedbackPhase.playing, onEnd: ends.call);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('End session?'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('End session?'), findsNothing);
    expect(ends.count, 0);
    expect(find.text('running'), findsOneWidget);
  });

  testWidgets('tapping the barrier is cancel', (tester) async {
    final ends = _Ends();
    await _open(tester, phase: FeedbackPhase.paused, onEnd: ends.call);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('End session?'), findsNothing);
    expect(ends.count, 0);
    expect(find.text('running'), findsOneWidget);
  });

  testWidgets('ended does not pop or end', (tester) async {
    final ends = _Ends();
    await _open(tester, phase: FeedbackPhase.ended, onEnd: ends.call);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('End session?'), findsNothing);
    expect(ends.count, 0);
    expect(find.text('running'), findsOneWidget);
  });

  testWidgets('a second back while end is in flight does not end twice', (
    tester,
  ) async {
    final gate = Completer<void>();
    final ends = _Ends();
    final host = GlobalKey<_HostState>();
    await _open(
      tester,
      phase: FeedbackPhase.playing,
      hostKey: host,
      onEnd: () async {
        ends.call();
        await gate.future;
        host.currentState!.setPhase(FeedbackPhase.ended);
      },
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    expect(ends.count, 1);
    expect(find.text('End session?'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('End session?'), findsNothing);
    expect(ends.count, 1);
    gate.complete();
    await tester.pump();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('End session?'), findsNothing);
    expect(ends.count, 1);
    expect(find.text('running'), findsOneWidget);
  });

  testWidgets('confirm after the phase leaves in progress does not end', (
    tester,
  ) async {
    final ends = _Ends();
    final host = GlobalKey<_HostState>();
    await _open(
      tester,
      phase: FeedbackPhase.calibrating,
      hostKey: host,
      onEnd: ends.call,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    host.currentState!.setPhase(FeedbackPhase.idle);
    await tester.pump();
    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    expect(ends.count, 0);
    expect(find.text('running'), findsOneWidget);
  });

  testWidgets('a failed end can be retried', (tester) async {
    var fail = true;
    final ends = _Ends();
    await _open(
      tester,
      phase: FeedbackPhase.interrupted,
      onEnd: () async {
        ends.call();
        if (fail) throw StateError('flush');
      },
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    expect(ends.count, 1);
    expect(find.text('running'), findsOneWidget);
    fail = false;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('End session?'), findsOneWidget);
    await tester.tap(find.text('End session'));
    await tester.pumpAndSettle();
    expect(ends.count, 2);
    expect(find.text('running'), findsOneWidget);
  });

  testWidgets('a sheet above the session closes before the warning', (
    tester,
  ) async {
    final ends = _Ends();
    await _open(tester, phase: FeedbackPhase.playing, onEnd: ends.call);
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Nerd'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Nerd'), findsNothing);
    expect(find.text('End session?'), findsNothing);
    expect(ends.count, 0);
    expect(find.text('running'), findsOneWidget);
  });
}

class _Ends {
  int count = 0;

  Future<void> call() async {
    count++;
  }
}

Future<void> _open(
  WidgetTester tester, {
  required FeedbackPhase phase,
  required Future<void> Function() onEnd,
  GlobalKey<_HostState>? hostKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        _Host(key: hostKey, phase: phase, onEnd: onEnd),
                  ),
                );
              },
              child: const Text('protocols'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('protocols'));
  await tester.pumpAndSettle();
  expect(find.text('running'), findsOneWidget);
}

class _Host extends StatefulWidget {
  const _Host({super.key, required this.phase, required this.onEnd});

  final FeedbackPhase phase;
  final Future<void> Function() onEnd;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late FeedbackPhase phase = widget.phase;

  void setPhase(FeedbackPhase next) {
    setState(() => phase = next);
  }

  @override
  Widget build(BuildContext context) {
    return SessionBackGuard(
      phase: phase,
      onEnd: widget.onEnd,
      child: Scaffold(
        appBar: AppBar(title: const Text('Sleep-Edge Rest')),
        body: Column(
          children: [
            const Text('running'),
            TextButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (_) =>
                      const SizedBox(height: 120, child: Text('Nerd')),
                );
              },
              child: const Text('open sheet'),
            ),
          ],
        ),
      ),
    );
  }
}
