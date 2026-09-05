# UI map

Spoken name → on-screen text → code → file. Grep the first two columns when a
human describes a bug. Frozen connect/pipeline names are mirrored, not renamed.

How to use: pick a surface in the TOC, then match **Spoken name**.

## Chrome

### Status bar — `lib/src/status_bar.dart`

Hosted by `AppShell` and `FeedbackSessionView` (`showMenu: false` on session).

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
| Feedback History | `Feedback History` | `AppView.feedbackHistory` | `app.dart` | `FeedbackHistoryView`. |
| Bands | `Bands` | `AppView.bands` | `app.dart` | |
| Raw EEG | `Raw EEG` | `AppView.rawEeg` | `app.dart` | |
| Spectrogram | `Spectrogram` | `AppView.spectrogram` | `app.dart` | |
| PSD | `Power Spectral Density (PSD)` | `AppView.psd` | `app.dart` | Full label. |
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
| Start Session | `Start Session` | `_PhaseControls.startSession` | `feedback_session.dart` | Crown → dialog. |
| Start skip-cal | `Start (skip calibration)` | `startCalibration(skipCalibration: true)` | `feedback_session.dart` | recordOnly. |
| Crown refused dialog | `Crown sessions are not available yet…` | `crownSessionUnsupportedMessage` | `protocol.dart` | Real and sim Crown. |
| Pause / Resume / End | phase controls | `pause` / `resume` / `end` | `feedback_state.dart` | |

### Settings cards — `lib/src/views/settings_view.dart`

Order: Save folder, Session recording, Gesture markers, Music feedback,
Guardrail AI engine, Audio (Android only), About, Debug mode.

| Spoken name | On-screen text | Code symbol | File | Notes |
|---|---|---|---|---|
| Save folder | `Save feedback to folder` | `setSessionFolder` | `settings_view.dart` | |
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

## Agent HTTP (debug)

Not a screen. `kDebugMode && --dart-define=MUSE_AGENT=1`. See
[testing-guide.md](testing-guide.md) (Linux agent) and
`.grok/skills/muse-run-linux/SKILL.md`.
