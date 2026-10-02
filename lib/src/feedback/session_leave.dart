import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';

/// True while leaving would stop a session that is still running.
bool sessionBackAsksToEnd(FeedbackPhase phase) {
  switch (phase) {
    case FeedbackPhase.calibrating:
    case FeedbackPhase.playing:
    case FeedbackPhase.paused:
    case FeedbackPhase.interrupted:
      return true;
    case FeedbackPhase.idle:
    case FeedbackPhase.ended:
      return false;
  }
}

/// Asks whether going back should stop the session.
///
/// Dismissing the barrier, or a system back that closes the dialog, is Cancel.
Future<bool> confirmEndSession(BuildContext context) async {
  final end = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('End session?'),
      content: const Text('Going back stops this feedback session.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('End session'),
        ),
      ],
    ),
  );
  return end ?? false;
}

/// AppBar back and system back for [FeedbackSessionView].
///
/// In progress, both ask before calling [onEnd]. Confirm does not pop: [onEnd]
/// moves the session to ended, and the session route replaces itself with the
/// summary. Idle pops. Ended does not pop — the summary blocks leaving an
/// unsaved session, and a pop here would skip Save/Discard.
class SessionBackGuard extends StatefulWidget {
  const SessionBackGuard({
    super.key,
    required this.phase,
    required this.onEnd,
    required this.child,
  });

  final FeedbackPhase phase;
  final Future<void> Function() onEnd;
  final Widget child;

  @override
  State<SessionBackGuard> createState() => _SessionBackGuardState();
}

class _SessionBackGuardState extends State<SessionBackGuard> {
  bool _promptOpen = false;
  bool _ending = false;

  // Ended stays until the summary route replaces this one. Idle leaves.
  // In progress cannot pop until the user confirms, and even then [onEnd]
  // replaces the route instead of popping it.
  bool get _canPop => widget.phase == FeedbackPhase.idle && !_ending;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _promptOpen || _ending) return;
        if (!sessionBackAsksToEnd(widget.phase)) return;
        _promptOpen = true;
        unawaited(_ask());
      },
      child: widget.child,
    );
  }

  Future<void> _ask() async {
    if (!mounted) {
      _promptOpen = false;
      return;
    }
    var end = false;
    try {
      end = await confirmEndSession(context);
    } finally {
      _promptOpen = false;
    }
    if (!mounted || !end) return;
    if (!sessionBackAsksToEnd(widget.phase)) return;
    _ending = true;
    try {
      await widget.onEnd();
    } catch (e, st) {
      debugPrint('[feedback] leave: end failed: $e\n$st');
    } finally {
      _releaseEnding();
    }
  }

  /// Keeps a second back from ending again until the phase can rebuild.
  ///
  /// [onEnd] notifies listeners before this future resumes, but the new phase
  /// arrives on the next frame. Clearing [_ending] in that gap would ask again.
  void _releaseEnding() {
    if (!mounted) return;
    if (!sessionBackAsksToEnd(widget.phase)) {
      _ending = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ending = false;
    });
  }
}
