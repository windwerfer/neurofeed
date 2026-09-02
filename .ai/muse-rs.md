# muse-rs

Muse BLE protocol + transport. We depend on upstream
`github.com/eugenehp/muse-rs` tag `0.1.0`, then **patch** it to our fork:

```toml
muse-rs = { git = "https://github.com/eugenehp/muse-rs.git", tag = "0.1.0", default-features = false }

[patch.'https://github.com/eugenehp/muse-rs.git']
muse-rs = { git = "https://github.com/windwerfer/muse-rs.git", tag = "0.1.1" }
```

The `[patch]` key must match the **dependency source URL**, not crates.io
(unlike btleplug). `third_party/muse-rs/` is a reference checkout, not the
build input. Bump the fork tag in `rust/Cargo.toml` when it advances.

`connect()` in `rust/src/api/muse.rs` calls `handle.start(true, false)`:
`enable_ppg=true` → Classic preset `p50` (EEG + PPG). Athena ignores the flag
(`p1045`). If Classic connection stability regresses, the old delayed `h/s/p21/d`
sequence is in the parent of commit `217cefe`.

## Classic vs Athena battery

Interaxon splits Muse S firmware into **Classic** (Muse 2016, Muse 2, older
Muse S) and **Athena** (newer Muse S).

| | Classic | Athena |
|---|---------|--------|
| Characteristic | `273e000b` (telemetry) | `273e0013` (bundled EEG/PPG/IMU/telemetry) |
| Rate | ~1 Hz | bundled |
| Endian | u16 BE | u16 LE |
| Percent | `u16 / 512.0` | `u16 / 256.0` |

muse-rs tries Athena `dc001` first; if rejected it falls back to Classic `d`
and the split-characteristic parser.

### `bp_override`

The `v1` control response includes `bp` (0–100). The forwarder in
`rust/src/api/muse.rs` captures it from `Control` events and overrides the raw
telemetry value. If `bp` never arrives, the raw characteristic value is used.

Status bar (`lib/src/status_bar.dart`): if `batteryLevel < 1` treat as a
fraction and ×100; otherwise already 0–100.

## Protocol decoders

Pure (no BLE): muse-rs `parse.rs` / `protocol.rs` / `types.rs`. RSSI filter:
`scan_all()` keeps only `props.rssi.is_some()`; our `scan()` mirrors that (no
`rssi` on `DeviceInfo`). Connect timeout: `setup_peripheral()` disconnects +
500 ms sleep so retry is not stuck "In Progress".
