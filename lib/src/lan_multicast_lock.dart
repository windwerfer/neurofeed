import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('neurofeed/wifi');

/// Android drops Wi-Fi broadcast packets for apps that do not hold a
/// `WifiManager.MulticastLock`. Crown OSC arrives as subnet broadcast.
Future<void> setMulticastLock({required bool held}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod<void>(
      held ? 'acquireMulticastLock' : 'releaseMulticastLock',
    );
  } catch (e) {
    debugPrint('[neurofeed] multicast lock: $e');
  }
}
