# UI map

Spoken name → on-screen text → code → file. Grep the first two columns when a
human describes a bug. Frozen connect/pipeline names are mirrored, not renamed.

How to use: pick a surface, then match **Spoken name**.

Surfaces: Status bar · Sidebar · Connect · GraphShell · Raw EEG · Bands · HR+SpO2 ·
Histogram · PSD · Spectrogram · HR+SpO2 · History · Recording dashboard · Feedback
list · Session · Settings · Android capture notification.

## Chrome

### Status bar — `lib/src/status_bar.dart`

Hosted by `AppShell` and `FeedbackSessionView` (`showMenu: false` on session).
On **mobile**, landscape cinema on graph views hides this bar (and the sidebar
+ GraphShell toolbar); portrait restores. Desktop keeps chrome; **F11**
toggles the same hide. Not Settings / Feedback / Streaming / History.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Status bar | — | `StatusBar` | `status_bar.dart` | Height 56. |
| Hamburger / Menu | tooltip `Menu` | `toggleSidebar` | `status_bar.dart` | Hidden on session. |
| Tap to connect | `Not connected — tap to connect` | `toggleConnectWindow` | `status_bar.dart` | Center hit target. |
| Connecting | `Connecting to {name}…` | `connectingTo` | `status_bar.dart` | |
| Disconnecting | `Disconnecting…` | `disconnecting` | `status_bar.dart` | |
| Device name | `status.name` (e.g. `Muse 2 (Simulated)`) | `ConnectionStatus.name` | `status_bar.dart` | After connect. Elides when chrome is tight; **signal pads keep priority**. |
| Signal pads | `/‾‾\` (Muse 4) or Crown ring of `•` | `signalQualityRow` | `status_bar.dart` | Head pads of `lastConnectedKind`. Muse AUX (Classic 1, Athena up to 4) inserts `•` between the overlines: `/‾•‾\` … `/‾••••‾\`. Crown is eight `•` in a top-down ring (front F5/F6, then C3/C4, CP3/CP4, back PO3/PO4), same 18px glyph, about one line tall. Green ≥ 80, orange ≥ 40, red below. |
| Battery | `{n}%` | `batteryLevel` | `status_bar.dart` | From `bp`, not fuel gauge. |
| Signal pads | `/‾‾\` or `/‾••••‾\` | `signalQualityRow` | `status_bar.dart` | TP9 AF7, then AUX dots when Devices → Muse Aux channels is on, then AF8 TP10. Classic one dot, Athena four. Hidden while that switch is off. Updates immediately. Green ≥80, amber ≥40, red <40. Never elided for a long device name. [headset-fit.md](headset-fit.md). |
| Disconnect | tooltip `Disconnect` | `disconnectDevice` | `status_bar.dart` | Icon `link_off`. |

### Sidebar — `lib/src/app.dart`

Width `kSidebarWidth` (220). Overlay below 700px; row sibling at ≥ 700.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Feedback | `Feedback` | `AppView.feedback` | `app.dart` | Body: `FeedbackListView`. |
| History | `History` | `AppView.feedbackHistory` | `app.dart` | Label only. Enum stays `feedbackHistory`. Filter All \| Feedback \| Recordings. |
| Bands | `Bands` | `AppView.bands` | `app.dart` | GraphShell. `monitor/views/bands_view.dart`. |
| Raw EEG | `Raw EEG` | `AppView.rawEeg` | `app.dart` | Sweep. `monitor/views/raw_eeg_view.dart`. |
| Histogram | `Histogram` | `AppView.histogram` | `app.dart` | After Raw EEG. `monitor/views/histogram_view.dart`. |
| Spectrogram | `Spectrogram` | `AppView.spectrogram` | `app.dart` | `monitor/views/spectrogram_view.dart`. |
| PSD | `PSD` | `AppView.psd` | `app.dart` | Short label. Title `Power Spectral Density`. |
| HR+SpO2 | `HR+SpO2` | `AppView.hrSpo2` | `app.dart` | Dual-pane optical. Follow: no top highlight; bottom IR PPG sweeps. Inspect: highlight + walking PPG. `monitor/views/hr_spo2_view.dart`. |
| Streaming | `Streaming` | `AppView.streaming` | `app.dart` | Trailing `StreamDot`. |
| Settings | `Settings` | `AppView.settings` | `app.dart` | |

### GraphShell — `lib/src/monitor/graph_shell.dart`

Shared chrome for the five live graph views. Record is global
(`MonitorController`); Follow/Inspect and window length are per-view.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Follow | `Follow` | `ViewportMode.follow` | `viewport_controller.dart` | Live graph views only. Hidden on the saved-recording dashboard. |
| Inspect | `Inspect` | `ViewportMode.inspect` | `viewport_controller.dart` | Freeze. Drag/pinch on time-X graphs enters Inspect. |
| Window length | `10s` / `30s` / … | `windowOptions` | `graph_shell.dart` | Per-view presets. Pinch-X on Bands/Spectrogram → `custom`. |
| Record | `Record` | `_RecordControls` | `graph_shell.dart` | All five **live** views. Starts `recording_$ts`. Clears the live graph, new capture clock, enters Follow. |
| Stop recording | `Stop recording` | `_RecordControls` | `graph_shell.dart` | Assemble + Save/Discard. Clears the live graph, keeps drawing new samples, enters Follow. Elapsed while recording. |
| Record disabled | tooltip `Stop the feedback session to record` | `_RecordControls` | `graph_shell.dart` | `CaptureKind.feedback` or disconnected. |
| Landscape cinema | — | `GraphCinema` | `graph_cinema.dart` | Graph views only. **Mobile:** landscape hides status bar, sidebar, GraphShell toolbar; portrait restores. **Desktop:** chrome stays; **F11** toggles the same hide. Not Settings / Feedback / Streaming / History. |
| Chrome overflow | chevron | `_PannableChromeRow` | `graph_shell.dart` | Whole toolbar pans when Follow/Inspect + electrodes overflow; mouse/touch drag anywhere on the row (incl. over chips); chevron jumps to end. |
| Waiting for signal | `Waiting for signal` | `MonitorWaitingSignal` | `empty_state.dart` | Connected, no samples yet. |

### Connect window — `lib/src/connect_window.dart`

Must exist in every view with a status bar (`AppShell` + session). Frozen:
[connect-simulator-ux.md](connect-simulator-ux.md).

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Connect window / overlay | `Connect to a device` | `ConnectOverlay` / `ConnectWindow` | `connect_window.dart` | Tap barrier closes it. |
| Connect status copy | `Connecting… (attempt N)`, scan results | `scanMessage` | `connect_window.dart` | Cleared to null after a successful connect. |
| Device type dropdown | `Device type` | `ConnectSource` / `switchConnectSource` | `connect_source.dart`, `connection_provider.dart` | Muse \| Neurosity; + Simulator iff Debug. A different type disconnects the current headset first, then scans that type (Muse BLE, Neurosity OSC, Simulator catalog). If the headset stays connected, the window shows `Could not disconnect. Stay on this device and try again.` and the dropdown stays on the old type. |
| Recording in progress | `Recording in progress` | `confirmDeviceTypeChange` | `device_type_switch.dart` | Disconnect / Cancel while a GraphShell recording is open. Cancel stays on the current headset. Disconnect leaves the recording open, then scans the new type. |
| Session in progress | `Session in progress` | `confirmDeviceTypeChange` | `device_type_switch.dart` | Disconnect / Cancel during calibration or a playing / paused / interrupted feedback session. Disconnect ends a playing, paused, or interrupted session. |
| Rescan | `Rescan` | `openConnectWindowAndScan` | `connect_window.dart` | **Hidden** on Simulator, and while connected or connecting. |
| Neurosity list | Crown nickname (e.g. `Crown-LOC`), device id below | `_runCrownDiscovery` / `discoveredCrowns` | `connection_provider.dart` | OSC LAN discovery on UDP 9000 (`/info` or any `/neurosity/notion/{id}/…`), refreshed 1 s, entries drop after 5 s silence. No BLE. |
| Neurosity empty copy | `No Crown found on this Wi-Fi. The Crown must be on the same network and have OSC streaming turned on.` | `emptyDevicesCopy` | `connect_source.dart` | Shown after a 3 s listening spinner; discovery keeps running. |
| Simulator · Muse 2 | `Muse 2` | `sim:muse-2` | `connect_source.dart` | Startable. Connected name `Muse 2 (Simulated)`. |
| Simulator · Muse S | `Muse S` | `sim:muse-s` | `connect_source.dart` | Startable. |
| Simulator · Muse S Athena | `Muse S Athena` | `sim:muse-s-athena` | `connect_source.dart` | Classic 3-ch PPG only. |
| Simulator · Crown (OSC) | `Crown (OSC)` | `sim:crown-osc` | `connect_source.dart` | Kind Neurosity. 8-ch sessions. |
| Simulator · Notion (OSC) | `Notion (OSC)` | `sim:notion-osc` | `connect_source.dart` | Kind Neurosity. 8-ch sessions. |

## Views

### Raw EEG — `lib/src/monitor/views/raw_eeg_view.dart`

GraphShell chrome. No electrode chips (each electrode is a pane). No
add/remove.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Follow | `Follow` | `ViewportMode.follow` | `viewport_controller.dart` | Live green wipe. |
| Inspect | `Inspect` | `ViewportMode.inspect` | `viewport_controller.dart` | Freeze + pan. Drag/pinch enters Inspect. |
| Window length | `2s` `4s` `8s` `10s` | `ViewportController.windowSeconds` | `graph_shell.dart` | Default **10 s** (2560 samples). No `custom`. |
| Electrode name | `TP9` / Crown names | `SweepPane` | `panes/sweep_pane.dart` | In-pane, top-right, gray. Not a chip. |
| Y scale | `Auto` / `±50 µV` … | `SharedYScale` | `sweep_pane.dart` | Overflow. One scale for the column. |

### Bands — `lib/src/monitor/views/bands_view.dart`

GraphShell chrome. One strip pane, five series (delta / theta / alpha /
beta / gamma). Electrode text toggles are average membership, not extra
graphs. In-pane band chips toggle series visibility.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Follow | `Follow` | `ViewportMode.follow` | `viewport_controller.dart` | Strip slides at display rate with ~1 s lead. Not Live / History. |
| Inspect | `Inspect` | `ViewportMode.inspect` | `viewport_controller.dart` | Freeze; pan / pinch-X. Drag or pinch enters Inspect. Cache still 1 Hz; no Follow ticker. |
| Window length | `15s` `30s` `60s` `120s` | `ViewportController.bandsWindowOptions` | `graph_shell.dart` | Default **30 s**. |
| Custom window | `custom` | `windowIsPreset` | `graph_shell.dart` | Closed label after pinch-X. Picking a preset restores. |
| Electrode toggle | `TP9` / Crown names | `ElectrodeToggles` | `electrode_toggles.dart` | Top-right, depressed = in the mean. Default all on. Last one stays. Whole GraphShell chrome row pans on overflow (drag anywhere); chevron jumps to end. Electrode chips are not a separate scroller. |
| Band toggle | `delta` / `theta` / `alpha` / `beta` / `gamma` | `BandToggles` | `band_toggles.dart` | In-pane, top-right overlay. Depressed = visible. Last one stays. Label color = line. |
| Y unit | `dB` | `linearToDb` | `panes/time_series_pane.dart` | `10·log10` of linear µV²/Hz. 0 is not the floor. |
| Waiting for signal | `Waiting for signal` | `MonitorWaitingSignal` | `empty_state.dart` | Connected, no BandCache samples. |

### Histogram — `lib/src/monitor/views/histogram_view.dart`

GraphShell chrome. ~70% histogram + ~30% Bands context strip
(`HistogramPsdSplit` flex 7/3). Mean of selected electrodes drives both
panes. No time slider. Histogram X is µV (no pinch-`custom`). Recording
dashboard Histogram is **one pane** (no strip).

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Follow | `Follow` | `ViewportMode.follow` | `viewport_controller.dart` | Last T seconds. Highlight flush-right on the strip; slides with the Follow-lead ticker (not 1 Hz). |
| Inspect | `Inspect` | `ViewportMode.inspect` | `viewport_controller.dart` | Freeze. Chrome `m:ss–m:ss`. Drag highlight to move epoch; drag outside pans strip. Pinch-X on strip. |
| Window length | `2s` `4s` `8s` | `histogramPsdWindowOptions` | `graph_shell.dart` | Default **8 s**. Highlight width = T. |
| µV range | `±100 µV` | `HistogramUvRange` | `histogram_view.dart` | Own domain. Overflow ±50 / ±200. Not Raw EEG Y-scale. |
| Electrode toggle | `TP9` / Crown names | `ElectrodeToggles` | `electrode_toggles.dart` | Average membership for histogram **and** strip. Last one stays. Overflow → whole chrome row pans + end chevron (GraphShell). |
| Hairline | `−12 µV   48` | tap on pane | `histogram_pane.dart` | Tap, not drag. |
| Bands context strip | `30s` / `custom` | `BandsContextStrip` | `panes/bands_context_strip.dart` | Default **30 s**. Pinch-X like Bands. Compact dropdown on the strip, not GraphShell. |
| Landscape cinema | — | `GraphCinema` | `graph_cinema.dart` | **Mobile** landscape hides chrome + strip `30s ▾` (both panes stay). **Desktop** keeps chrome; **F11** hides the same (including the strip dropdown). |

### PSD — `lib/src/monitor/views/psd_view.dart`

GraphShell title `Power Spectral Density`. Same 70/30 split and Bands
context strip as Histogram. Welch of last T seconds. Recording dashboard
PSD is **one pane** (no strip). FFT 1 s / 256-pt (not the Spectrogram
window).

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Follow | `Follow` | `ViewportMode.follow` | `viewport_controller.dart` | Last T seconds. Highlight flush-right on the strip; slides with the Follow-lead ticker (not 1 Hz). |
| Inspect | `Inspect` | `ViewportMode.inspect` | `viewport_controller.dart` | Freeze. Chrome `m:ss–m:ss`. Drag highlight to move epoch; drag outside pans strip. Pinch-X on strip. |
| Window length | `2s` `4s` `8s` | `histogramPsdWindowOptions` | `graph_shell.dart` | Default **4 s**. Highlight width = T. |
| Hz range | `0–60 Hz` | `PsdHzRange` | `psd_view.dart` | Overflow `0–100 Hz`. |
| Electrode toggle | `TP9` / Crown names | `ElectrodeToggles` | `electrode_toggles.dart` | Average membership for PSD **and** strip. Last one stays. Overflow → whole chrome row pans + end chevron (GraphShell). |
| Hairline | `10.2 Hz   −8.4 dB` | tap on pane | `psd_pane.dart` | Tap, not drag. |
| Alpha peak | `{n} Hz` | `alphaPeakHz` | `dsp.dart` | Argmax 8–13 Hz. |
| Bands context strip | `30s` / `custom` | `BandsContextStrip` | `panes/bands_context_strip.dart` | Same strip as Histogram. Spectrogram does **not** get this strip. |

### Spectrogram — `lib/src/monitor/views/spectrogram_view.dart`

Keep `AppView.spectrogram`. No Bands strip. STFT is 1 s / 256-pt Hamming.
No `FFT 1s ▾`.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Follow | `Follow` | `ViewportMode.follow` | `viewport_controller.dart` | ~1 s Follow lead + vsync ticker (same as Bands); newest second off-screen right. Hop from absolute newest (not capped sampleCount) so Follow continues after ~5 min wrap. Empty chart = theme surface. |
| Inspect | `Inspect` | `ViewportMode.inspect` | `viewport_controller.dart` | Freeze; pan / pinch-X. |
| Window length | `10s` `20s` `30s` `2min` `5min` | `spectrogramWindowOptions` | `graph_shell.dart` | Default **20 s**. Pinch-X → `custom`. Cap 5 min. |
| Custom window | `custom` | `windowIsPreset` | `graph_shell.dart` | Closed label after pinch-X. |
| Magnitude | `mag ▾` | dual-thumb RangeSlider | `spectrogram_view.dart` | Color min/max of log power. Not Hz. Not auto-pumping. |
| Electrode toggle | `TP9` / Crown names | `ElectrodeToggles` | `electrode_toggles.dart` | Average membership. Last one stays. Overflow → whole chrome row pans + end chevron (GraphShell). |

### History — `lib/src/views/feedback_history.dart`

Sidebar **History** (`AppView.feedbackHistory`). One sqlite list; no
`AppView.recordings`. Recording thumbnails are not sparklines.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| History | `History` | `FeedbackHistoryView` | `feedback_history.dart` | Headline. Sidebar same label. |
| Filter All | `All` | `HistoryKindFilter.all` | `feedback_history.dart` | Default. |
| Filter Feedback | `Feedback` | `HistoryKindFilter.feedback` | `feedback_history.dart` | `kind = feedback` → `FeedbackDashboardView`. |
| Filter Recordings | `Recordings` | `HistoryKindFilter.recordings` | `feedback_history.dart` | `kind = recording` → `RecordingDashboardView`. |
| Recording row | `Recording • {date}` | `SessionSummary.isRecording` | `feedback_history.dart` | Opens `monitor/views/recording_dashboard.dart`. Graph chips are inspect-only. |
| Export | `PDF report` / `PNG thumbnail` / `PNG charts` / `CSV (Mind Monitor)` / `EDF+ raw EEG` | `ExportKind` | `feedback_history.dart` | PDF / PNG charts feedback only; thumbnail / CSV / EDF+ also for recordings. Lossy imports add `Imported from … — already lost on import: …` to the result. [export.md](export.md). |
| Import | `Import…` | `_importRecording` | `feedback_history.dart` | App bar next to Refresh; picks `.edf` / `.csv`. |
| Import summary | `Import recording?` / `Import with losses?` · `Kept` · `Lost or changed` · `Cancel` / `Import` | `_confirmImport` | `feedback_history.dart` | Shown before every import is saved; lost list = `import.warnings`. |
| Import interval warning | `This Mind Monitor file was recorded with one row every {N} seconds, so it covers only about {X}% of the session. Short events can be missed, so expect lower result quality. For better results, set Mind Monitor's recording interval to 1 second.` | `intervalCoverageWarning` | `import_summary.dart` / `feedback_history.dart` | Warning box at the top of the import summary when `import.recordingInterval ≥ 1.9` s. None for Constant, ≤ 1 s intervals and EDF. |
| Folder-change dialog | `Move existing files?` · `Move` / `No` · `Move {s} session(s) and {r} recording(s) into the new folder? Choosing No leaves them in the current folder.` | `folderChangeMoveBody` | `settings_view.dart` | Asks only when something would move. Dismiss keeps the folder. **No** switches and leaves files. Body also names `export`, `cache`, and `AI models` when those trees contain a file. Empty trees do not count. `.cache/tmp_*` does not count and is deleted. |
| Muse Aux channels | `Muse Aux channels` | `Settings.museAuxEnabled` / `_MuseCard` | `settings_view.dart` | Devices section, Muse card. Default off. Shows AUX on the status bar and in the monitors immediately (Classic AUX1, Athena AUX1–AUX4). A real Muse already sends them. A simulated Muse does the same: Muse 2 and Muse S are one AUX channel, Muse S Athena is four. Pref `muse_aux_channels`. |
| Record AUX channels | `Record AUX channels` | `Settings.recordAux` / `_RecordingCard` | `settings_view.dart` | Recording section, Session recording card. Default on. Grayed, with a Devices note, while Muse Aux channels is off. Saves AUX in the next recording or feedback session. Does not change the status bar. |
| Crown quality source | `Crown` card: `Crown` / `App` radios | `Settings.crownQualitySource` / `_CrownCard` | `settings_view.dart` | Devices section. Default `Crown` (Crown per-pad quality averaged per second, app score for seconds without it); `App` = app score only. Pref `crown_quality_source`. Applies on next connect (`connectWithOptions(qualitySource:)`). |

### Recording dashboard — `lib/src/monitor/views/recording_dashboard.dart`

History row `kind = recording`. Graph chips are inspect-only: the
Follow / Inspect control is hidden. Chip order is **Dashboard**, **Bands**, **Raw EEG**, **Histogram**,
**PSD**, **Spectrogram**, **HR+SpO2**, **Movement**. Opening a recording still lands on **Bands**
(metadata + computed via two prefix reads). Raw body lazy-loads on Raw EEG /
Histogram / PSD / Spectrogram. HR+SpO2 always loads the raw body to look for
infrared PPG, and Movement loads raw only when computed frames omit the
metric. Histogram/PSD have **no** Bands strip.
**Dashboard** is the summary block, with no graphs.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Graph switcher | `Dashboard` `Bands` `Raw EEG` `Histogram` `PSD` `Spectrogram` `HR+SpO2` `Movement` | `RecordingDashGraph` | `recording_dashboard.dart` | SegmentedButton. `Dashboard` is first. Default **Bands**. |
| Dashboard | `Dashboard` | `RecordingDashGraph.dashboard` / `HistoryDashboardSummary` | `recording_dashboard.dart` / `history/history_dashboard_summary.dart` | Summary from nested `stats` plus `durationS` (else `elapsedSeconds`). No feedback totals, so in-zone and chime cells are absent. No graphs. |
| HR+SpO2 | `HR+SpO2` | `RecordingDashGraph.hrSpo2` / `OpticalOverviewPane` / `OpticalPpgPane` | `recording_dashboard.dart` | Same overview as sidebar HR+SpO2 (HR 40–200 bpm, SpO₂ 50–100%). Window 15/30/60/120, default 30 s. When the raw body has infrared PPG (channel 1), a lower IR strip uses 2/4/8/10 s, default 10 s (`history-hr-spo2-detail-window`, tooltip `IR PPG window`). The highlight tracks the overview’s visible end. No strip and no warning when the file has no IR samples. No electrode toggles. |
| Movement | `Movement` | `RecordingDashGraph.movement` / `MovementPane` | `recording_dashboard.dart` / `monitor/panes/movement_pane.dart` | Inspect-only linear series, 0–1.5 g, color same family as the old movement trace. Same window family as HR+SpO2. No live sidebar Movement view. No electrode toggles. |
| More | `More` | `Settings.historyDashboardMoreExpanded` | `history/history_dashboard_summary.dart` | Fold under the summary. Pref `history_dashboard_more_expanded`, default closed. One flag for both History pages. |
| Follow / Inspect | — | `followEnabled: false` | `graph_shell.dart` | Hidden on graph chips. The window length control stays. |
| Magnitude | `mag ▾` | `_magMenu` | `recording_dashboard.dart` | Spectrogram graph only. Same as live. |
| Hz range | `0–60 Hz` | `PsdHzRange` | `recording_dashboard.dart` | PSD graph. Overflow `0–100 Hz`. |
| µV range | `±100 µV` | `HistogramUvRange` | `recording_dashboard.dart` | Histogram graph. |

### Feedback list — `lib/src/views/feedback_list.dart`

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Feedback list | `Biofeedback Protocols` | `FeedbackListView` | `feedback_list.dart` | |
| Create program | `Create program` | `ProtocolBuilderView` | `protocol_builder.dart` | |
| Protocol card | catch phrase (e.g. `Sleep-Edge Rest`) | `ProtocolDocument` | `feedback_list.dart` | Tap → session route. Catalog copy names the reward electrodes as `the target electrode pair (Muse AF7/AF8, Crown PO3/PO4)`. |
| recordOnly | catalog copy | id `recordOnly` | `assets/protocols.json` | Skip-cal button. Agent smoke protocol. |

### Feedback session — `lib/src/views/feedback_session.dart`

Pushed route, **not** an `AppView`. HTTP smoke drives the notifier only (no
route). Engine: `FeedbackStateNotifier.startCalibration`.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Start Session | `Start Session` | `_PhaseControls.startSession` | `feedback_session.dart` | Crown → dialog. Recording → dialog. |
| Start skip-cal | `Start (skip calibration)` | `startCalibration(skipCalibration: true)` | `feedback_session.dart` | recordOnly. |
| Calibration Skip | `Skip` | `skipCalibration` | `feedback_session.dart` | Next to `Cancel`. Debug mode only. Simulator: canned baseline. Real device: last baseline for this device id; hidden until one exists. |
| Recording refused dialog | `Recording in progress` / `Stop the recording before starting a session.` | `_refuseRecordingStart` | `feedback_session.dart` | Actions `Cancel` / `Stop recording`. Start is not auto-continued. |
| Save recording | `Save recording?` | `RecordingSaveDiscardDialog` | `monitor/views/recording_save_discard.dart` | Body `Save this recording to History, or discard it.` Actions `Save` / `Discard`. `barrierDismissible: false`. GraphShell Stop, session-view Stop, in-app disconnect. |
| Incomplete recording | `Incomplete recording detected` | `RecordingSaveDiscardDialog` | `monitor/views/recording_save_discard.dart` | Launch leftover `recording_*`. Same widget; title only. |
| Incomplete session | leftover `session_*` reopens summary | `showCrashRecoveryDialog` | `feedback/crash_recovery.dart` | Launch leftover `session_*` → `FeedbackDashboardView` (Save/Discard). Not a dialog. Not the recording dialog. |
| Pause / Resume / End | phase controls | `pause` / `resume` / `end` | `feedback_state.dart` | Stop control still ends immediately. |
| Leave session | `End session?` / `Going back stops this feedback session.` | `SessionBackGuard` | `feedback/session_leave.dart` | AppBar back and system back while calibrating, playing, paused, or interrupted. Actions `Cancel` / `End session`. Cancel (button, barrier, or a back that closes the dialog) stays and the session keeps running. End session runs `end()` and does not pop; the summary replaces this route. Idle back leaves with no dialog. Ended does not pop. A second back while the dialog is open or `end()` is running does not end twice. iOS edge swipe is blocked while the session is in progress (PopScope); use the back button. |
| Guide | `Guide` | `_GuideCard` | `feedback_session.dart` | Bottom, under Pause/End. |
| Session Settings | `Session Settings` | `_SessionSettingsCard` | `feedback_session.dart` | Idle, playing, paused. |
| Feedback Sound | `Feedback Sound` | `_FeedbackTile` | `feedback_session.dart` | Tap picks output. Gear opens Target Settings: reward threshold plus 0–2 inhibit ceiling sliders. |
| Guardrail | `Guardrail` | `_GuardrailTile` | `feedback_session.dart` | Same layout as Feedback Sound. Tap opens scorer dialog (enable switch top right, engine, warning sound). Gear opens warning threshold; AI also shows the fixed δ ceiling. |
| Reward chip | `Reward` | `TrustChipRow` | `feedback/trust/trust_chips.dart` | Depressed = on. Default on. Omitted without a reward lane. Persist `Settings.trustRewardVisible`. |
| Guard chip | `Guard` | `TrustChipRow` | `feedback/trust/trust_chips.dart` | Default off; **on** when Reward is omitted (`guardrailOnly`). Omitted when protocol has no guard or Session Settings guard is `none`. Persist `Settings.trustGuardVisible`. |
| More chip | `More` | `TrustChipRow` | `feedback/trust/trust_chips.dart` | Default on. Readouts under visible lane(s). `recordOnly` hides the whole row. Persist `Settings.trustMoreVisible`. |
| Reward graph | catalog `shortLabel` (`ATR` / `TAR` / `BTR` / `α`) | `RewardTrustPane` | `feedback/trust/trust_pane.dart` | Playing/paused only. Follow-only, default 75 s. Not `% calm`. Gray **wash** only while inhibit is out (any reward Y). Stroke stays series color. Dirty is dotted. |
| Inhibit graph | `β` / `δ` / `inhibit` | `InhibitTrustPane` | `feedback/trust/trust_pane.dart` | Under Reward when the protocol has inhibit. Same Follow window. One pane per ceiling (0 / 1 / 2). Ceiling line matches series color. Overshoot uses a distinct hue-keeping color. Hidden if Reward is off. |
| Guard graphs | `warn` / `δ ceiling` | `GuardWarnPane` / `GuardCeilingPane` | `feedback/trust/trust_pane.dart` | Playing/paused only. Pane count from `trustGuardPaneSpecs`: band-math = warn only; AI = warn + δ ceiling. |
| Held back | `beta high` / `delta high` | `TrustInhibitSpec.overshootLabel` | `feedback/trust/trust_inhibit.dart` | Labels on the inhibit pane at zone-exit. More verdict `Held back` is still above-the-line + inhibit fail. |
| Noisy | `pads` / `movement` / dotted | dirty run | `trust_runs.dart` | Isolated 1 s blink = dotted, no text. |
| Blink mark / Jaw mark | `Blink` / `Jaw` | `TrustGestureMark` | `feedback/trust/trust_trace.dart` | Live ring even if Gesture markers persist is off. Not eye up/down. |
| Reward More | `In zone` / `Below the line` / `Noisy — not counting` / `Held back` | `TrustRewardMore` | `feedback/trust/trust_more.dart` | Strip + Now rail + Hold. Strip glyphs from the first sample. |
| Guard More | `Warning` / `Quiet` / `Noisy` | `TrustGuardMore` | `feedback/trust/trust_more.dart` | One block under the guard pane(s). |
| Nerd stats | science icon / sheet title `Nerd` | `NerdSheet` | `feedback/trust/nerd_sheet.dart` | App-bar science icon opens the sheet. Piles + band stack + (i) rows. Old bubble gone. Guard block only if the lane ran. Cooldown 20 s is nerd-only. Feature probe stays debug+sim, not in the sheet. |
| Feature probe | `Feature probe` | `_FeatureProbeCard` | `feedback_session.dart` | Debug + sim connected only. Master switch + one slider per present feature id. Below Session Settings. Not in the nerd sheet. |

### Feedback summary — `lib/src/views/feedback_dashboard.dart`

Pushed after End (`pushReplacement` from the session route). Leftover
`session_*` scratch at launch opens the same screen. Not an `AppView`.
Chip row is **Dashboard**, then **Feedback** when the session has a reward
or guard lane, then **Bands**, **Raw EEG**, **Histogram**, **PSD**,
**Spectrogram**, **HR+SpO2**, **Movement**. Opening a feedback session lands on **Dashboard**.
`recordOnly` has no Feedback chip. Graph chips are the same inspect-only
graphs as a recording (`HistorySignalGraphs`). The Dashboard chip has no
graphs. The music track list and the gesture-marker list stay under the
summary when the file has them. Alpha vs Theta, the old relative-power
Bands chart, Movement score, Heart rate / SpO₂, the sleep guardrail
chart, and the music cutoff chart do not.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Session summary | `{protocol} — Session` | `FeedbackDashboardView` | `feedback_dashboard.dart` | Live (`readOnly: false`) or History (`readOnly: true`). |
| Dashboard | `Dashboard` | `_SessionSummaryChip.dashboard` / `HistoryDashboardSummary` | `feedback_dashboard.dart` / `history/history_dashboard_summary.dart` | Default chip. Summary from nested `stats` plus the trust reader. No graphs. Music track list and gesture markers stay when present. |
| Feedback | `Feedback` | `_SessionSummaryChip.feedback` / `HistoryTrustReplay` | `feedback_dashboard.dart` / `history/history_trust_viewport.dart` | After Dashboard, before the graph chips. Omitted when the trust reader has no reward lane and no guard lane (`recordOnly`, recordings). Replays `RewardTrustPane` / `InhibitTrustPane` / `GuardWarnPane` / `GuardCeilingPane` with `showMore` off (no verdict, glyph strip, needle, or "in for Ns"). |
| Graph switcher | `Bands` `Raw EEG` `Histogram` `PSD` `Spectrogram` `HR+SpO2` `Movement` | `_SessionSummaryChip` / `HistorySignalGraphs` | `feedback_dashboard.dart` / `recording_dashboard.dart` | Same order as a recording, after Feedback when that chip exists. Inspect-only. One chip visible at a time. |
| More | `More` | `Settings.historyDashboardMoreExpanded` | `history/history_dashboard_summary.dart` | Fold under the summary on the Dashboard chip. Pref `history_dashboard_more_expanded`, default closed. Same flag as the recording Dashboard. Not on the Feedback chip. |
| Reward | `Reward` | local toggle on `HistoryTrustReplay` | `history/history_trust_viewport.dart` | Feedback chip only. Depressed = on. Default on when reward samples exist. Does not write `Settings.trustRewardVisible`. |
| Guard | `Guard` | local toggle on `HistoryTrustReplay` | `history/history_trust_viewport.dart` | Feedback chip only. Default off, except on when there is no reward lane and guard samples exist (`guardrailOnly`). Does not write `Settings.trustGuardVisible`. Omitted when the saved guard feature has no pane. |
| Trust window | `m:ss – m:ss` | `HistoryTrustViewport` | `history/history_trust_viewport.dart` | Default 75 s ending at the last sample. Drag pans. Pinch and Ctrl/Meta+scroll zoom, clamped 15–300 s. Right edge is the view end, not now. Not live `TrustViewport`. |
| Reward footer | `{n}% in zone · {n} chimes · {n}% inhibited` | `historyRewardFooter` | `history/history_trust_viewport.dart` | Whole session, not the visible window. Hidden when there is no reward lane. Null percent is `—`. |
| Guard footer | `{n}% warning · {n} chimes` | `historyGuardFooter` | `history/history_trust_viewport.dart` | Whole session. Adds ` · {n}% over ceiling` only when the ceiling pane is in the spec. |
| Back | AppBar leading / system back | `PopScope` | `feedback_dashboard.dart` | **Blocked** on the live unsaved summary (`canPop: false` while scratch remains). Must Save or Discard. History: warn if notes dirty. |
| Save | `Save` | `_save` | `feedback_dashboard.dart` | App bar. Live unsaved summary only. Publishes scratch `.neurofeed` to History. |
| Discard | `Discard` | `_discard` | `feedback_dashboard.dart` | App bar. Live unsaved summary only. Deletes scratch `.neurofeed`. |
| Notes | `Notes` | `_notes` | `feedback_dashboard.dart` | Editable on the Dashboard chip. History detail shows a save icon when the notes are dirty. |
| Thumbnail | — | `_thumbKey` | `feedback_dashboard.dart` | Capture of the summary block (`HistoryDashboardSummary`), not a trust graph. |
| HR+SpO2 | `HR+SpO2` | `_SessionSummaryChip.hrSpo2` | `feedback_dashboard.dart` | Same chip as the recording page, including the IR strip when the file has infrared PPG. |
| Movement | `Movement` | `_SessionSummaryChip.movement` | `feedback_dashboard.dart` | Same chip as the recording page. |

### Settings — `lib/src/views/settings_view.dart`

In-page section list, separate from the app sidebar. At ≥ 640 px of the
settings pane the list stays on the left and the cards on the right. Below
that, the list is the page and a section opens its cards with Back. Search
is an icon (tooltip `Search settings`). The field matches every section. A
hit reads `{Section} · {card}`. Closing search returns to the section that
was open. Picking a hit opens that section and scrolls to the card.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Search settings | tooltip `Search settings` | `_openSearch` | `settings_view.dart` | Icon only. |
| General | `General` | `SettingsSection.general` | `settings_sections.dart` | Appearance, Subject, Music feedback, Audio (Android). |
| Appearance | `Appearance` | `_AppearanceCard` / `AppAppearance` | `settings_view.dart` | Name on the left, description under it (`Choose a light or dark theme, or follow this device.`), dropdown on the right (`System` / `Light` / `Dark`). Default System. Pref `theme_mode`. |
| Devices | `Devices` | `SettingsSection.devices` | `settings_sections.dart` | Muse, Crown. |
| AI | `AI` | `SettingsSection.ai` | `settings_sections.dart` | Guardrail AI engine, then Calibration. |
| Recording | `Recording` | `SettingsSection.recording` | `settings_sections.dart` | Save folder, Session recording, Gesture markers. |
| About | `About` | `SettingsSection.about` | `settings_sections.dart` | About card, then Debug mode. |
| Save folder | `Save files to folder` | `setSessionFolder` | `settings_view.dart` | Was `Save feedback to folder`. The current folder path is under the title (`save_folder_path`). |
| Reset folder | `Reset to default folder` | `_resetFolder` | `settings_view.dart` | Shown when a custom folder is set. Same move dialog as picking a folder. |
| Folder change blocked | `Session in progress` / `Recording in progress` · `Finish the session before changing the save folder.` / `Finish the recording before changing the save folder.` | `folderChangeBlock` | `settings_view.dart` | Running feedback, unsaved ended session, open recording, or a recording waiting for Save / Discard. |
| Session recording | `Session recording` | `_RecordingCard` | `settings_view.dart` | Stream toggles. Applies to **tmp, Record, and feedback**. |
| PPG | `PPG` | `RecordingStream.ppg` | `settings_view.dart` | Session recording card. Default on (a missing `record_streams` pref is every stream). Stores raw light channels. History draws infrared only when the file has channel 1. |
| Gesture markers | `Gesture markers` | `_GesturesCard` | `settings_view.dart` | |
| Subject | `Subject` | `_SubjectCard` | `settings_view.dart` | Stable id plus optional nickname. |
| Music feedback | `Music feedback` | `_MusicCard` | `settings_view.dart` | Persist cutoff on `onChangeEnd`. |
| Guardrail AI engine | `Guardrail AI engine` | `AiEngineCard` | `reve_card.dart` | Not “AI sleep guardrail”. |
| Calibration | `Calibration` | `CalibrationSettingsCard` / `Settings.calibrationMethod` | `settings_view.dart` | AI section, after Guardrail AI engine. `Default` / `Always staged`. The setting default is Default: AI labeling features use staged, other features use simple. Always staged overrides that. Description `Default calibration method for neurofeedback.` Pref `calibration_method` (`default` / `always_staged`). Applies to the next session. |
| Audio (Android) | `Audio` / `Reduce audio stutter` | `_AudioCard` | `settings_view.dart` | Hidden off Android. |
| About | `About` | `_AboutCard` | `settings_view.dart` | |
| Debug mode | `Debug mode` | `enableSimulatedDevices` | `settings_view.dart` | Last card, inside About. Shows Simulator. Also shows calibration `Skip`. |

### Android capture notification — `lib/src/spine/capture_foreground.dart`

Foreground service type `connectedDevice`, same process as Flutter/Rust.
Shown while `CaptureKind` is `recording` or `feedback`, and until Save/Discard
of an unsaved ended session or pending recording. **Not** for `tmp_`. Screen
is allowed to sleep. Stop asks Dart to stop capture; it does not disconnect BLE.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Recording notification | `Recording` + elapsed | `CaptureForegroundKind.recording` | `capture_foreground.dart` | Live Record. Elapsed `m:ss` / `h:mm:ss`. Tap opens the app. |
| Session notification | `Session` + elapsed | `CaptureForegroundKind.session` | `capture_foreground.dart` | Feedback keepable capture. |
| Notification Stop | `Stop` | `ACTION_REQUEST_STOP` | `CaptureForegroundService.kt` | Live only, not while Save/Discard. Requests `stopRecording` / `end`. |

## Session internals

| Spoken name | On-screen / log | Code symbol | File | Notes |
|---|---|---|---|---|
| Phase idle | `[feedback] phase=idle` | `FeedbackPhase.idle` | `feedback_phase.dart` | |
| Calibrating | `[feedback] phase=calibrating` | `FeedbackPhase.calibrating` | | Shared baseline: 45 s of clean signal, or 60 s wall. Countdown `Ns of clean signal left`. Debug `Skip` next to `Cancel`. |
| Playing | `[feedback] phase=playing` | `FeedbackPhase.playing` | | Agent asserts this. |
| Paused / interrupted / ended | matching log | `paused` / `interrupted` / `ended` | | |
| Reward lane | session audio | `RewardLane` | `reward_lane.dart` | Guard never modulates. Dirty skips `recordEpoch` / `onSample`. |
| Guard lane | protocol builder Guard | `GuardLane` | `guard_lane.dart` | Warns only. Dirty skips `evaluateWarning`. |
| Trust graphs | Reward / Guard / More | `TrustTrace` / `TrustViewport` | `feedback/trust/` | Follow-only; not GraphShell. Inhibit pane shares the Reward window. History Feedback chip uses `HistoryTrustViewport` and the reader lists, not `TrustTrace`. |
| Feature bus | — | `FeatureBus` | `feature_bus.dart` | |
| Feature probe latch | debug sliders | `FeatureOverride` | `feature_override.dart` | Replaces `FeatureDto.value` in `_onEvent` while playing. |

## Agent HTTP (debug)

Not a screen. `kDebugMode && --dart-define=NEUROFEED_AGENT=true`. See
[testing-guide.md](testing-guide.md) (Linux agent) and
`.grok/skills/neurofeed-run-linux/SKILL.md`.

| Spoken name | HTTP | Notes |
|---|---|---|
| Switch view | `POST /view` | `histogram` / `spectrogram` / `psd` / `feedbackHistory` / … |
| Record | `POST /record/start` | 412 `disconnected`; 409 `feedback_active`. |
| Stop recording | `POST /record/stop` | Assembles scratch; does not publish. |
| Start during Record | `POST /session/start` | 409 `recording_active` (after `not_connected`). |
| Start with unsaved summary | `POST /session/start` | 409 `unsaved_session`. Same for `POST /session/reset`. |
| Start a model-only guard without a Ready model | `POST /session/start` | 412 `model_not_ready` when the protocol's `guard.requiresModel` (sleepGuard) and the AI engine is not Ready (missing or still loading). |
