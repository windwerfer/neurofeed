import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/connect_window.dart';
import 'package:muse_ml/src/rust/frb_generated.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:muse_ml/src/status_bar.dart';
import 'package:muse_ml/src/streaming/streaming_controller.dart';
import 'package:muse_ml/src/streaming/streaming_indicator.dart';
import 'package:muse_ml/src/views/bands.dart';
import 'package:muse_ml/src/views/raw_eeg.dart';
import 'package:muse_ml/src/views/terminal.dart';
import 'package:muse_ml/src/views/psd_view.dart';
import 'package:muse_ml/src/views/settings_view.dart';
import 'package:muse_ml/src/views/streaming_view.dart';
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
    // Construct the streaming controller once so it listens to the Muse
    // event stream for the whole app lifetime (streaming starts as soon as
    // a device connects, independent of the visible view).
    ref.read(streamingControllerProvider.notifier);
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  void _selectView(AppView view) {
    final notifier = ref.read(appStateProvider.notifier);
    notifier.setCurrentView(view);
    if (MediaQuery.sizeOf(context).width < 700) notifier.setSidebar(false);
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
      case AppView.streaming:
        body = const StreamingView();
      case AppView.settings:
        body = const SettingsView();
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const StatusBar(),
            Expanded(
              child: _buildContent(context, state, body),
            ),
          ],
        ),
      ),
    );
  }

  /// Sidebar: full-height rail shown either as a squishing Row sibling (wide
  /// screens) or as an overlay above the body (narrow screens).
  Widget _buildSidebar(BuildContext context, AppUiState state) {
    return Container(
      width: kSidebarWidth,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          _SideBarItem(
            label: 'Feedback',
            selected: state.currentView == AppView.feedback,
            onTap: () => _selectView(AppView.feedback),
          ),
          _SideBarItem(
            label: 'Feedback History',
            selected: state.currentView == AppView.feedbackHistory,
            onTap: () => _selectView(AppView.feedbackHistory),
          ),
          _SideBarItem(
            label: 'Bands',
            selected: state.currentView == AppView.bands,
            onTap: () => _selectView(AppView.bands),
          ),
          _SideBarItem(
            label: 'Raw EEG',
            selected: state.currentView == AppView.rawEeg,
            onTap: () => _selectView(AppView.rawEeg),
          ),
          _SideBarItem(
            label: 'Spectrogram',
            selected: state.currentView == AppView.spectrogram,
            onTap: () => _selectView(AppView.spectrogram),
          ),
          _SideBarItem(
            label: 'Power Spectral Density (PSD)',
            selected: state.currentView == AppView.psd,
            onTap: () => _selectView(AppView.psd),
          ),
          _SideBarItem(
            label: 'Streaming',
            selected: state.currentView == AppView.streaming,
            trailing: const StreamDot(),
            onTap: () => _selectView(AppView.streaming),
          ),
          _SideBarItem(
            label: 'Settings',
            selected: state.currentView == AppView.settings,
            onTap: () => _selectView(AppView.settings),
          ),
        ],
      ),
    );
  }

  /// Body area: the current view plus the connect window. On wide screens the
  /// sidebar is a squishing Row sibling and the body is fully usable while the
  /// menu is open; on narrow screens the sidebar overlays the full-size body
  /// behind a dim, tap-away scrim.
  Widget _buildContent(
      BuildContext context, AppUiState state, Widget body) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final connectOverlay = state.connectWindowOpen
        ? const ConnectOverlay()
        : const SizedBox.shrink();

    if (isWide) {
      return Row(
        children: [
          if (state.sidebarOpen) _buildSidebar(context, state),
          Expanded(
            child: Stack(children: [body, connectOverlay]),
          ),
        ],
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Stack(children: [body, connectOverlay]),
        ),
        if (state.sidebarOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(appStateProvider.notifier).setSidebar(false),
              child: Container(
                color: Theme.of(context).colorScheme.scrim.withAlpha(90),
              ),
            ),
          ),
        if (state.sidebarOpen)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: kSidebarWidth,
            child: _buildSidebar(context, state),
          ),
      ],
    );
  }
}

class _SideBarItem extends StatelessWidget {
  const _SideBarItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.card,
      color: const Color(0xFF1E212A),
      child: ListTile(
        title: Text(label),
        trailing: trailing,
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

  final permissions = [Permission.bluetoothScan, Permission.bluetoothConnect];

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
