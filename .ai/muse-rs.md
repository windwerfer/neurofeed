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

## Athena optical / fNIRS (not in this app)

Athena does **not** expose Classic’s three PPG GATT characteristics
(`273e000f/0010/0011`, ambient / IR / red). Optical data is multiplexed on
`273e0013` as tagged subpackets. muse-rs `parse_athena_notification`:

| Tag | Wire | What muse-rs does |
|-----|------|-------------------|
| `0x34` Optics4 | 20-bit LE, 3 samples × 4 ch @ 64 Hz | First **3** channels → `MuseEvent::Ppg` (labelled ambient/IR/red). 4th dropped. Default preset `p1045` is this layout. |
| `0x35` Optics8 | 2 samples × 8 ch | First **3** of 8 → `Ppg`. Remaining 5 discarded. |
| `0x36` Optics16 | 1 sample × 16 ch | **Skipped** (`idx = end`). No events. |

So muse-rs is **not** forwarding a real fNIRS stream. It squeezes the first
three optical lanes into the Classic `PpgReading` type and throws the rest
away. Channel order on 8/16-ch layouts is **not** ambient/IR/red — community
maps (e.g. Amused-EEG `OPTICS_CHANNELS_8`) are left/right inner/outer at
~850 nm and ~735 nm. Mind Monitor’s stance: “Athena uses Optics, not PPG.”

Default Athena startup in muse-rs is preset `p1045` (EEG8 + Optics4, dim
LED). Interaxon’s 5-optode frontal fNIRS needs Optics8/16 (`p1034` / `p1041`
etc.) which we do not select and do not decode.

### Reference parsers (do not integrate without Athena hardware)

Bit-unpacking is documented. HbO/HbR is not a copy-paste:

- [OpenMuse](https://github.com/DominiqueMakowski/OpenMuse) (`decode.py`) —
  the table muse-rs already used. Lists PPG (850/730/660 nm) **and** a
  5-optode fNIRS array as separate Athena sensors.
- [Amused-EEG/amused-py](https://github.com/Amused-EEG/amused-py) —
  `muse_athena_protocol.py` + `muse_fnirs_processor.py` (MBLL → HbO/HbR/TSI).
- [AbosaSzakal/MuseAthenaDataformatParser](https://github.com/AbosaSzakal/MuseAthenaDataformatParser)
- [fuji3to4/muse-jsx](https://github.com/fuji3to4/muse-jsx) `MuseAthenaClient`

Productizing this means new muse-rs types (not `PpgReading`), a new DTO,
session columns, and UI — plus MBLL params (source-detector distance, DPF)
that nobody has calibrated here. **Needs a real Athena on the head.** Classic
Muse S cannot generate these packets. Frozen out of scope for connect UX:
[connect-simulator-ux.md](connect-simulator-ux.md).

Queued (do not start from the connect branch): raw optical stream as
`MuseEvent::Optics`, TUI inspector, session tag 11, OpenMuse v1 names as
mapping metadata only. No Athena SpO₂/HR product.
[TODO/athena-optics-contract.md](TODO/athena-optics-contract.md),
[TODO/handoff-athena-optics.md](TODO/handoff-athena-optics.md).
