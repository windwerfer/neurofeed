# Handoff — connect simulator UX + settings cleanup

| Field | Value |
|---|---|
| Date | 2026-09-03 |
| Spec | [connect-simulator-ux.md](connect-simulator-ux.md) — **frozen. Read it first.** |
| Branch | `feat/connect-simulator-ux` (from `main` after session-charts archive) |
| Do not mix | Crown OSC connect, unlocking Crown Start, pipeline-contract Key Decisions, v5 byte layout |
| Status | Spec + this handoff only. **Not implemented.** |

The previous thread designed the work and stopped at docs. Implement in the
order below. Do not re-design the dropdown, `DeviceKind`, or OSC listing.

---

## What this project is doing

Muse ML: Flutter + Rust BLE headset app. Connect UI today dumps every
`DeviceKind` including Simulated* variants, and BLE-scans even for Neurosity
(Crown/Notion), which actually speak OSC. Simulator is almost unreachable
(`enable_simulated_devices` has no Settings toggle).

This thread:

1. Rework connect: Muse (BLE) / Neurosity (OSC list, empty OK) / Simulator
   (static catalog, debug-mode only).
2. Collapse Rust `DeviceKind` to Muse \| Neurosity. Simulation is `simulate`
   + `sim:*` ids, not extra enum variants. **FRB codegen required.**
3. Simulator catalog includes Muse 2, Muse S, Muse S Athena, **Crown (OSC)**,
   **Notion (OSC)**. Tapping those last two runs the local 8-ch simulator —
   no UDP. Real OSC connect stays broken.
4. Settings collaterals: delete “AI sleep guardrail” card; fix scroll hitch;
   add Debug mode switch at the bottom.

**Notion** is the other Neurosity 8-channel headset. Same
`DeviceConfig::neurosity_crown()` as Crown.

---

## Frozen decisions (repeat from spec — do not reopen)

1. Dropdown is Muse \| Neurosity \| Simulator. Simulator is `ConnectSource`.
2. `DeviceKind` is two values. Drop Simulated*.
3. Muse = BLE only. Neurosity = OSC only, never BLE. No OSC discovery/connect
   in this thread (empty list is OK).
4. Simulator = static catalog, local `DeviceSimulator`, no BLE, no OSC.
5. Catalog labels exact: Muse 2, Muse S, Muse S Athena, Crown (OSC), Notion (OSC).
6. Crown Start refused for `kind == neurosity` (real or simulated).
7. Remove Settings `_GuardrailCard`. Keep `AiEngineCard` and guard prefs.
8. Music cutoff persist on `onChangeEnd`. RepaintBoundary. Fewer slider divisions.
9. Reuse `enable_simulated_devices`. Debug off + Simulator selected → Muse.
   Ignore `sim:*` last-device when debug is off.

---

## Current code (why it is messy)

- `lib/src/connect_window.dart` — dropdown is `DeviceKind.values` (4 items).
  Extra Simulate switch gated on `settings.enableSimulatedDevices` (no
  Settings UI for that pref). Device list is unfiltered `state.devices`.
- `lib/src/connection_provider.dart` — `connectDeviceKind` + `connectSimulate`.
  `toggleConnectWindow` / `_startContinuousScan` always BLE-scan.
  `connectTo` retries + `_refreshDevice` BLE even when simulating.
- `rust/src/api/muse.rs` `scan()` — BLE; names containing Crown/Notion →
  `DeviceKind::Neurosity`. `connect_with_options` simulate branch hardcodes
  `"Muse S (Simulated)"` / `"Crown (Simulated)"`.
- `rust/src/api/device_config.rs` — four `DeviceKind` variants +
  `is_muse` / `is_neurosity` / `is_simulated` / `base_kind`. Feature registry
  already calls `base_kind()` everywhere.
- `rust/src/api/neurosity_osc.rs` — binds UDP **after** connect. No scan API.
- `lib/src/views/settings_view.dart` — `_GuardrailCard` (“AI sleep guardrail”);
  no Debug mode card. `lib/src/views/music_settings_panel.dart` RangeSlider
  `divisions: 200`, `onChanged` writes prefs + `notifyListeners()` every tick.
- Sessions do **not** persist `DeviceKind` (`DeviceInfoV5` is name/firmware/model).

---

## Implement in this order

Do not start step 3 until 1–2 compile and `flutter analyze lib/src` is clean.

### 1. Remove `_GuardrailCard`

`lib/src/views/settings_view.dart`. Drop unused imports (`guardrail_mode`,
protocol catalog if nothing else needs them). Keep `AiEngineCard`. Keep
`Settings.guardFeatureFor` + `test/settings_guardrail_migrate_test.dart`.

### 2. Settings scroll + Debug mode UI

- `music_settings_panel.dart`: persist cutoff on `onChangeEnd`; local state
  while dragging; never copy raw log-slider position into prefs. Drop or
  lower `divisions`. `RepaintBoundary` around the slider.
- `settings_view.dart`: `RepaintBoundary` per card. Last card after About:
  **Debug mode** switch bound to `enableSimulatedDevices`. Toggling off
  resets `ConnectSource` if it was Simulator (after step 4 exists; for this
  step just persist the pref).

### 3. Collapse `DeviceKind` + FRB

- `rust/src/api/device_config.rs`: enum `{ Muse, Neurosity }`. Delete
  Simulated* constructors, `is_simulated`, `base_kind`.
- `simulator.rs`: seed/firmware on Muse vs Neurosity.
- `muse.rs`: simulate branch still takes `kind` + `simulate`; name/firmware
  from `device_id` (`sim:*` table in the spec). Unknown sim id: Muse S /
  Crown fallbacks.
- `features.rs` tests: `SimulatedMuse` → `Muse`, etc.
- Dart `deviceKindIsCrown(kind)` → `kind == DeviceKind.neurosity`
  (`protocol.dart`; callers in `feedback_session.dart`, `protocol_builder.dart`,
  `feedback_state.dart`).
- **`flutter_rust_bridge_codegen generate`**. Commit both
  `rust/src/frb_generated.rs` and `lib/src/rust/`.
- `cargo test --lib` for device_config / features.

### 4. ConnectSource + catalog + scan behavior

- Dart enum `ConnectSource { muse, neurosity, simulator }` on `AppUiState`.
  Stop using `DeviceKind.values` as the dropdown.
- `setConnectSource`:
  - Muse: BLE continuous scan; keep Muse only.
  - Neurosity: do **not** BLE-scan; devices list stays empty (OSC later).
  - Simulator: stop BLE; `devices = catalog`; `connectSimulate = true`.
- Catalog `DeviceInfo` rows: ids/names/kinds in the spec table.
- `connectTo`: simulate → one attempt, skip `_refreshDevice`. Pass
  `kind` from the row (`muse` or `neurosity`) and `simulate: true`.
- Autoconnect: `sim:*` only if debug on; skip BLE.
- Debug off + source Simulator → Muse. Hide Simulator dropdown item.
- Hide Rescan for Simulator. Neurosity banner for real Neurosity only.
- Delete the in-dialog Simulate switch panel.

### Tests

- Catalog ids/labels.
- Dropdown sources with debug on/off.
- Muse list never includes Crown/Notion BLE names.
- Simulator includes Crown (OSC) and Notion (OSC).
- Debug-off drops Simulator and ignores `sim:*` last-device.
- Optional Rust unit test on sim id → name/firmware if extracted as a pure fn.

---

## Resume here

Nothing is implemented. Start at step 1.

| File | Role |
|------|------|
| `lib/src/views/settings_view.dart` | Guardrail card delete; cards; debug switch |
| `lib/src/views/music_settings_panel.dart` | RangeSlider jank |
| `lib/src/settings.dart` | `enableSimulatedDevices` already exists |
| `lib/src/connect_window.dart` | Dropdown + list |
| `lib/src/connection_provider.dart` | Scan/connect state |
| `rust/src/api/device_config.rs` | Enum collapse |
| `rust/src/api/muse.rs` | `scan` / `connect_with_options` |
| `rust/src/api/simulator.rs` | Seed/firmware |
| `lib/src/feedback/protocol.dart` | `deviceKindIsCrown` |

After landing, update `.ai/architecture.md` Devices section (today it still
documents four `DeviceKind` variants).

---

## Verify (from spec)

`flutter analyze lib/src`. Simulator path with debug on (five rows, Muse S
and Crown (OSC) both connect locally). Neurosity source does not BLE-scan.
Crown Start still refused for neurosity kind. Settings: no guardrail card;
debug switch at bottom.

Scroll feel: `flutter run -d linux` and scroll Settings — not verifiable in
headless CI.
