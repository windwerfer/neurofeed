# Session charts from v5 computed 1 Hz

**Status:** Implemented (steps 1–7). `flutter run` verified 2026-09-03.  
**Date:** 2026-09-02  
Merged to `main`. Spec kept as the implemented contract. Do not resurrect `SessionOverview`.

No old-format compatibility. Old `.muse.feedback` files are gone.

---

## Problem

v5 recording writes three temps (`.raw` / `.computed` / `.metadata`) and a 1 Hz computed stream. The post-session dashboard still tries to plot the **raw body** via `sessionParseBody`, which expects zstd **frames**. The v5 recorder appends naked records, so parse returns empty `SessionData`. Graphs are blank.

Save then feeds `Uint8List(0)` to `decodeImage` (the thumbnail `RepaintBoundary` is not in the tree when `prepared.x` is empty), throws, `_busy` sticks, temps stay in `.cache`. Even a successful finalize would write into scratch and skip `SessionStore.publishSession`.

The 400-bucket `SessionOverview` in metadata was a pre-v5 workaround so history could skip the fat raw body. It makes different-length sessions incomparable (one point = 1 s or 4 s). It is obsolete now that computed 1 Hz exists.

---

## Key decisions (do not reopen)

1. **Computed 1 Hz is the only waveform for summary charts** (bands, ATR/alpha-vs-theta, movement, HR, SpO₂, guardrail). X-axis is elapsed seconds. Not a fixed 400 buckets.
2. **No `metadata.summary` / `SessionOverview`.** Do not store a second downsampled series in JSON or SQLite.
3. **SQLite keeps scalars + thumbnail only** (list tiles). Detail always extracts computed from the file. A ~1 s wait is acceptable.
4. **Assemble a real v5 file into scratch at session end**, placeholder WebP is fine. Dashboard and history both call `v5ExtractComputed`. Save publishes that file to history (swap in real thumbnail + final metadata).
5. **One computed type after session end:** the FFI `ComputedFrame` from `lib/src/rust/api/session_format.dart` (Rust-owned JSON). One chart builder: `prepareChartDataFromComputed`.
6. **Raw body stays framed** (`sessionHeaderBytes` + `sessionFrameBytes`) so EDF/CSV/`sessionParseBody` work. Charts do not use raw.
7. **No old-format readers.** Delete overview fast-path, `fromData`, `cacheOverview`, `prepareChartDataFromOverview`.
8. **Paint-time decimation only** if a series has more points than pixels. Do not bake N=400 into the file.
9. **Do not add music cutoff to `ComputedFrame` in this pass** (would need FRB codegen). Music stays metadata: sparse `tracks` + 1 Hz `series`, **no 400-bucket `buckets`**. Guardrail waveform comes from `ComputedFrame.guardrail`; metadata drowsiness keeps **scalars only**.
10. **Do not change** v5 container layout (68-byte header), SQLite schema, BLE, Crown Start refuse, or `electrodeAf7`/`electrodeAf8` chart pads.

---

## Target lifecycle

```
RECORDING
  scratch/.cache/session_<ts>.raw        append-only framed .muse body
  scratch/.cache/session_<ts>.computed   JSONL (Dart sampler, crash log)
  scratch/.cache/session_<ts>.metadata   JSONL events (optional)

SESSION END (FeedbackStateNotifier.end, BEFORE phase=ended navigation)
  1. stop sampler, flush raw (sessionFrameBytes)
  2. parse JSONL → List<ffi.ComputedFrame>
     t already seconds-from-recording-start
  3. build SessionMetadata (no summary key; drowsiness scalars;
     music tracks+series; gestures; calibration; settings)
  4. containerEncodeV5(
       thumbnail: placeholder WebP,
       metadataJson: ...,
       computedFrames: that list,
       rawBody: framed .raw bytes)
     → scratch/session_<ts>.muse.feedback
  5. delete the three temps
  6. remember scratchV5Path; then set phase=ended
     (FeedbackSessionView pushReplacement → dashboard)

DASHBOARD (live, readOnly=false)
  v5ExtractComputed(scratch v5) → prepareChartDataFromComputed
  v5ParseHead → metadata for chips / notes / gestures / music
  RepaintBoundary always in tree (summary card)
  Save: capture PNG→WebP (or keep placeholder), rewrite v5,
        SessionStore.publishSession to history folder, delete scratch v5
  Discard: delete scratch v5

HISTORY (readOnly=true)
  storage.readFile(session_*.muse.feedback)
  v5ParseHead → full metadata (not the SQLite skeleton)
  v5ExtractComputed → same prepareChartDataFromComputed
  PDF/PNG export: same builder

CRASH RECOVERY
  scan scratchDirectory for leftover .muse.feedback (assembled)
    and/or leftover three-temps (assemble crashed)
  same assemble + publish / discard paths
  scan the real scratch dir, not getTemporaryDirectory()/sessions
```

```
Headset → recorder temps
        → end() assemble scratch v5
        → dashboard / history / PDF / PNG
              └─ v5ExtractComputed → prepareChartDataFromComputed
        → Save → history folder + SQLite scalars+thumb
```

---

## Data rules

### ComputedFrame.t

Seconds from recording (calibration) start: `0, 1, 2, …`.  
`ComputedSampler` today uses unix epoch — **must fix** or training-offset trim and gesture markers will not line up.

### Chart builder

`prepareChartDataFromComputed(frames, {trainingStartOffset, metric, conditions})`:

- Skip frames with `t < trainingStartOffset` when that offset is set.
- Relative AF7/AF8 powers via existing `_relativeAll` / autodrop (`total <= 0` drops a pad).
- Movement / pulse / SpO₂ from the frame fields (pulse/SpO₂ already 1 Hz; no confidence field on computed — plot if non-null).
- Stats chips from the same lists (peak alpha = max power in window, target %, stillness %, avg BPM / SpO₂ / alphaRel).
- `x` is `t - windowStart` in seconds (viewport already thinks in seconds).

### Metadata after this change

| Key | Keep? |
|-----|--------|
| protocol, times, device, streams, sessionSettings, calibration, gestures, protocolJson, notes, stats scalars | yes |
| `summary` / SessionOverview | **delete** |
| drowsiness `scoreTotalPct` / `meanSleepDir` / `threshold` | yes |
| drowsiness `series` / `buckets` | **delete** (plot from computed.guardrail) |
| music tracks + 1 Hz `series` + settings | yes |
| music `buckets` / `bucketWidthSecs` | **delete** |
| modelSnapshot | keep if already written |

### SQLite

No schema change. On `publishSession`, fill scalars from computed (avg HR, avg SpO₂, peak alpha, pct in target, avg movement, guardrail warn count, avg sleepDir, …). Thumbnail BLOB from the WebP/PNG we captured. `list()` stays list-tile data. Detail **must not** rely on `SessionMetadata.summary` from the list row.

### Thumbnail

- Placeholder: the 1×1 WebP already in `test/session_export_test.dart` (`_webp1x1`), or any valid WebP. Never `Uint8List(0)` into `image.decodeImage`.
- Capture: `RepaintBoundary` on a widget that **always** exists (the Session summary card), not behind `prepared.x.isNotEmpty`.
- `_encodeThumbnailWebP`: empty/invalid PNG → placeholder, no throw.
- `_save`: `try/finally` so `_busy` always clears.

### Raw body

`flushRaw()` must wrap pending bytes with `sessionFrameBytes` (restore pre-v5 recorder behavior). Header stays `sessionHeaderBytes()`. `containerEncodeV5` zstd-wraps that framed body as the raw section. Double-zstd is fine.

### Assembler

**One** function that calls `containerEncodeV5`. Callers:

- `end()` → scratch file
- Save → rewrite + `publishSession`
- Crash recovery → same assemble, then publish or discard

Delete the third copy in `SessionRecorder.finalize` writing a final file into `.cache`. Recorder exposes flush + read temps / return bytes; store or a small `SessionAssembler` owns the container.

---

## Implementation order (one branch, sequential)

Do in this order so the app is usable after step 3.

### 1. Recorder + sampler correctness

- `session_recorder.dart` `flushRaw`: `sessionFrameBytes`.
- `ComputedSampler._emitFrame`: `t` from recording start (pass a clock / start instant into the sampler).
- Keep JSONL append during record (crash log).

### 2. Assemble v5 in scratch at `end()`

- Parse `.computed` JSONL → FFI `ComputedFrame` (reuse `_toFfiFrame`; put it in one place).
- Build metadata **without** `summary`.
- `containerEncodeV5` + write `scratch/session_<id>.muse.feedback`.
- Delete three temps after successful assemble.
- `sessionFilePath` / a new `scratchV5Path` points at that file.
- Set `ended` only after the file exists (dashboard must not race).

### 3. Dashboard + save/discard

- Live dashboard: `v5ExtractComputed` + `v5ParseHead` on the scratch v5. **Do not** `SessionReader.read(.raw)`.
- `prepareChartDataFromComputed`.
- Thumbnail capture always possible; empty PNG safe.
- Save: `publishSession` into **history** storage (not `.cache`), then delete scratch v5.
- Discard: delete scratch v5.
- `_save` try/finally.

After this step: graphs show, Save produces a history file. Ship-quality for on-device use.

### 4. History + export

- History detail: read the container, `v5ParseHead` for metadata, `v5ExtractComputed` for charts. Ignore SQLite for series.
- `session_export.dart` / `session_pdf_export.dart`: `prepareChartDataFromComputed`, not `prepareChartData(SessionData)`.
- Raw `readMuse` + `sessionParseBody` remains for CSV/EDF only.

### 5. Delete 400-bucket machinery

- Remove `SessionOverview` (or leave a tombstone comment in the format README that it is gone).
- Remove `prepareChartDataFromOverview`, `cacheOverview`, dashboard overview branch, `fromColumns` stubs.
- Remove `SessionDrowsiness.decimate` / `buckets`; `SessionMusic.decimate` / `buckets`.
- Stop writing those fields in `feedback_state.dart` getters.
- Update `README_feedback_format.md`, `AGENTS.md` (session_summary / overview bullets), tests that construct 400-long lists.

### 6. Crash recovery

- Scan `scratchDirectory(storage)` for `session_*.muse.feedback` and for orphan three-temps.
- Three-temps → same assemble as `end()`.
- Assembled scratch v5 → Save via `publishSession` or Discard delete.
- Placeholder thumbnail is OK.

### 7. Tests + analyze

See handoff. `flutter analyze lib/src` must stay clean. `cargo test --lib session_format` stays green (no wire-layout change except using the existing framed raw). FRB codegen **not** required unless you touch Rust `ComputedFrame` fields (you should not).

---

## Files (expected)

| File | Change |
|------|--------|
| `lib/src/charts/session_recorder.dart` | frame raw; assemble helper or stop writing final `.cache` file; safe WebP |
| `lib/src/feedback/computed_sampler.dart` | `t` = session offset |
| `lib/src/feedback/computed_frame.dart` | recording JSONL only; map to FFI at assemble. Do not use after `end()` |
| `lib/src/feedback/feedback_recorder.dart` | `assembleScratchV5` / `scratchV5Path`; drop finalize-to-cache |
| `lib/src/feedback/feedback_state.dart` | `end()` assembles; music/drowsiness without buckets |
| `lib/src/feedback/session_store_core.dart` | `publishSession` from existing v5 bytes; scalars from computed; delete `cacheOverview`; list still SQLite scalars |
| `lib/src/feedback/session_chart_data.dart` | add `prepareChartDataFromComputed`; delete `prepareChartDataFromOverview` |
| `lib/src/views/feedback_dashboard.dart` | computed path only; save/discard; thumbnail |
| `lib/src/feedback/session_export.dart` | charts from computed |
| `lib/src/feedback/session_pdf_export.dart` | charts from computed |
| `lib/src/feedback/session_metadata.dart` | drop Overview; slim drowsiness/music |
| `lib/src/feedback/crash_recovery.dart` | real scratch dir; same assemble |
| `lib/src/feedback/session_v5_models.dart` | only if metadata shapes used here |
| `test/session_export_test.dart` | computed charts; empty-thumb assemble |
| `test/session_metadata_roundtrip_test.dart` | no 400-bucket summary |
| new `test/session_computed_charts_test.dart` | sampler t, JSONL→FFI, prepareChartDataFromComputed |
| `README_feedback_format.md` | drop section 5 overview; computed is SoT |
| `AGENTS.md` | drop overview-in-metadata hot spots |

Rust `session_format.rs`: **no layout change**. Optional: a unit test that naked records (no frames) are *not* what we write; framed parse stays golden.

---

## Out of scope

- Custom protocol builder (PR 7), Crown sessions, changing AF7/AF8 chart electrodes.
- Adding fields to Rust `ComputedFrame` / FRB regen.
- Render-time LTTB (only if a chart is actually slow; 1 Hz is enough).
- “Normalize x to 0–100% of session” compare toggle (view-only, later).
- Rebuilding `SessionStore.list()` file reconcile (nice-to-have; not required if publish always write-through SQLite).
- Recovering the user’s current `~/kkk/.cache` three-temps in production code beyond crash recovery scan.

---

## Done when

All true (2026-09-03, including `flutter run`):

- Post-session dashboard shows non-empty time-axis graphs from computed.
- Save writes `session_*.muse.feedback` to the **history** folder, SQLite row appears, scratch temps/v5 are gone, no hang.
- Reopening from history shows the same graphs.
- PDF/PNG charts match the dashboard builder.
- No `summary` key, no 400-bucket fields, no `decodeImage` on empty bytes.
- `flutter analyze lib/src` clean; new/updated Dart tests green (host `cargo build` for FFI tests).
