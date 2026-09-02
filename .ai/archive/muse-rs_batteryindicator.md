# Battery Level in muse-rs: Classic vs Athena

The battery level arriving via BLE from a Muse headband depends on which firmware the Muse S is running. Interaxon splits the hardware into two protocols: **Classic** (Muse 2016, Muse 2, older Muse S) and **Athena** (newer Muse S, updated firmware).

## Classic Protocol (Older Muse S)
- **Characteristic:** `273e000b` (dedicated Telemetry characteristic)
- **Rate:** ~1 Hz
- **Format:** 5 big-endian 16-bit fields (u16 BE)
- **Calculation:** battery_percent = u16_from_bytes(payload[0..2]) / 512.0

## Athena Protocol (Newer Muse S)
- **Characteristic:** `273e0013` (universal characteristic bundling EEG, PPG, IMU, Telemetry)
- **Format:** little-endian (u16 LE)
- **Calculation:** battery_percent = u16_from_bytes(payload[0..2]) / 256.0

## muse-rs behavior
- Attempts Athena `dc001` data-start command first
- If rejected (Classic device), falls back to Classic `d` command
- Auto-switches parsers: split characteristics (`273e000b`) + big-endian `/ 512.0` math

## bp_override
The `v1` command response includes `bp` (battery percentage 0–100). The forwarder in `rust/src/api/muse.rs` captures it from `Control` events and overrides the raw telemetry value. If `bp` never arrives (or `send_command` fails silently), the raw value from the telemetry characteristic is used instead.

## Battery Display in Status Bar
In `lib/src/status_bar.dart`:
```dart
Text('${(state.batteryLevel < 1 ? state.batteryLevel * 100 : state.batteryLevel).toInt()}%'),
```
If `batteryLevel < 1`, it assumes a fraction (0.0–1.0) and multiplies by 100. Otherwise treats as 0–100 percentage directly.
