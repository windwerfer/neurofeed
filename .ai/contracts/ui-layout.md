# UI layout contract (Compact / Regular)

Status: **Implemented** (`apps/neurofeed-egui/src/ui/layout.rs`).

- Setting `settings.layout` = `auto` (default) | `compact` | `regular`,
  changed with `settings.set {"layout":"compact"}` (MCP, CLI, Settings →
  General → Layout). Desktop can force the phone layout (and screenshot it).
- `auto`: Compact when the root width is `< 600` logical px, else Regular.
- The layout is picked once per frame in `ui::show_with`, stored in egui temp
  data; views read it with `ui::layout::current(ctx)`. Views are shared and
  only branch on the hint (e.g. stack two columns vertically) — never fork a
  view into a compact copy.
- Regular: top bar + left sidebar (`☰` toggles). Below 900 px the sidebar is
  an icon rail (label on hover).
- Compact: compact top bar (device area with signal-quality ASCII + battery +
  green dot only while an LSL/OSC server runs; tap opens the Device dialog;
  no title; icon record / pause; notch lives in Settings → Devices), bottom
  navigation (Feedback, Bands, History, Settings, `☰ More` for the rest),
  ~48 dp touch targets, Device dialog and onboarding as full-screen sheets.
- Android safe area: system-bar + cutout insets (Kotlin listener + JNI poll of
  the decor view every 500 ms, so rotation updates) feed
  `RawInput::safe_area_insets`; the top inset is never below 28 pt on Android.
