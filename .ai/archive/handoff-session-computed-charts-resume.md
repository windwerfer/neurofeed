# Handoff — session charts from v5 computed 1 Hz (resume)

| Field | Value |
|---|---|
| Date | 2026-09-02 |
| Spec | [`.ai/feedback/session-computed-charts.md`](session-computed-charts.md) — **frozen**. Do not reopen Key Decisions. |
| Branch | `feat/session-computed-charts` (off `refactor/eeg_feature_implementation`) |
| Last commit | `da4e119` `feat(session): assemble scratch v5 at end; charts from computed 1 Hz` |
| Status | **Steps 1–7 implemented.** Device/desktop `flutter run` still not done. |
| Do not mix | Crown Start, v5 byte layout, FRB regen, pipeline-contract Key Decisions |

Read the spec first. Then this file. Then implement remaining steps in order.

---

## Done (steps 1–4)

Computed 1 Hz is the summary waveform. At `end()`, a real v5 file is assembled in **scratch** (placeholder WebP) **before** `phase = ended`. Dashboard and history both call `v5ExtractComputed` → `prepareChartDataFromComputed`. Save publishes that file to the history folder.

| Step | What landed |
|------|-------------|
| 1 | `SessionRecorder.flushRaw` wraps pending records with `sessionFrameBytes`. `ComputedSampler.t` is seconds from recording start (injectable clock + `emitFrame()` for tests). |
| 2 | `FeedbackStateNotifier.end()` flushes, builds metadata **without** `summary` / drowsiness series / music buckets, `assembleScratchV5` via one `assembleV5Container` wrapper, deletes temps only on success, then sets `ended`. Failure logs and keeps temps. |
| 3 | Live dashboard reads scratch v5 (`v5ExtractComputed` + `v5ParseHead`). `RepaintBoundary` is on the summary **card**. Save rewrites container (captured WebP or placeholder) and `publishSession(..., encodedV5:)`. `_save` / `_discard` `try/finally` `_busy`. Discard deletes scratch v5. |
| 4 | History re-parses the file (`SessionStore.readContainer`). PDF/PNG use `prepareChartDataFromComputed`. CSV/EDF still `readMuse` + `sessionParseBody`. |

One assembler: `lib/src/feedback/session_assembler.dart` (`assembleV5Container`, `toFfiFrame`, `parseComputedJsonl`, `encodeThumbnailWebP`, `placeholderWebP`, `extractComputedScalars`).

### Tests green (host lib rebuilt)

`cargo build --manifest-path rust/Cargo.toml` then:

- `test/session_computed_charts_test.dart` — framed parse, sampler `t`, JSONL→FFI round-trip, `prepareChartDataFromComputed`, empty-thumb `MUSE5\0`, publish to history not `.cache`
- `test/session_store_test.dart`, `test/session_metadata_roundtrip_test.dart`, `test/session_export_test.dart`

`flutter analyze lib/src` — only pre-existing `deprecated_member_use` in `connect_window.dart`.

### Not verified on device

Handoff originally asked to stop after step 3 and check `flutter run -d linux` (graphs + Save). That was **not** done. Next thread should still do it when convenient; do not block step 5 on it.

---

## Frozen decisions (repeat — do not reopen)

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
| One `containerEncodeV5` wrapper | `lib/src/feedback/session_assembler.dart` |
| Framed raw + temps only (no finalize-to-cache) | `lib/src/charts/session_recorder.dart` |
| `assembleScratchV5` / `scratchV5Path` / `deleteScratchV5` | `lib/src/feedback/feedback_recorder.dart` |
| `end()` assemble **then** `phase = ended` | `lib/src/feedback/feedback_state.dart` |
| Sampler `t` | `lib/src/feedback/computed_sampler.dart` |
| `prepareChartDataFromComputed` (overview builder deleted) | `lib/src/feedback/session_chart_data.dart` |
| Live + history load from v5; Save publishes | `lib/src/views/feedback_dashboard.dart` |
| `publishSession(id, metadata, {encodedV5, rawBody, thumbnail, computedFrames})` | `lib/src/feedback/session_store_core.dart` |
| `readContainer` | same |
| PNG/PDF computed; CSV/EDF raw | `session_export.dart` / `session_pdf_export.dart` |
| Drowsiness scalars only; music `tracks` + `series` | `session_metadata.dart` |
| Crash recovery (scratch dir, `writeScratchV5`, placeholder WebP) | `lib/src/feedback/crash_recovery.dart` |
| Charts from computed 1 Hz | `README_feedback_format.md` §5 |
| Charts hot spot | `AGENTS.md` |

`sessionParseBody` / framed goldens: `rust/src/api/session_format.rs`. Do not change the wire layout. Do not run FRB codegen.

---

## Remaining work

Steps 5–7 are implemented. Still open: device/desktop `flutter run -d linux`
— session-end graphs + Save to history folder, not `.cache`.

### Step 5 — Delete 400-bucket code + docs (done)

- Remove `SessionOverview`, `BandPowerSeries`, `prepareChartDataFromOverview`, dashboard leftover overview types if any, `fromColumns`.
- Remove `SessionDrowsiness.decimate` / `buckets` / `bucketWidthSecs` (and `series` if unused). Keep scalars. `fromJson` may ignore leftover keys.
- Remove `SessionMusic.decimate` / `buckets` / `bucketWidthSecs`. Keep `tracks` + `series`.
- Dashboard music widgets still have a `buckets.isNotEmpty` branch — delete it, plot `series` only.
- `README_feedback_format.md` §5: replace with “charts from computed 1 Hz; no decimated summary”.
- `AGENTS.md`: drop the “Next charts spec will drop SessionOverview…” bullet; state computed 1 Hz is how charts work.

### Step 6 — Crash recovery (done)

- Scan `scratchDirectory(storage)` for leftover `session_*.muse.feedback` **and** orphan three-temps (`.raw` / `.computed` / `.metadata`).
- Temps → same `assembleScratchV5` / `assembleV5Container` as `end()`.
- Assembled scratch v5 → modal Save → `publishSession`; Discard → delete.
- Use `placeholderWebP`, never empty bytes. Reuse `toFfiFrame` from the assembler; delete the copy in `crash_recovery.dart`.
- Do **not** scan `getTemporaryDirectory()/sessions`.

### Step 7 — Tests leftover (done; device run still open)

Most of the table in the original handoff already has coverage in `test/session_computed_charts_test.dart`. Still add/adjust as you delete 400-bucket code:

| Test | Assert |
|------|--------|
| Metadata round-trip | already: **no** `summary` key; music `series` not `buckets` — keep green after field deletion |
| Crash recovery | scans scratch dir; temps assemble; discard deletes |
| Export PNG path | already uses computed builder |

`flutter analyze lib/src` clean. `cargo test --lib session_format` still green.

Device/desktop: `flutter run -d linux` — session-end graphs + Save to history folder, not `.cache`.

---

## Do not

- Call `flutter_rust_bridge_codegen generate` unless you change Rust public FFI (you should not).
- Put 400-bucket series back “for the list sparkline” — the WebP thumbnail is the sparkline.
- Plot live graphs from raw EEG.
- Write the final history file from the recorder into `.cache`.
- Scan `getTemporaryDirectory()/sessions` for crash recovery.
- `decodeImage` on empty bytes.
- Reopen pipeline-contract Key Decisions, unlock Crown, edit chart electrode indices.
- Keep a third assembler in crash recovery. One `assembleV5Container`.

---

## Done when (whole spec)

- Post-session dashboard shows time-axis graphs from computed (not “Not enough signal data”).
- Save does not hang; history folder has `session_*.muse.feedback`; `.cache` temps/v5 are gone.
- History reopen matches the session-end graphs.
- PDF/PNG charts match the dashboard builder.
- No `summary` key, no 400-bucket fields, no `decodeImage` on empty bytes.
- Crash recovery finds leftover scratch v5 / three-temps.
- Spec file’s “Done when” checklist is all true.

If something in the spec fights the code, **follow the spec**. Do not resurrect `SessionOverview`.
