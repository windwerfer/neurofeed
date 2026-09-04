# Handoff — Athena optical stream (raw)

| Field | Value |
|---|---|
| Date | 2026-09-04 |
| Spec | [athena-optics-contract.md](athena-optics-contract.md) — **queued; freeze Key Decisions when you start.** |
| Suggested branch | `feat/athena-optics` from `main` (after connect-simulator-ux merges). Do **not** pile this onto `feat/connect-simulator-ux`. |
| muse-rs | Implement on **`windwerfer/muse-rs`**, tag **`0.2.0`**, then point `flutter_muse_ml` `[patch.'https://github.com/eugenehp/muse-rs.git']` at that tag. Copy into `third_party/muse-rs/` as the reference tree. |
| Do not mix | Crown Start, OSC connect, pipeline-contract Key Decisions, Classic PPG GATT, Athena SpO₂/HR/MBLL product, connect-dropdown redesign. |

Read the contract first. This file is implementer order, file list, and
pitfalls. Do not re-litigate names vs 730/850 here.

---

## What this project is doing

Muse ML talks to headsets through **muse-rs**. Classic Muse 2 / Muse S
PPG is three BLE characteristics → `MuseEvent::Ppg` → `PpgDto` → session
tag 5 → `compute_pulse` / `compute_spo2`.

Athena puts **optics** on the multiplexed characteristic. muse-rs
currently:

- Maps 3 of 4/8 optical lanes to `Ppg` with Classic names.
- Skips 16-ch (`0x36`).
- TUI key `2` always draws Ambient / Infrared / Red.

This thread: **decode all optical lanes as `Optics`, save raw ADC,
inspect in the TUI, keep Classic PPG honest.** Labels = `openmuse-v1`
catalog, not “we measured 730 nm.”

Owner of the crate is a **git dep**. The app must not grow a second
Athena parser in `rust/src/api/`.

---

## Frozen decisions (repeat — do not reopen)

See contract Key Decisions 1–12. Short form:

- New `MuseEvent::Optics`; Athena never emits `Ppg`. Breaking → **0.2.0**.
- Store 20-bit counts. OpenMuse names are mapping id `openmuse-v1`.
- Session tag **11**, additive. Old parsers truncate at first optics record.
- No Athena pulse/SpO₂ in the forwarder. Default preset still `p1045`.
- Crate → TUI → tag → app DTO/session → simulator. No FRB until 0.2.0 exists.

---

## Current code (why it is messy)

### muse-rs (`third_party/muse-rs/` reference; edit the fork)

| File | What is wrong |
|------|----------------|
| `src/parse.rs` `0x34`/`0x35` | `for ch in 0..n_ch.min(3)` → `PpgReading`. 4th/5th… dropped. |
| `src/parse.rs` `0x36` | `idx = end` with comment “not yet mapped”. |
| `src/parse.rs` | **No unit tests.** 20-bit unpack is inline in the match arms, not a `decode_optics_20bit`. |
| `src/types.rs` | `PpgReading` claims Athena `p1045` always included as PPG. `MuseEvent` docs contradict themselves (`Ppg` Athena ✓ vs ✗). |
| `src/protocol.rs` | `ATHENA_PPG_CHANNELS = 3`, names ambient/IR/red. That is the hack. |
| `src/muse_client.rs` | Fine for transport. `start()` Athena always `p1045`. `enable_ppg` comment still says optical “not yet decoded”. |
| `src/lib.rs` | README-level docs say Athena PPG is 3-ch ambient/IR/red. |
| `src/bin/tui.rs` | `PPG_NUM_CH = 3`, `ViewMode::Ppg` only. `push_ppg` ignores ch≥3. `--simulate` has **no** PPG/optics. EEG view drops Athena ch 4–7 (`electrode < NUM_CH`) — **out of scope** unless it is a one-line ignore; do not expand EEG to 8 in this thread. |

### app

| File | What happens today |
|------|---------------------|
| `rust/src/api/muse.rs` `map_event` | `Ppg` only. No optics. |
| forwarder | ch1 IR / ch2 red buffers; 1 Hz pulse/SpO₂. Athena mislabelled PPG would feed this. After the crate change, Athena PPG events disappear — **do not** reconnect optics into those buffers. |
| `session_format.rs` | `FORMAT_TAG_PPG = 5`. `parse_records` `_ => return` on unknown tags. Tag 11 must be implemented on **encode and parse** together. |
| `simulator.rs` | Classic 3-ch PPG for `has_ppg`. Athena catalog row is still `DeviceConfig::muse()` + PPG. Must branch on identity / firmware. |
| `lib/src/rust/` | FRB. New DTO → `flutter_rust_bridge_codegen generate`, commit both sides. Rebuild `rust/target/release/` or `flutter run` content-hash-fails. |

---

## Crate design (fit muse-rs, no shortcuts)

Preserve the existing split:

```
protocol.rs   GATT, rates, layout geometry, OpenMuse name tables
parse.rs      pure bytes → samples / MuseEvent  (no BLE)
types.rs      public event structs
muse_client.rs  notify callback → parse_athena_notification → mpsc
bin/tui.rs    consume MuseEvent only
```

**Do:**

- `decode_optics_20bit(payload: &[u8], layout: OpticsLayout) -> Option<Vec<u32>>`
  returning **sample-major flat** `n_samples * n_ch` values, or `None` if
  `payload.len() != layout.payload_len()`. Mirror `decode_ppg_samples`.
- `optics_reading_from_payload(...) -> Option<OpticsReading>` that chunks
  into `channels: Vec<Vec<u32>>` (`channels[lane][sample]`).
- `OpticsLayout` methods for counts — no magic numbers in the `match tag`
  arms beyond `from_tag`.
- Table-driven tests in `parse.rs` (`#[cfg(test)] mod tests`). There are
  **zero** today; adding them is part of the work, not optional polish.
- Construct goldens **inside Rust** (known bit patterns → expected
  integers). Optionally one hex notification captured from OpenMuse
  adapted to the offset-9 walker. Do not pull Python as a test dep.

**Do not:**

- Decode 20-bit in the TUI or in `flutter_muse_ml`.
- `min(3)` anything.
- `include_bytes!` of a 2 MB BLE dump.
- Change Classic `decode_ppg_samples` / PPG characteristics.
- Make `PpgReading` generic over N channels.

**Semver:** new enum variant on `MuseEvent` is breaking. Tag **0.2.0**.
Crate `version` in `Cargo.toml` must match the git tag. App patch
`muse-rs` git tag `0.2.0`; keep `muse-rs = { git = eugenehp, tag = "0.1.0" }`
as the *dep source URL* (patch key trap — see `.ai/muse-rs.md`).

**Optional small API:** `MuseHandle::start` Athena still sends `p1045`.
Add `start_athena_preset(&self, preset: &str)` used only by TUI/debug.
App keeps `start(true, false)` → `p1045`. Needed so 8/16 can ever be
seen on hardware without a follow-up crate release.

---

## Implement in this order

Do not start step 4 until 1–3 are tagged. Do not start step 6 until 5
`flutter analyze` is clean.

### 1. muse-rs types + protocol

`types.rs`: `OpticsLayout`, `OpticsReading`, `MuseEvent::Optics`.
Fix `Ppg` / Athena docs so they stop lying.

`protocol.rs`: layout constants, `optics_names(layout)`,
`OPTICS_MAPPING_OPENMUSE_V1`, frequency 64. Keep `PPG_CHANNEL_NAMES`
for Classic.

`prelude` re-export the new types.

`cargo test --lib` still green (there may be few tests — do not break
compile of bins).

### 2. muse-rs parse + goldens

Extract 20-bit unpack. Rewrite `0x34`/`0x35`/`0x36` arms to
`OpticsReading`. **Zero** `Ppg` from those arms.

Tests (minimum):

1. Unpack a constructed 30 B Optics4 payload; 4 lanes × 3 samples;
   known values (e.g. lane i sample s = `0x10000 * i + s`).
2. Optics8 40 B → 8×2; Optics16 40 B → 16×1.
3. Short payload → `None` / skip, no panic.
4. Full fake notification (len byte, header, tag `0x34`, 4 meta, 30 B)
   through `parse_athena_notification` → exactly one `Optics`,
   `layout == Ch4`, no `Ppg`.
5. Tag `0x36` → `Ch16`, 16 lanes.
6. Classic `parse_ppg_reading` still returns 6 samples (regression).

If a test needs EEG+optics in one notification, keep it; don’t block on
it.

### 3. muse-rs TUI

`App`: keep `ppg_bufs[3]` for Classic. Add `optics_bufs: Vec<VecDeque<f64>>`,
`optics_layout: Option<OpticsLayout>`. `clear()` both.

Event task: `Ppg` → `push_ppg`; `Optics` → size buffers to
`channel_count`, `push` each lane.

View: key `2` is “optical”. If `optics_layout` is `Some`, draw optics
(names from `optics_names`); else draw Classic 3-ch PPG.

Draw:

- 4-ch: four stacked rows (copy EEG layout).
- 8-ch: two columns × four rows, or eight stacked if height allows —
  prefer **2×4 grid** so 8 traces stay readable.
- 16-ch: two pages of 8 (NIR+IR vs RED+AMB). Keys `[` `]` or `n`/`m`.
  Status shows `page 1/2`.

Y axis: auto min/max per trace (already PPG style). Title =
`LI_NIR` etc. + dim `openmuse-v1`.

`--simulate-optics 4|8|16`: tokio interval 64 Hz, `OpticsReading` into
the same `App` path (or inject via a fake event). Distinct DC per lane
(`1000.0 * (lane+1) + 50.0 * sin(...)`). Default `--simulate` stays
EEG-only.

Optional: `tui --athena-preset p1034` calling `start_athena_preset`.
Nice, not a blocker for merge of steps 1–2.

### 4. Tag and patch the app

Push `windwerfer/muse-rs` tag `0.2.0`. In `rust/Cargo.toml` patch that
tag. Refresh `third_party/muse-rs` to the tag (reference copy).
`cargo build --manifest-path rust/Cargo.toml` must resolve.

### 5. App DTO + forwarder + session

`MuseEventDto::Optics` + `OpticsDto` + layout enum. `map_event`.

Forwarder: `sink.add` optics; **do not** touch PPG IR/Red buffers.
Pkt counters: add `optics` to the 1 Hz `pkt/s` log.

`session_format.rs`:

- `FORMAT_TAG_OPTICS: u8 = 11`
- encode as in the contract
- parse into `SessionData.optics: Vec<OpticsSampleRecord>` (new struct)
- goldens like `ppg_record_wire_layout`
- existing bodies without tag 11 still parse (`cargo test --lib session_format`)

`README_feedback_format.md`: document `streams.optics` and tag 11.
Unknown-tag abort: one sentence that old apps stop at first optics
record.

`flutter_rust_bridge_codegen generate`. Commit
`rust/src/frb_generated.rs` **and** `lib/src/rust/`.
`cargo build --release --manifest-path rust/Cargo.toml` so desktop
`flutter run` does not hash-mismatch.

`flutter analyze lib/src`.

### 6. App simulator

If catalog id is `sim:muse-s-athena` (or firmware Athena on a Muse
config), run optics @ 64 Hz (4 lanes, 3 samples) instead of PPG.
Tests: Athena sim → `Optics` events, `derived` Ppg count 0; Muse S
Classic sim still PPG all 3 ch.

Do not emit fake Bands/Pulse from the sim (already forbidden).

### 7. Docs

`.ai/muse-rs.md`: replace “gap / do not integrate” with “0.2.0 emits
`Optics`; mapping openmuse-v1; SpO₂ still Classic-only.”
`.ai/architecture.md` one line on optics stream.
`.ai/active-task.md` when this *is* the thread.
Move this folder’s spec to live/archive when landed.

---

## Files (expected)

**Fork `muse-rs`**

- `src/types.rs`
- `src/protocol.rs`
- `src/parse.rs` (+ `#[cfg(test)]`)
- `src/muse_client.rs` (docs; optional preset helper)
- `src/lib.rs`
- `src/bin/tui.rs`
- `README.md` (supported-hardware table)
- `Cargo.toml` version `0.2.0`

**App**

- `rust/Cargo.toml` (patch tag)
- `rust/src/api/muse.rs`
- `rust/src/api/session_format.rs`
- `rust/src/api/simulator.rs`
- `rust/src/frb_generated.rs` + `lib/src/rust/**`
- `README_feedback_format.md`
- `.ai/muse-rs.md`, `.ai/architecture.md`
- `third_party/muse-rs/` snapshot after the tag

No Dart session encoder. No new Flutter chart widget in this series.

---

## Pitfalls

- **Patch URL** must stay eugenehp git URL, tag on windwerfer. Wrong
  `[patch]` key = silent old crate.
- **FRB enum** `MuseEventDto` new variant: every Dart `switch` /
  generated freezed file. `flutter analyze` will list misses; fix them.
  Prefer `_ =>` already used in `_onEvent`.
- **Tag 11 vs old parser:** a mixed EEG+optics recording opened in an
  old build **loses the tail of the body**. Do not backport skip-without-
  length. Changelog it.
- **Athena pulse/SpO₂ going to zero** is a behavior change. Status bar
  HR on Athena may vanish. Correct. Do not “fix” by feeding optics into
  IR/Red.
- **`n_ch.min(3)` leftover** in TUI or app = bug. Grep before merge.
- **Scale 1/32768** in the encoder = bug. Raw counts only.
- **Content hash:** codegen without release rebuild breaks `flutter run`.
- **8-ch EEG in TUI** is tempting while you are in `tui.rs`. Out of
  scope. Leave `NUM_CH = 4`.
- **OpenMuse default preset p1041** vs our `p1045`. Do not copy their
  CLI default.

---

## Size (approximate)

See contract table. Budget:

- muse-rs library + tests: **~0.7–0.9k** handwritten
- TUI: **~0.4–0.55k**
- app session/DTO/sim + docs: **~0.5–0.7k**
- FRB generated: **~0.5–0.8k** churn (do not hand-edit)

A careful implementer: **on the order of 2.5–3.5k lines touched**, about
half of that new parse tests + TUI, a quarter generated.

---

## Verify (copy from contract)

muse-rs `cargo test`; TUI simulate-optics 4/8/16; app
`session_format` + `simulator` tests; `flutter analyze lib/src`; Classic
PPG still drives pulse/SpO₂; Athena path does not; old sessions without
tag 11 parse.

No Athena headset required to merge. An Athena user later confirms
“traces move,” not “SpO₂ is 98%.”

---

## Resume / start here

1. Open [athena-optics-contract.md](athena-optics-contract.md), treat
   Key Decisions as frozen.
2. Branch `windwerfer/muse-rs` → steps 1–3 → tag `0.2.0`.
3. App branch `feat/athena-optics` → steps 4–7.

If interrupted after the tag, the app side is a straight FFI + session
tag job and should not reopen crate types.
