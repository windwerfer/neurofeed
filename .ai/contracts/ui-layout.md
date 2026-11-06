# UI layout contract (Compact / Regular / Immersive)

Status: **Implemented** (`apps/neurofeed-egui/src/ui/layout.rs`).

- Setting `settings.layout` = `auto` (default) | `compact` | `regular`,
  changed with `settings.set {"layout":"compact"}` (MCP, CLI, Settings →
  General → Layout). Desktop can force the phone layout (and screenshot it).
- `auto`: on a **phone** (Android or web whose short side is `< 600` logical
  px) portrait is Compact and landscape is Immersive; a phone in landscape is
  never Regular just because it is wide. Elsewhere (desktop, tablets): Compact
  when the root width is `< 600`, else Regular. A forced `compact` behaves like
  a phone (portrait Compact, landscape Immersive), so desktop can emulate it.
- **Immersive** (phone landscape, monitor screens only: Bands, Raw EEG,
  Histogram, Spectrogram, PSD, HR+SpO2, Movement): the graph only, with no top
  bar, navigation, monitor toolbar, headings or record controls. Graph gestures
  still work and the safe area still applies through the root ui. Other screens
  fall back to Compact. Rotating to portrait brings the controls back.
- The layout is picked once per frame in `ui::show_with`, stored in egui temp
  data; views read it with `ui::layout::current(ctx)`. Views are shared and
  only branch on the hint (e.g. stack two columns vertically) — never fork a
  view into a compact copy.
- Regular: top bar + left sidebar (`☰` toggles). Below 900 px the sidebar is
  an icon rail (label on hover).
- Compact: compact top bar (`☰` opens the navigation drawer, device area with signal-quality ASCII + battery +
  green dot only while an LSL/OSC server runs; tap opens the Device dialog;
  no title; icon record / pause; notch lives in Settings → Devices), a modal
  navigation drawer over a scrim listing every view (no bottom bar; owner
  decision 2026-11-06),
  ~48 dp touch targets, Device dialog and onboarding as full-screen sheets.
- Android safe area: system-bar + cutout insets (Kotlin listener + JNI poll of
  the decor view every 500 ms, so rotation updates) feed
  `RawInput::safe_area_insets`; the top inset is never below 28 pt on Android.
