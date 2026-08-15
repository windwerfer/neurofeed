import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/connect_window.dart';
import 'package:muse_ml/src/rust/frb_generated.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:muse_ml/src/status_bar.dart';
import 'package:muse_ml/src/views/bands.dart';
import 'package:muse_ml/src/views/raw_eeg.dart';
import 'package:muse_ml/src/views/terminal.dart';
import 'package:muse_ml/src/views/psd_view.dart';
import 'package:muse_ml/src/views/settings_view.dart';
import 'package:muse_ml/src/views/feedback_list.dart';
import 'package:muse_ml/src/views/feedback_history.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// The main app shell: status bar on top, a collapsible sidebar with the three
/// views, and the connect window overlay.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        final notifier = ref.read(appStateProvider.notifier);
        await notifier.disconnectOnClose();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);

    final Widget body;
    switch (state.currentView) {
      case AppView.feedback:
        body = const FeedbackListView();
      case AppView.feedbackHistory:
        body = const FeedbackHistoryView();
      case AppView.bands:
        body = const BandsView();
      case AppView.rawEeg:
        body = const RawEegView();
      case AppView.spectrogram:
        body = const SpectrogramView();
      case AppView.psd:
        body = const PsdView();
      case AppView.settings:
        body = const SettingsView();
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
          const StatusBar(),
          Expanded(
            child: Stack(
              children: [
                Row(
                  children: [
                    if (state.sidebarOpen)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Container(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          child: Column(
                            children: [
                              _SideBarItem(
                                label: 'Feedback',
                                selected: state.currentView == AppView.feedback,
                                onTap: () => ref
                                    .read(appStateProvider.notifier)
                                    .setCurrentView(AppView.feedback),
                              ),
                              _SideBarItem(
                                label: 'Feedback History',
                                selected: state.currentView == AppView.feedbackHistory,
                                onTap: () => ref
                                    .read(appStateProvider.notifier)
                                    .setCurrentView(AppView.feedbackHistory),
                              ),
                              _SideBarItem(
                                label: 'Bands',
                                selected: state.currentView == AppView.bands,
                                onTap: () => ref
                                    .read(appStateProvider.notifier)
                                    .setCurrentView(AppView.bands),
                              ),
                              _SideBarItem(
                                label: 'Raw EEG',
                                selected: state.currentView == AppView.rawEeg,
                                onTap: () => ref
                                    .read(appStateProvider.notifier)
                                    .setCurrentView(AppView.rawEeg),
                              ),
                              _SideBarItem(
                                label: 'Spectrogram',
                                selected:
                                    state.currentView == AppView.spectrogram,
                                onTap: () => ref
                                    .read(appStateProvider.notifier)
                                    .setCurrentView(AppView.spectrogram),
                              ),
                              _SideBarItem(
                                label: 'Power Spectral Density (PSD)',
                                selected: state.currentView == AppView.psd,
                                onTap: () => ref
                                    .read(appStateProvider.notifier)
                                    .setCurrentView(AppView.psd),
                              ),
                              _SideBarItem(
                                label: 'Settings',
                                selected: state.currentView == AppView.settings,
                                onTap: () => ref
                                    .read(appStateProvider.notifier)
                                    .setCurrentView(AppView.settings),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(child: body),
                  ],
                ),
                if (state.connectWindowOpen)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: const ConnectWindow(),
                  ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }
}

class _SideBarItem extends StatelessWidget {
  const _SideBarItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.card,
      color: const Color(0xFF1E212A),
      child: ListTile(
        title: Text(label),
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}

/// Entry point. Loads settings, initializes the Rust library, requests BLE
/// permissions, then runs the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await requestBlePermissions();
  final settings = await Settings.load();
  runApp(
    ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => AppStateNotifier(settings)),
        settingsProvider.overrideWithValue(settings),
      ],
      child: MaterialApp(
        title: 'Muse ML',
        themeMode: ThemeMode.system,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
        ),
        home: const AppShell(),
      ),
    ),
  );
}

/// Requests the Bluetooth LE permissions needed for scanning/connecting.
///
/// On Android 12+ (API 31+) this is `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT`
/// (the "Nearby devices" group). `BLUETOOTH_SCAN` is declared with
/// `neverForLocation`, and btleplug reads device names from the advertisement
/// `ScanRecord` rather than `BluetoothDevice.getName()`, so names are returned
/// on API 31/32 without any location permission. On Android 11 and below, BLE
/// scanning still requires `ACCESS_FINE_LOCATION`, so we request it there.
/// If a permission is permanently denied we open the app settings so the user
/// can grant it manually.
///
/// Returns true if every required permission is granted (or the platform does
/// not require runtime BLE permissions), false otherwise.
Future<bool> requestBlePermissions() async {
  // permission_handler has no Linux/desktop implementation, so only request on
  // Android (where BLE requires runtime permissions).
  if (!Platform.isAndroid) return true;

  final permissions = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ];

  // Location is only needed for BLE scanning on Android 11 (API 30) and below.
  // On API 31+ BLUETOOTH_SCAN is declared `neverForLocation` and the manifest
  // scopes ACCESS_FINE_LOCATION to maxSdkVersion 30, so there is no location
  // permission to request there.
  final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  if (sdkInt <= 30) {
    permissions.add(Permission.locationWhenInUse);
  }

  final statuses = await permissions.request();

  final denied = statuses.entries.where((e) => !e.value.isGranted);
  if (denied.isEmpty) return true;

  final permanentlyDenied = denied.any((e) => e.value.isPermanentlyDenied);
  if (permanentlyDenied) {
    await openAppSettings();
  }
  return false;
}
