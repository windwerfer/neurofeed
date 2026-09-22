import 'package:flutter/widgets.dart';

/// Drops a window inset that covers more than half of that axis.
///
/// Android 15 Xiaomi freeform reports the caption-bar rect as the whole
/// window, so [MediaQueryData.padding] on that edge equals the window size
/// and [SafeArea] lays the UI out at zero height. Real status and navigation
/// insets stay well under half the window.
/// https://github.com/flutter/flutter/issues/161086
EdgeInsets clampBrokenFreeformInsets(EdgeInsets insets, Size size) {
  if (size.width <= 0 || size.height <= 0) return insets;
  final top = insets.top > size.height * 0.5 ? 0.0 : insets.top;
  final bottom = insets.bottom > size.height * 0.5 ? 0.0 : insets.bottom;
  final left = insets.left > size.width * 0.5 ? 0.0 : insets.left;
  final right = insets.right > size.width * 0.5 ? 0.0 : insets.right;
  if (top == insets.top &&
      bottom == insets.bottom &&
      left == insets.left &&
      right == insets.right) {
    return insets;
  }
  return EdgeInsets.fromLTRB(left, top, right, bottom);
}

/// Rewrites [MediaQuery] when a freeform caption inset would blank the UI.
class FreeformInsetClamp extends StatelessWidget {
  const FreeformInsetClamp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final padding = clampBrokenFreeformInsets(mq.padding, mq.size);
    final viewPadding = clampBrokenFreeformInsets(mq.viewPadding, mq.size);
    if (padding == mq.padding && viewPadding == mq.viewPadding) return child;
    return MediaQuery(
      data: mq.copyWith(padding: padding, viewPadding: viewPadding),
      child: child,
    );
  }
}
