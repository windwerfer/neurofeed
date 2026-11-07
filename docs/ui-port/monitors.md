# UI port: monitor screens (Flutter → egui)

Status: **milestone 1 landed (2026-11-06)**: the shared monitor foundation, Bands, the hamburger navigation and immersive phone landscape. See *Progress* below. Scope: the live *monitor* screens.
Feedback, history and settings are out of scope for this pass.

Visual target: Flutter 0.60.0 (tag `pre-rust-port`, `lib/src/monitor/`).
We copy the look and the interaction model, not the code. Compact (phone) and
regular (tablet/desktop) are separate view sets over shared logic and shared
widgets (`ui/layout.rs` already picks the mode).

Screenshots (box, not committed): `/workspace/ui-shots/monitors/`
`flutter-<view>-{regular,compact}.png`, `rust-<view>-{regular,compact}.png`,
`compare-*.png`. Flutter shots come from the 0.60.0 AppImage on Xvfb with
the `sim:muse-s` simulator (debug pref `enable_simulated_devices`), light theme.
Rust shots come from `neurofeed-egui` (debug build) through `--bridge screenshot`,
`sim:muse_s`, default dark theme. Regular = 1280×800, compact = 400×850.

## Which screens are monitors

Flutter `AppView` with `appViewIsGraph == true`:

| Flutter view | Flutter file | Rust view | Rust file |
|---|---|---|---|
| Bands | `monitor/views/bands_view.dart` | Bands | `ui/views/bands.rs` |
| Raw EEG | `monitor/views/raw_eeg_view.dart` + `panes/sweep_pane.dart` | Raw EEG | `ui/views/raw.rs` |
| Histogram | `monitor/views/histogram_view.dart` + `panes/histogram_pane.dart` + `bands_context_strip.dart` | Histogram | `ui/views/histogram.rs` |
| Spectrogram | `monitor/views/spectrogram_view.dart` + `panes/spectrogram_pane.dart` | Spectrogram | `ui/views/spectrogram.rs` |
| PSD | `monitor/views/psd_view.dart` + `panes/psd_pane.dart` + `bands_context_strip.dart` | PSD | `ui/views/psd.rs` |
| HR + SpO2 | `monitor/views/hr_spo2_view.dart` + `optical_overview_pane.dart` + `optical_ppg_pane.dart` | HR+SpO2 | `ui/views/heart.rs` |
| (Movement: only a pane in the recording dashboard) | `panes/movement_pane.dart` | Movement (own view) | `ui/views/movement.rs` |

Rust-only extra: Movement is a top-level view. Keep it, but give it the same chrome as the others.

## Shared Flutter model (applies to every monitor)

- **GraphShell** (`graph_shell.dart`): one 48 px toolbar row on
  `surfaceContainer`, bottom divider. Contents, in order: `Follow | Inspect`
  segmented button, window-length dropdown (`30s ▾`, plus a `custom` entry
  after zooming), inspect range label (Inspect only), per-view extra
  (Y-scale, Hz range, `mag ▾`), **Record**, electrode chips (`TP9 AF7 AF8 TP10`).
  The row pans sideways when it overflows (phones), with a chevron to jump
  to the end. No view title or caption text: the sidebar or drawer names the view.
- **ViewportController** (`viewport_controller.dart`): `follow` / `inspect`,
  window presets per view, zoom floor/cap, Follow lead of about 1 s for 1 Hz strips, and the
  window is saved per view (`setMonitorWindowSeconds`).
  Presets: EEG 2/4/8/10 s; Bands 15/30/60/120 s (zoom 5 s to 30 min);
  Histogram/PSD 2/4/8 s; Spectrogram 10/20/30/120/300 s (zoom 5 to 300 s);
  optical overview 15/30/60/120 s; optical detail 2/4/8/10 s (zoom 2 to 120 s).
- **Gestures**: one-finger or mouse drag pans and enters Inspect. Two-finger pinch
  zooms X around the focal point (Bands, Spectrogram, Bands strip, HR overview and detail).
  The mouse wheel pans in Inspect (Raw EEG). Ctrl/⌘+wheel zooms (HR/SpO2; it should
  become universal, see the plan below). Disconnecting snaps back to Follow.
- **Time axis**: elapsed `m:ss` since capture start, vertical grid lines on each tick,
  labels under the plot. Rust shows only `-60 s … now`.
- **Electrode chips** (`electrode_toggles.dart`): average of the selected electrodes,
  at least one stays on. The same component is used on Bands, Histogram, PSD and Spectrogram.
- **Band toggles** (`band_toggles.dart`): a small floating legend card at the top right of the plot,
  inside it (delta…gamma, colored text, tap to hide).
- **Bands context strip** (`bands_context_strip.dart`): Histogram and PSD views are split 7:3. Main
  pane on top, a Bands mini time series below it with its own window menu (`90s ▾`). The
  shaded region marks the epoch the top pane is computed from, and it can be panned and pinched.
- **Empty and waiting states** (`empty_state.dart`): `MonitorWaitingSignal` overlay.
- **Cinema** (`graph_cinema.dart`): phone landscape or F11 hides all chrome.
- **Record** button in the toolbar on all live graphs (monitor recorder, save/discard sheet).
- Layout: the sidebar auto-closes below 700 px width. Phones use a hamburger drawer and there is
  **no bottom nav bar**. The status bar shows device, battery, pad horseshoe and a disconnect icon.

## Per screen

### 1. Bands
Flutter: one full-bleed time-series pane. Y in dB (about −40 to +20), grid on
every tick, `m:ss` X ticks. Smooth (spline) lines in band colors. Floating band
toggle legend at the top right. Electrode chips in the toolbar. Window dropdown 30 s. Pinch
zoom and drag pan (enters Inspect). Lines start where the capture starts.

Rust: heading + "(simulated data)", Absolute(log)/Relative% toggle, Over time /
Bars toggle, "Average of" chips, a wrapped legend row with Hz ranges, then the
window chip row and Follow/Inspect, then the plot. Y is log10 µV² (−1…3). Labels are `-60 s` and `now`.

Gaps:
- [missing] pinch zoom and Ctrl+wheel zoom (X); `custom` window after zoom; zoom floor and cap of 5 s to 30 min.
- [missing] `m:ss` time ticks with vertical grid lines; Y unit dB (Flutter) vs log10. Decide one (proposal: dB = 10·log10, same data).
- [missing] window saved per view across restarts.
- [visual] four chrome rows → one 48 px toolbar. The legend moves into a floating toggle card in the plot.
- [visual] the band palette is different. Flutter: δ #4FC3F7, θ #FF7043, α #66BB6A, β #AB47BC, γ #FFA726. Rust: δ red, θ orange, α green, β blue, γ purple.
- [visual] smooth (Catmull-Rom) lines (`smooth_path.dart`) vs polylines.
- [visual] the plot card has a 6 px radius on `extreme_bg`; Flutter is full-bleed with no card.
- [keep] Rust extras (Relative %, Bars mode) move into an overflow `⋯` menu in the toolbar so the Flutter look stays intact.

### 2. Raw EEG
Flutter: one **sweep** pane per electrode (oscilloscope-style wipe cursor, the trace overwrites
from the left; HOLD on Inspect), stacked full width, at least 160 px each, scrolls when the panes don't fit.
X axis only on the last pane. Electrode name on the right, Y labels on the right.
Y scale menu: Auto / ±50 / ±100 / ±200 µV. Wheel pans in Inspect, drag pans.
Inspect beyond RAM reads from the file-backed recording.

Rust: a card grid (2 columns at ≥900 px), a fixed ±60 µV range, scrolling (not sweep) traces, a quality
number per card, bad and gap shading, plus AUX channels.

Gaps:
- [missing] Y-scale menu (Auto/±50/±100/±200).
- [missing] sweep/wipe rendering mode (or decide that scrolling is fine; Flutter's identity is the sweep).
- [missing] wheel pan in Inspect; pinch has no zoom here (same as Flutter).
- [missing] inspect older than the 10 s RAM buffer (file-backed). Defer, because it depends on recording.
- [visual] a single stacked column, no cards, a shared X axis at the bottom, labels on the right, light trace color.
- [keep] quality and flag shading (a Rust improvement). Show them as subtle overlays.

### 3. Histogram
Flutter: 7:3 split. Top: amplitude histogram over the epoch (2/4/8 s), µV range
menu (±50/100/200), Y `count`, tap sets a hairline µV readout. Electrode chips
average. Bottom: Bands context strip with the epoch shaded.
Rust: per-channel card grid (4 cards), fixed ±100 µV, 64 bins over the last 2 s, σ label.

Gaps:
- [missing] Bands context strip (shared widget, also used by PSD).
- [missing] epoch window 2/4/8 s + Follow/Inspect (epoch follows the strip selection).
- [missing] µV range menu; tap hairline readout.
- [visual] a single averaged pane instead of a grid (keep per-channel as an option?). Proposal: the Flutter
  default is averaged selected electrodes. A grid toggle goes in `⋯`.
- (The Flutter simulator showed a single spike bar, which looks like a sim artifact, not the design.)

### 4. Spectrogram
Flutter: one full pane of the averaged selected electrodes, plasma colormap
(#0D0887→#F0F921) with a vertical color bar on the right, Hz axis on the left (0–60),
`m:ss` X. `mag ▾` menu: min…max dB range slider + lock (else auto range).
Window 10/20/30/120/300 s, pinch zoom 5 to 300 s, drag pan.
Rust: single-channel selector chips (not averaged), 10/20/30 s only (30 s buffer),
custom blue→red colormap, no color bar, 0–50 Hz, fixed −20…25 dB.

Gaps:
- [missing] longer history (120/300 s), so the buffer must grow; pinch and Ctrl+wheel zoom.
- [missing] `mag` range menu + auto range + lock; color bar legend.
- [broken/semantic] the electrode chips select one channel instead of averaging the selection (Flutter averages).
- [visual] plasma colormap, Hz ticks up to 60, `m:ss` X ticks.

### 5. PSD
Flutter: 7:3 split. Top: one averaged PSD line (dB) over 0–60 or 0–100 Hz (menu),
**band-colored background regions** (δ…γ shading), peak label (e.g. `10.3 Hz`),
tap sets a hairline readout. Epoch 2/4/8 s. Bottom: Bands context strip.
Rust: four per-channel cards, log10 power −2…3, 0–50 Hz, an alpha peak marker per card.

Gaps:
- [missing] band shading behind the curve; Hz range menu (60/100); tap hairline.
- [missing] Bands context strip + epoch window + Follow/Inspect.
- [visual] single averaged pane (grid in `⋯`), dB Y axis, black trace on light / light on dark.

### 6. HR + SpO2
Flutter: two stacked panes. **Overview** (HR bpm 40–200 on the left axis, SpO2 % 50–100
on the right axis, dashed "avg HR" line, `m:ss` X) with the shell window 15–120 s.
**Detail** "IR PPG" waveform with its own window menu (`10s ▾`, 2/4/8/10, zoom
2 to 120 s) and a moving cursor. Both pinch and Ctrl/⌘+wheel zoom, and both pan.
Rust: big HR/SpO2 numbers with confidence, a 6 s pulse wave card, a fixed "trend last 2 min" card. No
Follow/Inspect, no window, no gestures.

Gaps:
- [missing] GraphShell chrome (Follow/Inspect, window, Record).
- [missing] dual-axis overview with avg-HR dashed line; zoom and pan on both panes; detail window menu.
- [keep] big current HR/SpO2 readout (Rust addition). Move it into a compact header chip set.
- [visual] titles inside panes (`IR PPG`), axis units top-left/top-right.

### 7. Movement (Rust only)
Has Follow/Inspect + window. Just apply the shared shell, the time-series widget and the theme. Low priority.

## Proposed shared widgets (egui, `ui/monitor/`)

1. **`GraphShell`**: the single toolbar row (Follow/Inspect segmented, window combo
   with `custom`, inspect label, extras slot, Record, electrode chips, `⋯` overflow).
   Compact: a horizontally scrollable row (egui `ScrollArea::horizontal`) with 48 px targets.
2. **`Viewport`** (extend `views/plot.rs::Viewport`): presets, floor and cap, `zoom_at(focal_frac, factor)`,
   `pan`, Follow lead, persisted per view via settings (`monitor_window.<view>`), and nf-core
   commands so MCP can set and read it (`monitor.viewport.set`).
3. **`TimePlot`**: the one zoomable time-series plot reused by Bands, Bands strip, HR
   overview and detail, Movement, and as the base of Raw EEG. Input: drag = pan,
   `zoom_delta()` (pinch) and Ctrl+wheel = X zoom at the pointer, wheel = pan,
   double-click = Follow. Draws the `m:ss` grid, Y gutters (left and/or right axis),
   gap breaks, clipping markers, optional smoothing, and an optional shaded epoch region.
   (egui gives pinch as `InputState::zoom_delta` and Ctrl+wheel the same way, so one code path covers both.)
4. **`SweepPane`**: per-channel sweep trace on top of the `TimePlot` axes (wipe cursor).
5. **`ElectrodeChips`** and **`BandToggles`** (floating legend card).
6. **`BandsContextStrip`** + `MonitorSplit` (7:3) for Histogram and PSD.
7. **`SpectrumPlot`** (PSD/histogram X-domain plot with band shading, hairline tap readout).
8. **`Heatmap`** (spectrogram) with plasma LUT + color bar.
9. **`WaitingSignal`** overlay + empty state.

Data notes: the averaged-electrode values, epoch PSD/histogram and longer
spectrogram history should be in nf-core/nf-dsp (shared with MCP), not in views.

## Compact vs regular

| | Regular (≥600 px) | Compact (<600 px) |
|---|---|---|
| Nav | sidebar (Flutter: closed by default, hamburger) | Flutter: drawer via ☰, **no bottom bar**. Rust: bottom bar + More. Decision needed; proposal: keep the Rust bottom bar for now (outside the monitor scope) |
| Toolbar | single 48 px row | same row, scrolls horizontally, chevron |
| Raw EEG | panes fill height | min 160 px per pane, vertical scroll |
| Histogram/PSD | 7:3 split | 7:3 split (same) |
| HR | overview + detail stacked | same, detail min height |
| Landscape phone / F11 | normal | cinema (chrome hidden) |
| Text | Rust headings + captions | drop headings and captions; the view name is in the nav |

Both view sets call the same widget constructors, and only the arrangement differs
(`views/<name>/regular.rs`, `views/<name>/compact.rs`, shared `views/<name>/mod.rs`).

## Shared theme (match Flutter M3, seed `Colors.deepPurple`)

- Light (Flutter default): background/surface ≈ #FEF7FF, toolbar `surfaceContainer`
  ≈ #F3EDF7, status bar ≈ #E8DEF8-ish tint, divider ≈ #CAC4D0, primary #6750A4-ish
  (derive from the M3 tonal palette of #673AB7; generate once and hard-code).
- Dark: the M3 dark scheme from the same seed (surface ≈ #141218, container ≈ #211F26).
  Rust currently uses the stock egui dark with a teal-blue accent. Replace it with the M3 palette and keep a
  light/dark/system switch (it already exists in settings).
- Plot: no card. Grid is `outlineVariant` at about 0.5 alpha. Axis text is 10–11 px `onSurfaceVariant`.
- Band palette: δ #4FC3F7, θ #FF7043, α #66BB6A, β #AB47BC, γ #FFA726.
- Spectrogram: plasma 5-stop LUT (from `spectrogram_pane.dart`).
- Spacing: toolbar 48 px, horizontal padding 12 px, 12 px gaps between groups, chips
  compact density. Touch targets of at least 48 px in compact.
- Fonts: Flutter on Linux used Roboto-like system sans (M3 type scale:
  labelLarge 14/500 for buttons, labelMedium 12 for chips, bodySmall 11 for axes).
  Embed Roboto (Apache-2.0, about 170 KB per weight) or Inter. egui's default proportional font is
  noticeably different, and this is the biggest "doesn't look like the old app" factor after color.

## Ordered work plan (rough effort, 1 d = one focused agent/dev day)

1. **Theme module**: M3 palette light and dark, band palette, plasma LUT, Roboto, type scale and spacing tokens. *1 d*
2. **Viewport v2 + nf-core commands** (presets, zoom floor and cap, persisted per-view window, MCP). *1 d*
3. **`TimePlot`** (pan, pinch / Ctrl+wheel zoom, wheel pan, `m:ss` grid, dual Y axis, smoothing, epoch shading) + tests. *2–3 d*
4. **`GraphShell`** toolbar + `ElectrodeChips` + `BandToggles` + `⋯` overflow + compact scrolling row + WaitingSignal. *1.5 d*
5. **Bands** on the new widgets (regular + compact); dB axis; Rust extras into `⋯`. *1 d*
6. **HR + SpO2** (overview dual axis + detail pane, both on TimePlot). *1.5 d*
7. **BandsContextStrip + MonitorSplit + SpectrumPlot** (band shading, hairline), then **PSD**, then **Histogram** (averaged, epoch window, range menus; data in nf-dsp). *3 d*
8. **Spectrogram**: averaged electrodes, 300 s history in nf-core, heatmap + color bar, mag range menu, zoom. *2 d*
9. **Raw EEG**: stacked layout, Y-scale menu, sweep mode, wheel pan (file-backed inspect deferred). *2 d*
10. **Movement** onto the shell. **Cinema** mode (F11 / phone landscape). *1 d*
11. Screenshot regression pass with `--bridge screenshot` for both layouts, plus docs. *0.5 d*

Total ≈ 16–18 d. Steps 1–4 unblock everything; after step 5 the Bands screen
can be reviewed against `compare-bands-regular.png`.

## Open decisions for the owner
- Y units on Bands: dB (Flutter) or log10 µV² (Rust)?
- Compact nav: the Flutter drawer or the current Rust bottom bar?
- Raw EEG: sweep (Flutter) or scrolling (Rust) as the default?
- Histogram/PSD: averaged single pane (Flutter) as the default, with the per-channel grid as an option?

## Owner decisions (2026-11-06)

1. Bands: a persisted toggle between **log absolute (dB)** and **relative %**.
2. Compact navigation: **hamburger drawer** (the bottom bar was removed).
3. Raw EEG: **sweep** by default, stacked plots generated from the device's EEG channel list (never a fixed count).
4. Histogram/PSD: **one averaged panel**, with the same electrode chips in the toolbar as Bands.
5. **Phone landscape hides all chrome** on monitor screens (graph only). Portrait brings the controls back.
   A phone is never classed regular just because it is wide.

### Bands value math (documented contract)

- Inputs: per electrode and band, `log10(µV²/Hz)` from the band snapshots (unchanged DSP).
- **Electrode aggregation**: convert each selected electrode's value to **linear** power (`10^x`),
  skip non-finite values, and take the arithmetic mean. No mean of logs.
- **Absolute (dB)**: `10·log10(mean_linear)`. The Y axis fits the data in 10 dB steps.
- **Relative (%)**: `mean_linear(band) / Σ mean_linear(visible bands) × 100`. A hidden band is left
  out of the denominator and is not drawn, so the visible lines always sum to 100 %. A zero, negative or
  non-finite total yields no value (gap) for every band.
- Electrodes come from the device's channel list. Selecting none is impossible (the last one stays on),
  and an empty selection means "all".
- Implemented in `nf_core::monitor::band_values` with unit tests. Per-electrode bars (`…`) use the same
  function with one electrode.

## Progress

### Milestone 1: done (2026-11-06)

- **Core viewport** `nf_core::monitor`: per-monitor window presets and zoom limits, Follow/Inspect, zoom
  anchored at a focal point (right-edge zoom keeps Follow), pan (enters Inspect), clamping to the data,
  NaN-safe. Commands: `monitor.viewport`, `monitor.zoom`, `monitor.pan`, `monitor.display` and `monitor.get`
  (CLI/MCP/bridge, documented in `docs/automation.md`). Window lengths and hidden bands are persisted, and
  disconnect returns every monitor to Follow. Bands history covers 30 min (the legacy zoom cap).
- **Shared UI** `apps/neurofeed-egui/src/ui/monitor.rs`: a single horizontally scrollable toolbar row
  (Follow | Inspect, window menu with `custom`, extras slot); plot input (touch pinch and Ctrl/Cmd+wheel zoom
  anchored at the pointer or pinch centre, drag pan, wheel pan, double-click Follow); and an elapsed `m:ss` time
  grid. Used by Bands. The later screens reuse it.
- **Bands**: full-bleed graph, floating band legend (tap hides a band), legacy band palette, dB | % toggle,
  electrode chips, inspect range label, `…` → per-electrode bars.
- **Layouts**: Compact uses a `☰` drawer (no bottom bar). Immersive phone landscape hides the top bar,
  navigation and toolbars on monitor screens (`.ai/contracts/ui-layout.md`). The old Raw EEG, PSD, Histogram and
  Movement headers and window rows are hidden in immersive too.
- Tests: viewport zoom anchoring, clamps and Follow/Inspect; relative and absolute math (linear averaging,
  hidden bands, invalid totals); persistence round trip through the settings doc; command validation;
  layout selection by orientation and phone identity.
- Screenshots: `/workspace/ui-shots/monitors/m1-rust-bands-{regular,regular-relative,compact,landscape}.png`.

### Known limits after milestone 1

- Raw EEG, Spectrogram and Movement still use the old view-local viewport (`views/plot.rs::Viewport`).
  HR+SpO2 has none. Their toolbars are not yet the shared row.
- Spectrogram and HR+SpO2 still draw their headers in immersive landscape (their own header code).
- No Follow lead (~1 s) and no smoothed (spline) lines yet. The theme is still stock egui dark, and the
  Material 3 palette and Roboto are still to come.
- The drawer and pinch were checked by unit tests and the desktop window, not on a real phone.

### Next milestones (ordered)

1. ~~**Raw EEG**~~ — done 2026-11-07 (see "Raw EEG milestone" below).
2. **Histogram + PSD** (≈3 d): one averaged panel with electrode chips (`monitor.display`); 2/4/8 s epoch;
   Bands context strip (7:3) on the shared plot; PSD band shading, Hz range and tap readout; µV range for
   the histogram.
3. **Spectrogram** (≈2 d): averaged electrodes, longer history (300 s), plasma map + colour bar, dB range menu,
   zoom via the core viewport.
4. **HR+SpO2** (≈1.5 d): overview (two Y axes) + detail panes on the shared plot, both zoomable.
5. **Movement** onto the shared toolbar (≈0.5 d).
6. **Theme** (≈1 d): Material 3 palette light/dark, Roboto, spacing tokens; Follow lead and smoothing.


### Raw EEG milestone (done 2026-11-07)
- `ui/views/raw.rs` on the shared toolbar and core viewport `raw_eeg` (presets 2/4/8/10 s, saved; 1–10 s zoom).
  One full-width pane per shown channel from `DeviceInfo.channels` (Muse 4, Crown 8, any count), AUX panes after.
  Minimum pane height 160 (regular), 140 (compact), 96 (phone landscape); below that the stack scrolls
  vertically. Plain vertical wheel / vertical drag scroll the stack when it overflows; otherwise the wheel pans
  in Inspect. Sideways drag/wheel pans, pinch and Ctrl/⌘+wheel zoom, double-click returns to Follow.
- `monitor.raw {mode, scale, electrodes}`: `sweep` (default) | `scroll`; `auto` | `50` | `100` | `200` µV (both
  saved); electrodes by name, session-only like Bands. `monitor.get` reports `raw`.
- Geometry in `nf_core::rawtrace` (pure, tested): true sample timestamps from the gap-padded ring; sweep x =
  phase in a window-long slot, lines split at the wrap, gaps and non-finite values; 2 % blank after the cursor;
  min+max per pixel column at their true x (spikes kept, ≤ 2 points per column). Bad samples are drawn with red
  shading, gaps grey; values beyond the scale are clamped with a red dot.
- Auto Y is **shared** by all panes: max |µV| of the visible OK samples + 15 %, 10..10 000 µV, re-fit every
  250 ms (Flutter fits min..max; symmetric here so nothing is clipped around the 0 line).
- Follow uses `FollowClock` with a 0.25 s lead (`RAW_FOLLOW_LEAD_S`) so the cursor glides; vsync repaints only
  while live + Follow. Inspect (drag, wheel, Inspect button) holds a time-ordered window in both modes.
- 2026-11-07 fix: Inspect drag barely moved because the RAM ring was 10 s (8 s window → 2 s to pan); the ring is
  now 60 s (`signal::BUFFER_S`).
- 2026-11-07: ring raised to 5 min (300 s, owner).
- Deferred: inspect older than the 5 min RAM ring (file-backed); per-channel Auto; quality numbers (a dot only).

### Future work: Inspect beyond the 5 min ring (not built; needs owner approval)
What exists: only an explicit recording (Record button / `recording.start`, or a training, which always
records) writes samples. The body is NFEDBIN: a header, then `[u32 len][zstd frame]` frames flushed every 1 s
(`recording.rs` `FLUSH_S`), held in memory while recording; every 10 s the new bytes are appended to the store
(`blob_chunks`, crash recovery) and the whole body is saved on stop. There is no time index and no range-read
API (`parse_body` decodes everything). Without a recording, samples older than the ring are gone.

Proposal (≈3–4 d): (1) at each frame flush record `(first_t, last_t, byte_offset)` in a frame index kept with
the recording (old files: build it once by walking the length prefixes, decompressing only to read times);
(2) a `history` reader in nf-core that decodes the frames overlapping `[t0, t1]` for the current device's
recording (live: from the in-memory body; saved: from the store blob, native thread / web async), returning
true timestamps and gap flags; (3) the Raw view asks for the visible window when it lies before the ring, shows
"loading" meanwhile, keeps a small LRU (≈8 windows), drops stale requests by generation id, optionally prefetches
one window each side; (4) min/max decimation as now. Never starts a recording by itself; outside recorded
spans the panes say "not recorded".

### Raw EEG: Sweep → Inspect without a jump (2026-11-07)
Leaving a Sweep (Inspect button, drag, sideways wheel, pinch/Ctrl+wheel
zoom) freezes on the current sweep slot `[k·w, (k+1)·w]`
(`rawtrace::Mapping::freeze_end`). Every sample keeps its x; the previous
sweep's data right of the cursor is cleared. That right region is real
future time: empty until live samples arrive and fill it (no fabricated
data, the frozen window never moves). In Sweep mode the Raw span allows one
window of such blank room past the newest sample (`Span::ahead_s`), so
panning right can reach at most one window of empty time; Scroll mode has
none and freezes at the presented edge as before. Limits: the one sample
exactly on the slot start leaves the window (x = 0); with the cursor in the
last ~2 % of the slot, real slot-start samples hidden under the sweep's
blank gap reappear at the left edge; samples newer than the presented
cursor (≤ 0.25 s follow lead) appear right of it right away.

### PSD (done 2026-11-07)
One averaged spectrum (dB re µV²/Hz of the linear Welch mean) of the selected,
analysis-eligible electrodes over the epoch (2/4/8 s, Follow/Inspect; Inspect
computes the requested window), band shading (app band edges 1–4–8–13–30–44 Hz),
alpha peak marker, tap/hover hairline readout, 0–60/0–100 Hz. Below (7:3) the
Bands strip (`psd_strip` viewport) with the epoch shaded: drag the shade to move
the epoch, drag elsewhere pans, pinch/Ctrl+wheel zooms, tap places the epoch.
Strip time older than the 5 min raw ring is dimmed. Spectrum cached per 1/8 s of
epoch movement; strip reads only its visible snapshots. `ui/spectrum.rs` is the
base for the Histogram later. Landscape: graphs only.
