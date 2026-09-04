# Contract — Athena optical stream (raw)

| Field | Value |
|---|---|
| Status | **Queued.** Do not start until connect-simulator-ux is done and this is the active-task. |
| Date | 2026-09-04 |
| Branch (when started) | new, from `main` (or from connect-simulator-ux after merge). Suggested: `feat/athena-optics`. |
| muse-rs | New **breaking** tag on `windwerfer/muse-rs` (**`0.2.0`**). Patch `flutter_muse_ml` to that tag. `third_party/muse-rs/` is a reference checkout — update it when the tag exists. |
| Depends on | Frozen connect UX ([../connect-simulator-ux.md](../connect-simulator-ux.md)). Headset-only simulator (`Eeg`/`Ppg`/IMU/`Telemetry`). |
| Do not mix | Pipeline-contract Key Decisions; Crown Start; OSC connect/discovery; v5 computed columnar layout; Classic PPG wire; Athena-accurate HbO/SpO₂ product claims. |

Key Decisions below are frozen once implementation starts. Do not reopen
them in the implementing PRs.

---

## Problem

Athena multiplexes optical samples on GATT `273e0013` as tags `0x34` /
`0x35` / `0x36` (Optics4 / 8 / 16, 20-bit LE, 64 Hz). muse-rs **does not
expose that stream**:

- `0x34` / `0x35`: first **3** lanes squeezed into `MuseEvent::Ppg` and
  labelled ambient / IR / red (Classic PPG names). Remaining lanes dropped.
- `0x36`: payload skipped, zero events.

Those three names are a compatibility hack. OpenMuse’s Optics4 map is
`LI_NIR, RI_NIR, LI_IR, RI_IR` — not ambient/IR/red. Red and ambient only
appear in Optics16. The app’s `compute_pulse` / `compute_spo2` assume
Classic ch1=IR 850 nm, ch2=red 660 nm. On Athena that is wrong.

We have **no Athena hardware** (Classic Muse S only). Community parsers
agree on **packet geometry**. They **disagree** on which lane is 730 vs
850 nm. This series records the **raw optical stream** correctly and treats
names as a versioned catalog, not as parse output.

---

## Goals

1. **muse-rs** exposes a first-class optical event for all three layouts.
   Athena **never** emits `Ppg`. Classic PPG path is untouched.
2. **Parse + tests** for 20-bit unpack, 4/8/16 sizes, and “Athena emits
   `Optics` not `Ppg`”. Hex goldens. `0x36` is decoded.
3. **TUI** plots raw lanes with assumed OpenMuse names, layout in the
   status line, pages for 16-ch. No HR/SpO₂ in the TUI.
4. **App** maps `Optics` → `MuseEventDto::Optics`, encodes a new session
   body tag, writes **raw ADC counts**. Classic `Ppg` / pulse / SpO₂
   unchanged for Muse 2 / Muse S Classic.
5. **Simulator** Athena catalog row emits `Optics` (OpenMuse lane count),
   not Classic 3-ch `Ppg`.
6. Labels live in a **mapping catalog** (`openmuse-v1`). A later swap of
   730/850 is a catalog bump, not a re-decode of BLE or a rewrite of
   saved bytes.

## Non-goals

- Validating channel names on a head. Assumed map is explicit in the file
  and the TUI title.
- Athena **SpO₂** (needs 660 nm red; Optics4/8 do not have it). Do not run
  `compute_spo2` on optics lanes.
- Athena **HR as a product metric**. TUI may *look* pulsatile; do not
  wire `compute_pulse` to optics in this series.
- fNIRS MBLL / HbO / HbR / TSI / DPF / source–detector distance.
- Changing default Athena startup preset (`p1045` / Optics4). Parser must
  still accept 8/16 if they appear. Optional `start` preset override is
  allowed in muse-rs so a future debug flag can request `p1034`/`p1041`.
- Unlocking Crown sessions, OSC discovery, pipeline-contract reopen.
- Live Flutter optics charts (TUI is the inspector). Status-bar PPG for
  Athena stays absent or explicitly “optics, unlabelled physiology”.
- Length-prefixing *old* session tags. Unknown-tag abort in
  `parse_records` stays (`_ => return`). New optics tag is additive; old
  binaries truncate the body at the first optics record. Classic sessions
  without the tag are unchanged.
- Relabelling Classic `PpgDto.channel` 0/1/2.

---

## Key decisions (do not reopen)

1. **`MuseEvent::Optics` is a new variant.** `Ppg` remains Classic-only
   (three GATT characteristics, 24-bit BE, 6 samples @ 64 Hz). Athena
   `parse_athena_notification` must not construct `PpgReading`. This is a
   **breaking** change for exhaustiveness → muse-rs **0.2.0**, not 0.1.2.

2. **Raw values are 20-bit ADC counts** (`u32` in muse-rs, `f64` of those
   integers on the DTO / session `f32` payload). Do **not** store
   `value / 32768` as the recording truth. Display scale is UI-only.

3. **One optical frame per tag**, all lanes, sample-major unpack:

   | Tag | Layout | ch | samples/ch | payload |
   |-----|--------|----|------------|---------|
   | `0x34` | Optics4 | 4 | 3 | 30 B |
   | `0x35` | Optics8 | 8 | 2 | 40 B |
   | `0x36` | Optics16 | 16 | 1 | 40 B |

   Sample-major: `[s0_ch0..s0_chN, s1_ch0..]`. Same as current muse-rs
   `0x34` comment and OpenMuse `_decode_optics_data`.

4. **Framing stays the walker we already use** (do not “fix” it to a
   different OpenMuse story). `parse.rs` documents:

   ```
   byte[0]    packet length
   [1..8]     header
   byte[9]    first subpacket tag
   [10..13]   4-byte meta
   [14..]     first payload, then [TAG][META4][PAYLOAD]…
   ```

   `HEADER=9` means “first tag at offset 9”, payload at 14. Goldens are
   **full notifications** this walker accepts, not Python dump lines
   unless adapted.

5. **Names are not parse output.** Parse yields `OpticsLayout` +
   `Vec<u32>` per lane (or a packed matrix). Display names come from
   mapping id `openmuse-v1`:

   OpenMuse `OPTICS_CHANNELS` (16), sliced:

   | Layout | Indices into the 16-name table |
   |--------|--------------------------------|
   | Optics4 | 4,5,6,7 → `LI_NIR, RI_NIR, LI_IR, RI_IR` |
   | Optics8 | 0..7 → outers then inners, NIR+IR only |
   | Optics16 | 0..15 → NIR/IR for four sites, then RED/AMB for four sites |

   OpenMuse comments: NIR=730 nm, IR=850 nm, RED, AMB. **Amused-EEG
   swaps 730/850 on the same strings.** We ship OpenMuse as v1 and
   document the dispute. Do not invent a third map.

6. **Physiology is catalog-bound, and this series does not enable it
   for Athena.** Forwarder keeps `ppg_ir_buffer` / `ppg_red_buffer`
   filled **only** from `MuseEventDto::Ppg`. `Optics` does not enter
   those buffers. Pulse/SpO₂ on Athena will go silent (today they were
   garbage from mislabelled lanes). That is intended.

7. **Session body tag `FORMAT_TAG_OPTICS = 11`.** Record layout (LE):

   ```
   u8   tag = 11
   f64  timestamp_ms
   u8   layout   // 4 | 8 | 16
   u8   mapping  // 0 = openmuse-v1
   u16  n_samples_per_channel
   then layout * n_samples f32  // sample-major, raw counts as f32
   ```

   Size is determined by `layout` and `n_samples`; no extra length
   prefix. Parser must reject `layout` other than 4/8/16.
   `streams.ppg` in metadata stays Classic IR+Red. Add
   `streams.optics: { layout, mappingId, rateHz: 64, channels: [...] }`.
   This **is** a v5 body additive change; it is allowed in this series
   (pipeline-contract forbade it *there*). Old `parse_records` hits
   tag 11 and **stops**. Acceptable: optics sessions require this
   binary. Add a golden that a body *without* tag 11 still parses.

8. **Default preset remains `p1045` (Optics4).** Parser + TUI + session
   must handle 8 and 16 anyway. Optional muse-rs API:
   `start_with_athena_preset(&str)` defaulting to `p1045`. Do not
   silently switch the app to `p1041`.

9. **Simulator:** `sim:muse-s-athena` emits `Optics` Optics4 @ 64 Hz
   (3 samples/ch, 4 lanes, distinct DC offsets so lanes are separable).
   Other Muse sim rows stay Classic `Ppg`. Crown sim still has no PPG
   and no optics.

10. **TUI is the optical debugger.** Key `2` shows Classic PPG **or**
    Athena optics from live events (not both in one buffer). 16-ch is
    paged (NIR+IR / RED+AMB). Status: `Optics4 openmuse-v1`.
    `--simulate` gains optics only with an explicit flag
    (`--simulate-optics 4|8|16`) so default simulate stays EEG-focused.

11. **Work order is crate → TUI → app session.** Do not FRB-codegen
    `OpticsDto` until muse-rs `0.2.0` is tagged and the patch points at
    it. Do not teach the app simulator to emit `Optics` while the
    library still emits fake `Ppg`.

12. **No shortcuts:** extract `decode_optics_20bit(&[u8], n_ch) ->
    Vec<u32>` as a pure function next to `decode_ppg_samples`. Table-
    driven tests. Do not leave `n_ch.min(3)`. Do not use `unwrap` on
    BLE payloads. Unknown Athena tags keep one-byte resync.

---

## Data model (muse-rs)

Keep modules as they are: `types` (public events), `parse` (pure
decoders), `protocol` (constants + name tables), `muse_client` (BLE).
Optical **geometry** lives in `protocol`; **unpack** in `parse`;
**event** in `types`. The TUI does not unpack bits.

Suggested types (names can match this shape):

```rust
/// Athena optical layout. Not used for Classic PPG.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OpticsLayout {
    Ch4,  // tag 0x34
    Ch8,  // 0x35
    Ch16, // 0x36
}

impl OpticsLayout {
    pub fn channel_count(self) -> usize { /* 4 / 8 / 16 */ }
    pub fn samples_per_packet(self) -> usize { /* 3 / 2 / 1 */ }
    pub fn payload_len(self) -> usize { /* 30 / 40 / 40 */ }
    pub fn from_tag(tag: u8) -> Option<Self> { /* 0x34..0x36 */ }
}

/// One Athena optical subpacket, all lanes.
/// `channels[lane][sample]` — lane count = layout.channel_count().
/// Values are 20-bit ADC (0 .. 2^20-1).
#[derive(Clone, Debug)]
pub struct OpticsReading {
    pub layout: OpticsLayout,
    pub timestamp: f64, // 0.0 on Athena until a later ts series; same as EEG
    pub channels: Vec<Vec<u32>>,
}

pub enum MuseEvent {
    Eeg(EegReading),
    Ppg(PpgReading),      // Classic only
    Optics(OpticsReading), // Athena only
    // …unchanged
}
```

`protocol.rs`: `OPTICS_FREQUENCY = 64.0`, payload lens, **OpenMuse v1
name tables** as `&'static [&str]` plus `optics_names(layout) ->
&'static [&str]`. Mapping id constant `OPTICS_MAPPING_OPENMUSE_V1`.

Do **not** put wavelength nanometres on the event. A doc comment on the
name table cites OpenMuse `decode.py` and the Amused-EEG 730/850 swap.

`PpgReading` docs: Classic GATT only; Athena must not produce it.

---

## Data model (app)

```rust
// muse.rs — new DTO, FRB freezed
pub enum OpticsLayoutDto { Ch4, Ch8, Ch16 }

pub struct OpticsDto {
    pub layout: OpticsLayoutDto,
    pub mapping_id: String, // "openmuse-v1"
    pub timestamp: f64,
    /// Sample-major flattened: len = channel_count * n_samples
    /// or nested `Vec<Vec<f64>>` if FRB is cleaner — pick one, test it.
    pub channels: Vec<Vec<f64>>,
}

pub enum MuseEventDto {
    // …
    Ppg(PpgDto),       // Classic
    Optics(OpticsDto), // Athena
}
```

`map_event`: `MuseEvent::Optics` → DTO; `Ppg` unchanged.

Forwarder: `Optics` is forwarded to the sink and to `encode_session_event`.
It does **not** extend PPG IR/Red buffers. Athena timestamps 0.0: either
leave 0.0 (session still has order) or reuse the EEG virtual-clock
pattern **only if** tests show we need it. Prefer recording
`now_ms()` at forwarder ingest for optics if Athena ts is 0.0 — document
the choice in the PR. Do not invent per-lane 64 Hz clocks unless tests
require it.

`DeviceSimulator`: Athena config (`firmware == Athena` / catalog id
`sim:muse-s-athena`) runs an optics task (64 Hz, 4 lanes, 3 samples)
instead of `run_ppg`. Other Muse sims keep PPG.

---

## What “correct” means without hardware

**In scope to be sure of:**

- Given a well-formed notification, we emit `Optics` with the right
  `layout`, lane count, samples/ch, and 20-bit integers matching a
  hand-built payload (and, if available, an OpenMuse-adapted hex dump).
- Those integers round-trip through `encode_session_event` /
  `session_parse_body`.
- Classic `Ppg` still round-trips. Athena path no longer yields `Ppg`.

**Not in scope to be sure of:**

- Lane 0 is left-inner 730 nm. That is `openmuse-v1`, revisable.
- SpO₂ / HR numbers.

Confidence on parse+save: **high after goldens**, same class as Athena
EEG unpack in this crate (also unproven on our desk). Framing goldens
must use the muse-rs walker. Do not claim 99% before those tests exist.

---

## References (do not copy blindly)

- OpenMuse `decode.py` — SENSORS table, 20-bit LSB, 16-name list, Optics4
  slice `(4,5,6,7)`. Default OpenMuse *app* preset is `p1041` (16-ch);
  **ours stays `p1045`**.
- Amused-EEG `muse_athena_protocol.py` — same tags/sizes; Optics8 names
  with **swapped** 850/735 vs OpenMuse comments.
- AbosaSzakal/MuseAthenaDataformatParser — tag nibble documentation.
- Mind Monitor: “Athena uses Optics, not PPG.”
- In-tree: `third_party/muse-rs/src/parse.rs` (`0x34`/`0x35`/`0x36`),
  `types.rs` `PpgReading`, `bin/tui.rs` 3-ch PPG view,
  `.ai/muse-rs.md` (Athena optical gap).

---

## Size (approximate)

Hand-written, excluding FRB codegen churn (~500–800 lines generated).

| Area | Add | Change |
|------|-----|--------|
| muse-rs `types` + `protocol` | 180–220 | 40–60 |
| muse-rs `parse` + goldens | 400–550 | 80–120 |
| muse-rs client / docs / prelude | 60–90 | 40–60 |
| muse-rs TUI + simulate-optics | 320–420 | 100–140 |
| app DTO + `map_event` + forwarder | 80–120 | 40–70 |
| app `session_format` + tests | 180–250 | 30–50 |
| app simulator + tests | 100–140 | 30–50 |
| app docs (`.ai`, format README) | 80–120 | 40 |
| **Total handwritten** | **~1400–1900** | **~400–590** |

Plan on **~2.0–2.5k net diff** in human-edited files, **~2.8–3.5k**
with generated FRB. TUI is the largest single file (`tui.rs` is already
~1.6k). Parse tests are the second-largest *new* chunk (`parse.rs` has
**no tests today** — this series adds them; do not skip).

---

## Verify (when implemented)

- `cargo test` in muse-rs: 20-bit table, 4/8/16 payload sizes, `0x36`
  emits 16 lanes, Athena fixture has zero `Ppg`, Classic PPG fixture
  unchanged.
- TUI: Classic still `2` = 3 PPG names. Simulated optics 4/8/16 draws
  the right count; 16-ch pages. Status shows layout + `openmuse-v1`.
- App: `cargo test --lib session_format` + new optics goldens;
  `cargo test --lib simulator` Athena has optics, no Ppg; Classic sim
  still Ppg. `flutter analyze lib/src`.
- Athena firmware in the app: no SpO₂/HR from optics (buffers empty is
  OK). Classic headset still pulse/SpO₂ from `Ppg`.
- Old `.muse.feedback` without tag 11 still parses.

Hardware (Athena user, later, not a gate for merge): TUI `Optics4`
traces move; compare lane shapes to Mind Monitor / OpenMuse. Names may
be wrong; **counts should exist**.
