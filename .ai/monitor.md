# Live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| **Status** | Implemented |
| **Date** | 2026-09-13 |
| **Chrome names** | [ui-map.md](ui-map.md) |
| **Series history** | [archive/handoff-monitor.md](archive/handoff-monitor.md), [archive/monitor-rev6-design.md](archive/monitor-rev6-design.md), [archive/handoff-monitor-perf.md](archive/handoff-monitor-perf.md) (draw-path PRs 1–7; PR 8 skipped) |

Do not reopen: pipeline-contract Key Decisions, Crown Start, Connect UX, v5
68-byte header. Do not add Spectrogram `FFT 1s ▾`, averaging, or a Bands
strip on Spectrogram.

---

## What it is

`lib/src/monitor/` is the live-signal surface, split from Feedback.

On connect, a rolling `tmp_$ts` scratch capture starts (30 min, never
published). **Record** starts a keepable `recording_$ts`. Feedback sessions
keep `session_$id`. At most one scratch writer is open (exclusive lease).

Published files share the history folder and sqlite:

- `session_$id.muse.feedback` — `kind = feedback`
- `recording_$ts.muse.feedback` — `kind = recording`

Sidebar **History** (`AppView.feedbackHistory`) filters All | Feedback |
Recordings. There is no `AppView.recordings`.

---

## Tree

```
lib/src/monitor/
  monitor_controller.dart     constructed in main(); hydrates if already connected
  monitor_state.dart          CaptureKind, montage, elapsed
  monitor_providers.dart
  graph_shell.dart            Follow / Inspect, window, Record / Stop
  graph_cinema.dart           mobile landscape, or desktop F11
  viewport_controller.dart    elapsed seconds from capture start; Bands Follow lead 1 s
  electrode_toggles.dart      non-EEG average membership
  band_toggles.dart           in-pane delta/theta/alpha/beta/gamma chips
  empty_state.dart            Waiting for signal
  dsp.dart                    Hamming FFT, 1/N², n power-of-two (live uses 256)
  device_montage.dart         N = channelCount (Muse 4 / Crown 8)
  cache/
    sweep_buffer.dart         5 min EEG RAM + display ring
    band_cache.dart           1 Hz bands, 30 min cap
    recording_index.dart      (elapsedT, fileLength) at frame boundaries
    file_backed_source.dart   Inspect beyond RAM (tmp / recording .raw)
    sweep_mean.dart
    stft_ring.dart            Follow STFT column ring (Inspect / electrodes / window = full)
    sliding_spectrum.dart     Follow Welch / histogram (Inspect / electrodes / window = full)
  panes/                      SweepPane, TimeSeriesPane, histogram / PSD /
                              spectrogram, BandsContextStrip, overshoot_hold
  views/                      five live graphs + recording dashboard + Save/Discard
  recording/
    capture_lease.dart        idle | tmp | recording | feedback
    monitor_recorder.dart     tmp_ / recording_ temps
    monitor_sampler.dart      1 Hz ComputedFrame, N-ch
    recording_metadata.dart   nested JSON snapshot (not SessionMetadata)
    crash_recovery.dart       recording_* only; glob-delete tmp_*
    recording_store.dart      publish → history + sqlite kind=recording
```

`bandNames` / `bandColors` stay in `lib/src/charts/band_style.dart`.
Pad-quality dots are a 4-ch 1 s ring in `connection_provider.dart`.

---

## Isolation

**May import:** `rust/api/{muse,session_format,device_config}.dart`,
`connection_provider.dart`, `settings.dart`, `session_v5/`,
`charts/{smooth_path,band_style}.dart`, `version.dart`,
`feedback/session_storage.dart`, `feedback/session_sqlite.dart`.

**Must not import:** `feedback_state.dart`, lanes, protocol, `session_store*.dart`,
feedback `crash_recovery.dart`.

**Feedback → monitor** only via the lease (`acquireFeedbackLease` /
`releaseFeedbackLease`) and `_refuseRecordingStart`. History list may open
`recording_dashboard.dart`.

Release the lease only when `!FeedbackRecorder.isRecording` (failed assemble
keeps temps).

---

## Capture lease

```
idle → tmp          connect (or feedback writer closed, still connected)
tmp  → recording    user Record (discards tmp; no pre-click bytes in the file)
tmp  → feedback     Start Session (discards tmp, no prompt)
recording → idle    Stop / in-app disconnect → assemble + Save/Discard
feedback  → tmp     writer actually closed, still connected
```

Record during feedback: button disabled. Start during Record: dialog + agent
409 `recording_active`. Disconnect while recording: assemble + Save/Discard.
Disconnect while tmp: discard, no prompt.

`tmp_` silent-rotates at 30 min (new capture clock). Explicit `recording_` is
uncapped (soft 2 h warning, no auto-stop). Settings → **Session recording**
stream picker applies to tmp, Record, and feedback.

Scratch is always `scratchDirectory()`. SAF is history-only.

---

## Graphs

Shared chrome: Follow | Inspect, window length, Record / Stop, electrode
toggles (non-EEG). Chrome hide (`graph_cinema.dart`): **mobile landscape**
hides status bar, sidebar, and GraphShell toolbar (portrait restores).
**Desktop keeps chrome** in a landscape window; **F11** hides the same
chrome (F11 again restores). Plot gestures stay. Not Settings / Feedback /
Streaming / History.

Viewport domain is **elapsed seconds from capture start**. Follow default.
Drag/pinch on a time-X graph enters Inspect.

| View | Panes | Window | Notes |
|------|-------|--------|-------|
| Raw EEG | N stacked sweep | 2/4/8/**10 s** | Oscilloscope wipe. No chips. Shared Y. |
| Bands | 1 strip, 5 series | 15/**30**/60/120 s + pinch `custom` | Y = dB display; storage linear µV²/Hz. Mean of selected in dB. Overshoot = dashed hold. PCHIP strokes. Follow slides with ~1 s lead (1 Hz cache). In-pane band chips toggle series (depressed = visible). |
| Histogram | ~70% + ~30% Bands strip | 2/4/**8 s** | X ±100 µV (overflow ±50/±200), 64 bins. Tap hairline. Strip default 30 s. |
| PSD | same split | 2/**4**/8 s | X 0–60 Hz (overflow 0–100). Welch 1 s / 256-pt, 50% hop. Band shading + alpha peak. |
| Spectrogram | 1 heatmap | 10/**20**/30 s / 2 min / 5 min + pinch `custom` | Y 0–60 Hz. `mag ▾` color min/max. STFT 256-pt, hop ~0.25 s. No strip, no FFT-size chrome. |

Histogram/PSD highlight on the strip is **time only** (width = T). One
electrode-toggle set drives both panes. Recording-dashboard Histogram/PSD
are one pane (no strip). Follow is disabled there.

DSP: `monitor/dsp.dart` only. Hamming, power `(re²+im²)/(n*n)`. Live `n = 256`.
Follow Spectrogram STFT is incremental (one new hop FFT); Inspect / electrode
set / window-length still full recompute. Follow Histogram adds/subtracts
bins; Follow PSD is sliding Welch (hop `n/2` = 128). Inspect pan, window,
electrodes, µV/Hz range, and disconnect full-recompute. Recording dashboard
stays one-shot `welch` / `histogramCounts`. The heatmap is a bitmap painted
with `FilterQuality.none`, rasterized inside `SpectrogramPane` (live +
recording dashboard).

EEG RAM is SweepBuffer only (5 min). SweepBuffer and BandCache coalesce
`notifyListeners` to vsync; RAM writes stay 256 Hz. AppShell `select`s
`currentView` / sidebar / connect-window (pad quality does not rebuild the
shell). Live graphs `select` connected. Plot panes sit in `RepaintBoundary`.
Data ticks rebuild the plot through `ListenableBuilder` (Histogram/PSD: sweep
→ primary, bands → strip) and do not rebuild GraphShell. Hidden graphs stay
unmounted (`AppShell` `switch`, not `IndexedStack`). Histogram/PSD Inspect does not
re-Welch / re-bin; Follow is still last T seconds (sliding Welch / histogram).
Inspect past 5 min reads the open
tmp/recording `.raw` via `FileBackedSource`. After tmp rotate, Inspect is
the **new** tmp plus whatever is still in RAM.

Raw EEG traces downsample min/max per pixel column when samples exceed chart
width (peaks kept; wipe bar still `cursor % n`). Axis Y/X labels reuse
`TextPainter`s for the same string. Auto-Y runs at most 4 Hz. Only Raw EEG
uses the Follow wipe ring; leaving that view calls `setDisplayWindow(0)` so
`append` is RAM-only.

---

## Montage

`lastConnectedKind` → `DeviceConfig.forKind` → `channelCount` / names.
Muse: TP9 AF7 AF8 TP10. Crown/Notion: 8 names. Simulator Crown is 8-ch
for graphs; Start Session stays refused. Status-bar pads stay 4-ch.

Non-EEG electrode toggles: top-right text, depressed = in the mean, default
all on, last one stays. Raw EEG has no chips.

Bands series chips: in-pane `BandToggles` (right gutter), label color = line,
depressed = visible, last one stays. Histogram/PSD strip legend is painted
and not tappable. Recording-dashboard Bands uses the same chips.

---

## Recording files

Temps: `recording_$ts.{raw,computed,json}` (`.json` is an atomic snapshot,
not JSONL). Assemble `writeScratchV5(prefix: recording)` with placeholder
WebP **before** Save/Discard.

Dialog (`Save recording?` / `Incomplete recording detected`): Save publishes
history-root file + sqlite `kind=recording`; Discard deletes scratch.

Crash: feedback scanner is `session_*` only; monitor scanner is `recording_*`
only; launch glob-deletes `tmp_*`.

`RecordingMetadata` is nested (`kind`, `device`, complete ten-key `streams`).
Not `SessionMetadata.toJson()`. Format: [README_feedback_format.md](../README_feedback_format.md).

---

## Frozen product calls

- Unified History; Settings **Save files to folder**; sidebar **Spectrogram**.
- Raw EEG stays sweep. 5 min RAM + 30 min tmp. Do not grow RAM to 30 min.
- Bands Y is dB display. Pinch-X `custom` on Bands and Spectrogram only.
  Follow on 1 Hz Bands strips slides with ~1 s lead + always-on PCHIP.
  Spectrogram Follow is flush-right. No `SMOOTH` / `REAL TIME` chrome.
- Cinema: mobile landscape hides chrome; desktop **F11** does the same.
  Spectrogram `mag ▾` is color, not Hz.
- No averaging, no hold-finger readout, no FFT-window chrome (256-pt only).
- Histogram/PSD: no time slider; Bands strip is the time map. No strip on Spectrogram.
- Crown graphs + recording allowed; Crown Start refused.
- No Android foreground service in this surface (recording dies if the app is backgrounded).
