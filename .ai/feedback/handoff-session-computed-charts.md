# Handoff — session charts from v5 computed 1 Hz

| Field | Value |
|---|---|
| Date | 2026-09-02 |
| Spec | [`.ai/feeback/session-computed-charts.md`](session-computed-charts.md) — **frozen** |
| Branch | New topic branch off whatever is checked out. Do not push unless asked. |
| Do not mix | Custom protocol builder (handoff-pr7), Crown Start, v5 byte layout, FRB regen |
| Status | **Steps 1–4 landed on `feat/session-computed-charts` (`da4e119`). Resume: [handoff-session-computed-charts-resume.md](handoff-session-computed-charts-resume.md).** Spec is the law. Do not reopen Key Decisions. |

Read the spec first. Then this file. Then implement in the order below.

---

## What this project is doing

Muse ML: Flutter + Rust BLE. Feedback sessions record into a **v5** `.muse.feedback` container:

```
[68-byte header][WebP thumb][metadata zstd][computed 1 Hz zstd][raw zstd]
```

The 400-bucket `SessionOverview` in metadata is **gone**. Summary graphs (live dashboard, history, PDF/PNG) all plot **computed 1 Hz** via `v5ExtractComputed` → `prepareChartDataFromComputed`. X-axis is elapsed seconds.

At **session end**, assemble a real v5 file in **scratch** (placeholder WebP). Save **publishes** it to the history folder.

---

## Why the current app is broken (do not “fix” these in isolation)

On-device today:

1. Dashboard `SessionReader.read(.raw)` → `sessionParseBody` expects `[u32][zstd frame]…`. Recorder writes naked `encodeSessionEvent` records. Parse returns **empty** `SessionData`. Graphs blank.
2. Thumbnail `RepaintBoundary` is only built when `prepared.x.isNotEmpty`. Save passes `Uint8List(0)` → `image.decodeImage` **RangeError**. `_save` sets `_busy` and has no `finally` → spinner hang. Temps stay in `~/…/.cache/`.
3. `_save` writes empty `SessionOverview.fromColumns(bands: {}, …)` and `SessionRecorder.finalize` dumps a v5 into **scratch**, not `SessionStore.publishSession`.

Stack from the hang:

```
SessionRecorder._encodeThumbnailWebP (session_recorder.dart ~202)
SessionRecorder.finalize (~164)
_FeedbackDashboardViewState._save (feedback_dashboard.dart ~404)
```

---

## Frozen decisions (repeat from spec — do not reopen)

1. Computed 1 Hz = only waveform for summary charts.
2. No `metadata.summary` / `SessionOverview` / SQLite series.
3. Assemble v5 into scratch at `end()`; placeholder WebP OK.
4. One FFI `ComputedFrame` after end; one chart builder.
5. Raw body framed with `sessionFrameBytes` (EDF/CSV only).
6. No old-format readers.
7. Music: tracks + 1 Hz `series` in metadata, **no buckets**. Do **not** add music to `ComputedFrame` (no FRB).
8. Drowsiness waveform from `computed.guardrail`; metadata scalars only.
9. `ComputedSampler.t` = seconds from recording start, not unix epoch.

---

## Resume pointers (current code)

| What | Where |
|------|--------|
| Live dashboard load (broken: reads `.raw`) | `lib/src/views/feedback_dashboard.dart` `initState` ~64–86 |
| Empty overview stub on save | same file `_save` ~364–378 |
| Empty PNG into decoder | `lib/src/charts/session_recorder.dart` `_encodeThumbnailWebP` ~201, `_save` ~405 |
| Naked raw writes | `session_recorder.dart` `writeEvent` / `flushRaw` ~129 (missing `sessionFrameBytes`) |
| Pre-v5 flush that **did** frame | `git show 203d687^:lib/src/charts/session_recorder.dart` `flush()` |
| Sampler unix `t` | `lib/src/feedback/computed_sampler.dart` `_emitFrame` ~108 |
| `end()` flush then UI navigates | `feedback_state.dart` `end` ~934; `feedback_session.dart` ~37–46 **ended → dashboard** |
| Scratch dir | `session_storage.dart` `scratchDirectory` (history `.cache/` on desktop) |
| FFI extract / encode | `lib/src/rust/api/session_format.dart` `containerEncodeV5`, `v5ExtractComputed`, `v5ParseHead` |
| Duplicate Dart frame | `lib/src/feedback/computed_frame.dart` (JSONL during record only) |
| FFI `_toFfiFrame` copies | `session_recorder.dart` ~258, `crash_recovery.dart` ~165 — **dedupe into one helper** |
| `publishSession` | `session_store_core.dart` ~175 (history folder + SQLite). Dashboard no longer calls it. |
| `list()` skeleton metadata (no summary, no notes, no calibration) | `session_store_core.dart` ~89 — detail must `v5ParseHead`, not this row |
| Chart viewport already time-based | `feedback_dashboard.dart` `_ChartViewport` ~1225 |
| `prepareChartData` (raw body) / `prepareChartDataFromOverview` | `session_chart_data.dart` |
| Music/drowsiness 400-bucket | `feedback_state.dart` `sessionMusic` ~1227, drowsiness ~1455; `session_metadata.dart` `decimate` |
| Crash recovery scans the **wrong** dir | `crash_recovery.dart` `getTemporaryDirectory()/sessions` |
| Placeholder WebP bytes | `test/session_export_test.dart` `_webp1x1` |
| Export still uses raw `prepareChartData` | `session_export.dart` ~406, `session_pdf_export.dart` ~33 |
| Format doc still specifies 400-bucket summary | `README_feedback_format.md` §5 |

`sessionParseBody` / framed goldens: `rust/src/api/session_format.rs` `body()` helper ~792. Do not change the wire layout.

---

## Implement in this order

Stop and verify after step 3 on device/desktop (`flutter run -d linux`): graphs + Save.

### Step 1 — Raw frames + sampler `t`

- `flushRaw`: `sessionFrameBytes(data: pending)` then append (mirror pre-v5 `flush`).
- `ComputedSampler`: take recording start; `t` = seconds since that instant.
- Tests: write a few events, flush, `sessionParseBody` has bands; sampler `t` starts near 0.

### Step 2 — Assemble scratch v5 inside `end()`

Must finish **before** `phase = ended` (the session view navigates on that transition).

- Flush, read temps, JSONL → FFI frames (one shared `toFfiFrame`).
- Metadata **without** `summary`. Drowsiness scalars only. Music tracks+series, no buckets.
- `containerEncodeV5` + write `scratchDirectory/session_<id>.muse.feedback`.
- Placeholder WebP, never empty bytes.
- Delete `.raw` / `.computed` / `.metadata` only after the v5 write succeeds.
- Expose `scratchV5Path` (replace `sessionFilePath` pointing at `.raw`).

If assemble fails, log, keep temps, still end the session (dashboard can show load error + Discard). Do not hang.

### Step 3 — Dashboard plots computed; Save publishes

- Live `initState`: read scratch v5 → `v5ExtractComputed` + `v5ParseHead`. No `SessionReader.read`.
- Add `prepareChartDataFromComputed` next to the old preparers (same `_relativeAll` / metric / conditions).
- `RepaintBoundary` on the summary **card** (always built).
- `_encodeThumbnailWebP` / Save: placeholder on empty/invalid; `try/finally` `_busy`.
- Save: rewrite container with captured WebP + final notes/stats; `publishSession` to **history**; delete scratch v5; invalidate `sessionListProvider`.
- Discard: delete scratch v5.
- `publishSession` should accept already-encoded v5 bytes **or** (thumb, metadata, frames, raw) — do not assemble in two different modules.

### Step 4 — History + export

- History route already passes `sessionId` + list metadata. **Re-parse the file** (`readFile` + `v5ParseHead` + `v5ExtractComputed`). List metadata is a skeleton.
- PDF/PNG: `prepareChartDataFromComputed`.
- CSV/EDF: keep `readMuse` + `sessionParseBody` (raw).

### Step 5 — Delete 400-bucket code + docs

- `SessionOverview`, `prepareChartDataFromOverview`, `cacheOverview`, dashboard overview/legacy `fromColumns` stubs.
- `SessionDrowsiness.decimate` / `buckets`; `SessionMusic.decimate` / `buckets`.
- `README_feedback_format.md` §5: replace with “charts from computed 1 Hz; no decimated summary”.
- `AGENTS.md`: remove overview-in-metadata / `session_summary.dart` bullets (that file is already gone).

### Step 6 — Crash recovery

- Scan `scratchDirectory` for `session_*.muse.feedback` and orphan three-temps.
- Temps → same assemble as `end()`.
- Modal Save → `publishSession`; Discard → delete.

### Step 7 — Tests

Need host lib: `cargo build --manifest-path rust/Cargo.toml` then `flutter test …`.

| Test | Assert |
|------|--------|
| Recorder flush → `sessionParseBody` | non-empty bands |
| JSONL → FFI frames → `containerEncodeV5` → `v5ExtractComputed` | `t` ~ 0,1,2; bands round-trip |
| `prepareChartDataFromComputed` | non-empty `x` / alphaRel for 4-ch frames |
| Empty thumbnail assemble | no throw; v5 magic `MUSE5\0` |
| `publishSession` | file in **history** storage, not `.cache`; SQLite row; scratch gone |
| Metadata round-trip | **no** `summary` key; music has `series` not `buckets` |
| Export PNG path | uses computed builder (not empty raw) |

`flutter analyze lib/src` clean. `cargo test --lib session_format` still green.

---

## Do not

- Call `flutter_rust_bridge_codegen generate` unless you change Rust public FFI (you should not).
- Put 400-bucket series back “for the list sparkline” — the WebP thumbnail is the sparkline.
- Plot live graphs from raw EEG.
- Write the final history file from `SessionRecorder.finalize` into `.cache`.
- Scan `getTemporaryDirectory()/sessions` for crash recovery.
- `decodeImage` on empty bytes.
- Reopen pipeline-contract Key Decisions, unlock Crown, edit chart electrode indices.
- Keep three assemblers (`finalize`, `publishSession`, `crash_recovery.saveSession`). One `containerEncodeV5` wrapper.

---

## Suggested commit shape (optional)

One branch is enough. If splitting:

1. `fix(session): frame raw body + session-relative computed t`
2. `feat(session): assemble v5 in scratch at end; charts from computed; publish on save`
3. `refactor(session): drop 400-bucket overview; crash recovery on scratch dir`

---

## Done when

- Session-end dashboard shows time-axis graphs (not “Not enough signal data”).
- Save does not hang; history folder has `session_*.muse.feedback`; `.cache` temps are gone.
- History reopen matches the session-end graphs.
- Spec file’s “Done when” checklist is all true.

If something in the spec fights the code, **follow the spec** and note the drift in the PR/commit message. Do not resurrect `SessionOverview`.
