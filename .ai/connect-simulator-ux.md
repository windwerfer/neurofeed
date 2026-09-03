# Connect simulator UX + settings cleanup

**Status:** Frozen spec. Implemented on `feat/connect-simulator-ux`.  
**Date:** 2026-09-03  
**Branch:** `feat/connect-simulator-ux`  
**Handoff (landed):** [archive/handoff-connect-simulator-ux.md](archive/handoff-connect-simulator-ux.md)

Do not mix with Crown OSC connect, unlocking Crown sessions, or pipeline-contract
Key Decisions. Session-charts work is done on `main`.

---

## Problem

The connect dropdown lists every `DeviceKind` (`Muse`, `Neurosity`,
`Muse (Simulated)`, `Neurosity (Simulated)`). A second “Enable Simulator”
switch exists only when `Settings.enableSimulatedDevices` is true, and that
pref has **no Settings UI**. `scan()` is BLE-only and tags names containing
“Crown”/“Notion” as Neurosity — wrong transport (those devices speak OSC).

Settings also has a leftover **AI sleep guardrail** card (guard is chosen in
the protocol builder) and a scroll hitch on the way down (music RangeSlider).

---

## Key decisions (do not reopen)

1. **Connect dropdown is Muse | Neurosity | Simulator.** Simulator is a
   Dart `ConnectSource`, not a `DeviceKind`. Simulator appears only when
   Settings **Debug mode** is on (`enable_simulated_devices`, default false).
2. **`DeviceKind` is two values: `Muse` and `Neurosity`.** Kind is the headset
   family (montage / features / Crown-start-refused). Simulation is the
   existing `simulate` flag on `connect_with_options`, plus synthetic `sim:*`
   device ids. Drop `SimulatedMuse` / `SimulatedNeurosity`, `is_simulated`,
   `base_kind`. This **does** change the FFI enum → FRB codegen, commit both
   generated sides.
3. **Muse discovery is BLE only.** Filter out anything that is not Muse.
4. **Neurosity discovery is OSC only, never BLE.** Do not call BLE `scan()`
   while the source is Neurosity. There is no OSC scan API today — the list
   may be empty. Do **not** implement working OSC connect or OSC discovery in
   this thread. Empty copy must not say “enable Bluetooth”.
5. **Simulator list is a static catalog** (no BLE, no OSC). Tapping a row
   calls `connectWithOptions(..., simulate: true)` and runs `DeviceSimulator`
   locally. Crown/Notion simulator rows do **not** open a UDP socket.
6. **Simulator catalog labels (exact):**
   - Muse 2
   - Muse S
   - Muse S Athena
   - Crown (OSC)
   - Notion (OSC)
7. **Notion** is Neurosity’s other 8-channel headset (Notion 1/2). Crown is
   the current one. Both simulator rows use `DeviceConfig::neurosity_crown()`.
   Variants differ by display name / firmware only — not Athena fNIRS packets
   or extra Muse channels.
8. **Crown Start stays refused** whenever `kind == DeviceKind.neurosity`
   (real or simulated). Muse simulator rows stay startable.
9. **Remove the Settings card titled “AI sleep guardrail”** (per-protocol
   on/off). Keep `AiEngineCard` (model download/import). Keep
   `Settings.guardFeatureFor` and migration tests.
10. **Settings scroll:** persist music cutoff on `onChangeEnd`, not every
    `onChanged` tick; `RepaintBoundary` per card; drop or lower RangeSlider
    `divisions: 200`. Do not slice `Settings` into new Riverpod providers.
11. **Reuse pref key** `enable_simulated_devices`. No migration. Debug mode
    off while Simulator is selected → fall back to Muse. `lastDeviceId`
    starting `sim:` is ignored when debug is off.

---

## Target connect UI

| Device type | Found-device list |
|---|---|
| Muse | BLE scan, Muse headsets only |
| Neurosity | OSC-discovered Crown/Notion only. No BLE. Empty is OK. |
| Simulator | Static catalog below. Immediate local simulator. |

| id | kind | connected name | firmware |
|---|---|---|---|
| `sim:muse-2` | muse | Muse 2 (Simulated) | Classic |
| `sim:muse-s` | muse | Muse S (Simulated) | Classic |
| `sim:muse-s-athena` | muse | Muse S Athena (Simulated) | `Athena` |
| `sim:crown-osc` | neurosity | Crown (Simulated) | (sim string) |
| `sim:notion-osc` | neurosity | Notion (Simulated) | (sim string) |

Firmware `Athena` matters: `sweep_eeg_view.dart` keys off
`status.firmware == 'Athena'`.

| Source | `DeviceKind` | `simulate` | Discovery |
|---|---|---|---|
| Muse | `muse` | false | BLE `scan()`, keep Muse only |
| Neurosity | `neurosity` | false | OSC only. Do not call BLE `scan()`. |
| Simulator | `muse` or `neurosity` from the tapped row | true | Static catalog |

Delete the in-dialog “Simulator (Debug)” panel / Enable Simulator switch.
Keep the Neurosity experimental banner for real Neurosity only.
Hide Rescan while source is Simulator.

---

## Implementation steps (landed)

1. Remove `_GuardrailCard` from `settings_view.dart`. Drop unused imports.
2. Settings scroll: RangeSlider persist-on-end + `RepaintBoundary` (+ fewer
   divisions) in `music_settings_panel.dart` / `settings_view.dart`. Debug
   mode card after About.
3. Collapse `DeviceKind` to `Muse` \| `Neurosity`. Update
   `device_config.rs`, `simulator.rs`, `muse.rs`, `features.rs` tests,
   `deviceKindIsCrown`. Run `flutter_rust_bridge_codegen generate`. Commit
   both generated sides.
4. Dart `ConnectSource { muse, neurosity, simulator }` on `AppUiState`.
   Connect window + `connection_provider` scan/connect behavior as in the
   tables. Simulator catalog. `connect_with_options` simulate branch maps
   `sim:*` → name/firmware. Autoconnect skips BLE for `sim:*` when debug is
   on.

---

## Out of scope

- Making Crown / Notion OSC connect work (including OSC discovery)
- Unlocking Crown sessions
- Athena-accurate optical / extra Muse channels
- Auto-scan-on-launch vs AGENTS.md (only touch `_init` if already in the diff)

---

## Verify

- Debug off: dropdown is Muse \| Neurosity. No Simulator row, no old
  Simulate switch.
- Debug on: Simulator appears. List is the five catalog rows; Rescan hidden;
  tap Muse S connects without BLE; tap Crown (OSC) connects the 8-ch
  simulator (no UDP); status name/firmware match the table; Start on
  simulated Crown/Notion is still refused.
- Muse: BLE list, no Crown/Notion rows from BLE names.
- Neurosity: no BLE scan; list is OSC-only (empty is OK); banner still shown;
  tapping a real OSC row is allowed to fail.
- Settings: no “AI sleep guardrail” card; AI engine card remains; debug
  switch at bottom; scroll should not hitch on the music slider.
- `flutter analyze lib/src` clean. `cargo test --lib` for
  features/device_config.

---

## Files (expected)

- `lib/src/connect_window.dart`
- `lib/src/connection_provider.dart`
- `lib/src/settings.dart`
- `lib/src/views/settings_view.dart`
- `lib/src/views/music_settings_panel.dart`
- `lib/src/feedback/protocol.dart` (`deviceKindIsCrown`)
- `rust/src/api/device_config.rs`
- `rust/src/api/muse.rs`
- `rust/src/api/simulator.rs`
- `rust/src/api/features.rs` (tests)
- generated: `rust/src/frb_generated.rs`, `lib/src/rust/`
- `lib/src/connect_source.dart`
- tests under `test/connect_source_test.dart`
- `.ai/architecture.md` Devices section (updated)
