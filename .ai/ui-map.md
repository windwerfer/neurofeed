# UI map

Spoken name → on-screen text → code → file. Grep the first two columns when a
human describes a bug. Frozen connect/pipeline names are mirrored, not renamed.

How to use: pick a surface in the TOC, then match **Spoken name**.

## Chrome

### Status bar — `lib/src/status_bar.dart`

Hosted by `AppShell` and `FeedbackSessionView` (`showMenu: false` on session).
Landscape cinema on graph views hides this bar (and the sidebar + GraphShell
toolbar); portrait restores. Not Settings / Feedback / Streaming / History.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Status bar | — | `StatusBar` | `status_bar.dart` | Height 56. |
| Hamburger / Menu | tooltip `Menu` | `toggleSidebar` | `status_bar.dart` | Hidden on session. |
| Tap to connect | `Not connected — tap to connect` | `toggleConnectWindow` | `status_bar.dart` | Center hit target. |
| Connecting | `Connecting to {name}…` | `connectingTo` | `status_bar.dart` | |
| Disconnecting | `Disconnecting…` | `disconnecting` | `status_bar.dart` | |
| Device name | `status.name` (e.g. `Muse 2 (Simulated)`) | `ConnectionStatus.name` | `status_bar.dart` | After connect. |
| Battery | `{n}%` | `batteryLevel` | `status_bar.dart` | From `bp`, not fuel gauge. |
| Signal pads | `/ ‾ ‾ \` | `_signalQualityRow` | `status_bar.dart` | Green/amber/red. |
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
| Streaming | `Streaming` | `AppView.streaming` | `app.dart` | Trailing `StreamDot`. |
| Settings | `Settings` | `AppView.settings` | `app.dart` | |

### Connect window — `lib/src/connect_window.dart`

Must exist in every view with a status bar (`AppShell` + session). Frozen:
[connect-simulator-ux.md](connect-simulator-ux.md).

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Connect window / overlay | `Connect to a device` | `ConnectOverlay` / `ConnectWindow` | `connect_window.dart` | Tap barrier closes it. |
| Connect status copy | `Connecting… (attempt N)`, scan results | `scanMessage` | `connect_window.dart` | Cleared to null after a successful connect. |
| Device type dropdown | `Device type` | `ConnectSource` | `connect_source.dart` | Muse \| Neurosity; + Simulator iff Debug. |
| Rescan | `Rescan` | `openConnectWindowAndScan` | `connect_window.dart` | **Hidden** on Simulator. |
| Simulator · Muse 2 | `Muse 2` | `sim:muse-2` | `connect_source.dart` | Startable. Connected name `Muse 2 (Simulated)`. |
| Simulator · Muse S | `Muse S` | `sim:muse-s` | `connect_source.dart` | Startable. |
| Simulator · Muse S Athena | `Muse S Athena` | `sim:muse-s-athena` | `connect_source.dart` | Classic 3-ch PPG only. |
| Simulator · Crown (OSC) | `Crown (OSC)` | `sim:crown-osc` | `connect_source.dart` | Kind Neurosity. **Start refused.** |
| Simulator · Notion (OSC) | `Notion (OSC)` | `sim:notion-osc` | `connect_source.dart` | Kind Neurosity. **Start refused.** |

## Views

### Raw EEG — `lib/src/monitor/views/raw_eeg_view.dart`

GraphShell chrome. Record / Stop recording. No electrode chips
(each electrode is a pane). No add/remove.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Follow | `Follow` | `ViewportMode.follow` | `viewport_controller.dart` | Live wipe. Not Live / History. |
| Inspect | `Inspect` | `ViewportMode.inspect` | `viewport_controller.dart` | Freeze + pan. Drag/pinch enters Inspect. |
| Window length | `2s` `4s` `8s` `10s` | `ViewportController.windowSeconds` | `graph_shell.dart` | Default **10 s** (2560 samples). |
| Record | `Record` | `_RecordControls` | `graph_shell.dart` | Starts `recording_$ts`. Disabled when feedback or disconnected. |
| Stop recording | `Stop recording` | `_RecordControls` | `graph_shell.dart` | Assemble + Save/Discard. Elapsed while recording. |
| Record disabled | tooltip `Stop the feedback session to record` | `_RecordControls` | `graph_shell.dart` | `CaptureKind.feedback` or not connected. Landscape hides toolbar. |
| Waiting for signal | `Waiting for signal` | `MonitorWaitingSignal` | `empty_state.dart` | Connected, no samples. |
| Electrode name | `TP9` / Crown names | `SweepPane` | `panes/sweep_pane.dart` | In-pane, top-right, gray. Not a chip. |
| Y scale | `Auto` / `±50 µV` … | `SharedYScale` | `sweep_pane.dart` | Overflow. One scale for the column. |

### Bands — `lib/src/monitor/views/bands_view.dart`

GraphShell chrome. Record / Stop recording. One strip pane, five
series (delta / theta / alpha / beta / gamma). Electrode text toggles are
average membership, not extra graphs.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Follow | `Follow` | `ViewportMode.follow` | `viewport_controller.dart` | Strip, newest at right. Not Live / History. |
| Inspect | `Inspect` | `ViewportMode.inspect` | `viewport_controller.dart` | Freeze; pan / pinch-X. Drag or pinch enters Inspect. |
| Window length | `15s` `30s` `60s` `120s` | `ViewportController.bandsWindowOptions` | `graph_shell.dart` | Default **30 s**. |
| Custom window | `custom` | `windowIsPreset` | `graph_shell.dart` | Closed label after pinch-X. Picking a preset restores. |
| Electrode toggle | `TP9` / Crown names | `ElectrodeToggles` | `electrode_toggles.dart` | Top-right, depressed = in the mean. Default all on. Last one stays. |
| Y unit | `dB` | `linearToDb` | `panes/time_series_pane.dart` | `10·log10` of linear µV²/Hz. 0 is not the floor. |
| Waiting for signal | `Waiting for signal` | `MonitorWaitingSignal` | `empty_state.dart` | Connected, no BandCache samples. |

### Histogram — `lib/src/monitor/views/histogram_view.dart`

GraphShell chrome. Record / Stop recording. One pane (Column +
Expanded; PR 7 will add a Bands strip). Mean of selected electrodes.
No time slider. No pinch-`custom`.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Follow | `Follow` | `ViewportMode.follow` | `viewport_controller.dart` | Last T seconds. |
| Inspect | `Inspect` | `ViewportMode.inspect` | `viewport_controller.dart` | Freeze. Chrome `m:ss–m:ss`. |
| Window length | `2s` `4s` `8s` | `histogramPsdWindowOptions` | `graph_shell.dart` | Default **8 s**. |
| µV range | `±100 µV` | `HistogramUvRange` | `histogram_view.dart` | Own domain. Overflow ±50 / ±200. Not Raw EEG Y-scale. |
| Electrode toggle | `TP9` / Crown names | `ElectrodeToggles` | `electrode_toggles.dart` | Average membership. Last one stays. |
| Hairline | `−12 µV   48` | tap on pane | `histogram_pane.dart` | Tap, not drag. |
| Landscape cinema | — | `appViewIsGraph` | `app.dart` / `graph_shell.dart` | Hides status bar, sidebar, toolbar. |

### PSD — `lib/src/monitor/views/psd_view.dart`

GraphShell title `Power Spectral Density`. Record / Stop recording. Column +
Expanded (PR 7 hook). Welch of last T seconds.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Follow | `Follow` | `ViewportMode.follow` | `viewport_controller.dart` | Last T seconds. |
| Inspect | `Inspect` | `ViewportMode.inspect` | `viewport_controller.dart` | Freeze. Chrome `m:ss–m:ss`. |
| Window length | `2s` `4s` `8s` | `histogramPsdWindowOptions` | `graph_shell.dart` | Default **4 s**. |
| Hz range | `0–60 Hz` | `PsdHzRange` | `psd_view.dart` | Overflow `0–100 Hz`. |
| Electrode toggle | `TP9` / Crown names | `ElectrodeToggles` | `electrode_toggles.dart` | Average membership. Last one stays. |
| Hairline | `10.2 Hz   −8.4 dB` | tap on pane | `psd_pane.dart` | Tap, not drag. |
| Alpha peak | `{n} Hz` | `alphaPeakHz` | `dsp.dart` | Argmax 8–13 Hz. |

### Spectrogram — `lib/src/monitor/views/spectrogram_view.dart`

Keep `AppView.spectrogram`. Record / Stop recording. No Bands strip.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Follow | `Follow` | `ViewportMode.follow` | `viewport_controller.dart` | Newest column at right. |
| Inspect | `Inspect` | `ViewportMode.inspect` | `viewport_controller.dart` | Freeze; pan / pinch-X. |
| Window length | `10s` `20s` `30s` `2min` `5min` | `spectrogramWindowOptions` | `graph_shell.dart` | Default **20 s**. Pinch-X → `custom`. Cap 5 min. |
| Magnitude | `mag ▾` | dual-thumb RangeSlider | `spectrogram_view.dart` | Color min/max of log power. Not Hz. Not auto-pumping. |
| Electrode toggle | `TP9` / Crown names | `ElectrodeToggles` | `electrode_toggles.dart` | Average membership. Last one stays. |

### History — `lib/src/views/feedback_history.dart`

Sidebar **History** (`AppView.feedbackHistory`). One sqlite list; no
`AppView.recordings`. Recording thumbnails are not sparklines.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| History | `History` | `FeedbackHistoryView` | `feedback_history.dart` | Headline. Sidebar same label. |
| Filter All | `All` | `HistoryKindFilter.all` | `feedback_history.dart` | Default. |
| Filter Feedback | `Feedback` | `HistoryKindFilter.feedback` | `feedback_history.dart` | `kind = feedback` → `FeedbackDashboardView`. |
| Filter Recordings | `Recordings` | `HistoryKindFilter.recordings` | `feedback_history.dart` | `kind = recording` → `RecordingDashboardView`. |
| Recording row | `Recording • {date}` | `SessionSummary.isRecording` | `feedback_history.dart` | Opens `monitor/views/recording_dashboard.dart`. Follow disabled. |
| Folder-change dialog | `Move {s} session(s) and {r} recording(s) into the new folder? Choosing No leaves them in the current folder.` | `folderChangeMoveBody` | `settings_view.dart` | Counts both prefixes. |

### Feedback list — `lib/src/views/feedback_list.dart`

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Feedback list | `Biofeedback Protocols` | `FeedbackListView` | `feedback_list.dart` | |
| Create program | `Create program` | `ProtocolBuilderView` | `protocol_builder.dart` | |
| Protocol card | catch phrase (e.g. `Sleep-Edge Rest`) | `ProtocolDocument` | `feedback_list.dart` | Tap → session route. |
| recordOnly | catalog copy | id `recordOnly` | `assets/protocols.json` | Skip-cal button. Agent smoke protocol. |

### Feedback session — `lib/src/views/feedback_session.dart`

Pushed route, **not** an `AppView`. HTTP smoke drives the notifier only (no
route). Engine: `FeedbackStateNotifier.startCalibration`.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Start Session | `Start Session` | `_PhaseControls.startSession` | `feedback_session.dart` | Crown → dialog. Recording → dialog. |
| Start skip-cal | `Start (skip calibration)` | `startCalibration(skipCalibration: true)` | `feedback_session.dart` | recordOnly. |
| Crown refused dialog | `Crown sessions are not available yet…` | `crownSessionUnsupportedMessage` | `protocol.dart` | Real and sim Crown. |
| Recording refused dialog | `Recording in progress` / `Stop the recording before starting a session.` | `_refuseRecordingStart` | `feedback_session.dart` | Actions `Cancel` / `Stop recording`. Start is not auto-continued. |
| Save recording | `Save recording?` | `RecordingSaveDiscardDialog` | `monitor/views/recording_save_discard.dart` | `Save` / `Discard`. `barrierDismissible: false`. GraphShell Stop, session-view Stop, in-app disconnect. |
| Incomplete recording | `Incomplete recording detected` | `RecordingSaveDiscardDialog` | `monitor/views/recording_save_discard.dart` | Launch crash recovery of leftover `recording_*`. Same widget; title only. |
| Pause / Resume / End | phase controls | `pause` / `resume` / `end` | `feedback_state.dart` | |
| Feature probe | `Feature probe` | `_FeatureProbeCard` | `feedback_session.dart` | Debug + sim connected only. Master switch + one slider per present feature id. |

### Settings cards — `lib/src/views/settings_view.dart`

Order: Save folder, Session recording, Gesture markers, Music feedback,
Guardrail AI engine, Audio (Android only), About, Debug mode.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Save folder | `Save files to folder` | `setSessionFolder` | `settings_view.dart` | Was `Save feedback to folder`. |
| Session recording | `Session recording` | `_RecordingCard` | `settings_view.dart` | |
| Gesture markers | `Gesture markers` | `_GesturesCard` | `settings_view.dart` | |
| Music feedback | `Music feedback` | `_MusicCard` | `settings_view.dart` | Persist cutoff on `onChangeEnd`. |
| Guardrail AI engine | `Guardrail AI engine` | `AiEngineCard` | `reve_card.dart` | Not “AI sleep guardrail”. |
| Audio (Android) | `Audio` / `Reduce audio stutter` | `_AudioCard` | `settings_view.dart` | Hidden off Android. |
| About | `About` | `_AboutCard` | `settings_view.dart` | |
| Debug mode | `Debug mode` | `enableSimulatedDevices` | `settings_view.dart` | Last card. Shows Simulator. |

## Session internals

| Spoken name | On-screen / log | Code symbol | File | Notes |
|---|---|---|---|---|
| Phase idle | `[feedback] phase=idle` | `FeedbackPhase.idle` | `feedback_phase.dart` | |
| Calibrating | `[feedback] phase=calibrating` | `FeedbackPhase.calibrating` | | 50 s baseline unless skip. |
| Playing | `[feedback] phase=playing` | `FeedbackPhase.playing` | | Agent asserts this. |
| Paused / interrupted / ended | matching log | `paused` / `interrupted` / `ended` | | |
| Reward lane | session audio | `RewardLane` | `reward_lane.dart` | Guard never modulates. |
| Guard lane | protocol builder Guard | `GuardLane` | `guard_lane.dart` | Warns only. |
| Feature bus | — | `FeatureBus` | `feature_bus.dart` | |
| Feature probe latch | debug sliders | `FeatureOverride` | `feature_override.dart` | Replaces `FeatureDto.value` in `_onEvent` while playing. |

## Agent HTTP (debug)

Not a screen. `kDebugMode && --dart-define=MUSE_AGENT=1`. See
[testing-guide.md](testing-guide.md) (Linux agent) and
`.grok/skills/muse-run-linux/SKILL.md`.
