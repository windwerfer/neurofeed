# Contract — Athena optical stream (raw)

| Field | Value |
|---|---|
| Status | **Implemented (first milestone, 2026-11-11).** |
| muse-rs | Fork `windwerfer/muse-rs`, branch `athena-optics`. Default Athena preset `p1041` (16 lanes). Distinct `MuseEvent::Optics` (never Classic `Ppg`). |
| Hardware | No Athena headset in house; simulator (`sim:athena`) and constructed packets are the test surface. |

## Decisions (t166)

1. **Default preset p1041** (16 channels), like upstream 0.2.3. 4- and 8-channel layouts stay selectable via Settings (`athena_preset`) and `optics.preset.set` (`p1045` / `p1044` and the other measured presets).
2. **Separate Optics stream**, not a widened PPG. Athena never feeds Classic PPG / HR / SpO2. `MuseEvent::Optics` carries per-lane samples, layout/preset, and lane labels `ambient` / `infrared` / `red` / `opt3`…`opt15`. Labels are names, not wavelength claims.
3. **First milestone includes an Optics monitor page** (shared monitor infrastructure: stacked lanes like Raw, sweep / Follow / Inspect, lane selector, overview off by default, compact + regular, safe area, graph-only phone landscape, EN/DE). Ring is 5 minutes, like Raw.
4. **Recording** only via Record / training, as before. New NFEDBIN tag **14** (`Optics`). Disk-backed loading of recorded waveforms stays on hold.

## Commands

- `optics.get` — raw ADC counts per lane, ≤ 60 s of the 5 min ring.
- `optics.preset.get` / `optics.preset.set` — current / saved Athena preset and lane list.
- `monitor.optics` — sweep/scroll and shown lanes.

Classic `hr.get` / `spo2.get` / `ppg.get` / `heart.get` stay Muse 2 / Muse S Classic only.

## Still unverified without hardware

Packet geometry on a live Athena (fw 3.x), BLE notify gaps, `set_athena_preset` mid-session, and whether the headset’s lane order matches these labels.
