# Import / Export — EDF · EDF+ · Mind Monitor CSV

| Field | Value |
|---|---|
| Status | **Design** (export audit fixes on `feature/import_export`; import not coded yet) |
| Branch | `feature/import_export` |
| Related | [../export.md](../export.md), [../contracts/fileformat_v6.md](../contracts/fileformat_v6.md) |
| Out of scope | History UI chrome redesign; nickname→EDF name product toggle; live-device pass |

## Export audit (post fileformat v6) — findings

History export remains **feedback sessions only** (recordings: snackbar
`Export is not available for recordings.`). Documented; not a silent break.

| Check | Result | Fix |
|---|---|---|
| CSV columns / units / TimeStamp | Columns `TimeStamp`, `Delta_*`…`Gamma_*`, `RAW_*` match Mind Monitor FAQ names. Band units = Muse absolute (Bels). RAW = µV. 1 Hz rows (last EEG sample / sec) ≈ Mind Monitor default interval, not Constant. | Prefer `startedAt` (+ `timeZone`) for TimeStamp wall clock; fall back to `savedAt − elapsedSeconds`. |
| EDF+ patient code = `subject.id` | Was hardcoded `NeuroFeed`. | Pack EDF Local Patient ID `{code} X X X` from `meta.userId` / `subject.id`. Nickname→name deferred. |
| EDF+ startdate/starttime local (FAQ Q17) | `localWallClockFromIso` ignored `timeZone` (`toLocal()` only). | Delegate to `sessionWallClock` (offset digits / `Etc/GMT±N`). |
| Annotations / markers vs v6 | History list summaries omit calibration + `annotations[]`. Exporter used `meta.gestures` (emptied on v6 file read). | Reload file head metadata; emit calibration free-text + root `annotations[].type` as TAL text. Legacy gestures only if annotations empty. |
| TAL `duration` for intervals | TALs still omit Duration segment. | **TODO** — optional `duration_seconds` on crate + FFI. |
| Annotation channel record size | Was variable-length (non-EDF+). | Fixed: pad to max TAL size; header `nsamples` matches. |
| Signal header layout | Was signal-major 256-byte blocks (non-spec). | Fixed: **field-major** (`ns` labels, then transducers, …). |
| Sample scaling | Near-midpoint ≈ same; now exact EDF linear map. | `phys↔dig` uses `(phys-pmin)/(pmax-pmin)*(dmax-dmin)+dmin`. |
| Session vs recording | Session-only today. | Keep; document in `.ai/export.md`. |
| Decode API | None. | Started: `decode_edf_plus` + encode→decode round-trip test in crate (no FFI/`RecordingStore` yet). |

Tests: `test/session_export_test.dart`, `test/timezone_test.dart`.

## Import goal

Contract-aligned ingest into **`.neurofeed` (NFED6)** + sqlite row so History
lists the file. Default **`kind: recording`** unless the source proves a
neurofeed feedback protocol (none of EDF / Mind Monitor CSV do).

Do **not** invent `feedback{}` Trust extras, protocol, calibration, or
`outcomeScalars` on import.

## Options matrix

### A) Input kinds

| Input | Detect | Typical contents |
|---|---|---|
| **EDF** | ASCII header version `0`, no `EDF+C`/`EDF+D` reserved | Continuous signals only; no Annotations signal |
| **EDF+** | Reserved `EDF+C` or `EDF+D` | EEG (+ others) + `EDF Annotations` TALs |
| **Mind Monitor CSV** | Header starts with `TimeStamp,` + band/RAW/ACC/… columns | See variants below |

### B) Mind Monitor CSV option variants (research)

Sources: [Mind Monitor FAQ — Recorded Data](https://mind-monitor.com/FAQ.php), forums (recording interval / Elements).

| Setting / variant | Effect on file | Import implication |
|---|---|---|
| **Recording interval ≈ 1 s (default)** | One row / ~s; RAW = one sample that second | Map row → 1 Hz bands (+ optional last RAW); reconstruct sparse EEG only |
| **Recording interval = Constant** | Rows at device rate (~256 Hz EEG, 10 Hz bands, 52 Hz IMU, …); empty cells common | Detect by median Δt; RAW columns → raw EEG packets; bands subsample to 1 Hz computed |
| **Band columns present** | `Delta|Theta|Alpha|Beta|Gamma_{TP9,AF7,AF8,TP10}` in **Bels** | → computed `bands` (abs) and/or raw band tags if we re-emit Muse-shaped raw |
| **RAW columns present** | `RAW_{TP9,…}` µV `0…1682.815` | → raw EEG stream (256 Hz if Constant; else 1 sample/s) |
| **Accelerometer / Gyro** | `Accelerometer_{X,Y,Z}`, `Gyro_{X,Y,Z}` | → raw IMU tags when present; else omit stream |
| **PPG / Optics** | `PPG_*`, `Optics*` (device-dependent) | → raw PPG / future optics; omit if absent |
| **HeadBandOn / HSI_*** | Fit / horseshoe quality | → `signalQuality` heuristic on computed; optional `bad_quality` annotations |
| **Battery** | `%/100` | → `stats.battery` bookends |
| **Elements** | `Blink`, `Jaw_Clench`, numbered markers | → `annotations[]` instants (`double_blink` only if we can detect doubles; else skip or map single blink as free type later — **v6 locked types prefer double_***; propose import types `blink` / `jaw_clench` only with format PR, or drop singles) |
| **Delimiter** | Comma (Excel CSV) | Reject TSV unless trivial detect |
| **TimeStamp** | `YYYY-MM-DD HH:MM:SS.mmm` (local wall) | → `startedAt` = first row; `timeZone` = captureIana at import **or** Etc/GMT from device; store ISO with offset |

**Neurofeed’s own CSV export** is a **subset**: TimeStamp + bands + RAW only, 1 Hz.
Importer must accept that subset and fuller Mind Monitor files.

### C) What we can / cannot reconstruct → NFED6

| Target | EDF / EDF+ | Mind Monitor CSV |
|---|---|---|
| Identity (`formatVersion` 6, `appVersion`, `kind: recording`, `savedAt`, `startedAt`, `timeZone`, `durationS`, `elapsedSeconds`) | Yes (start from header; duration from records × record duration) | Yes (first/last TimeStamp) |
| `subject.id` | From patient **code** subfield if not `X`; else new anon id | New anon id (CSV has no subject) |
| `device` / `channelLabels` | From signal labels (EEG channels); model unknown → `"imported"` | Muse 4-ch labels from columns |
| `streams` enablement | Infer from which signals/columns exist | Infer from columns |
| Raw EEG body (framed) | Yes (int16 → µV via dig/phys) | Yes if RAW present |
| Other raw (IMU/PPG/telemetry) | If labeled signals present | If columns present |
| Computed 1 Hz | From EDF band signals if any; else **recompute later** or omit + empty computed | From band columns (resample to 1 Hz); quality from HSI |
| `stats.*` | Assemble from computed when present | Same |
| `annotations[]` | EDF+ TAL text → `type` (map known tokens; unknown → skip or future `note`) | Elements + optional HSI-derived `bad_quality` |
| `feedback{}` / Trust extras | **Never** | **Never** |
| Thumbnail | Placeholder WebP | Placeholder |

**EDF+D** discontinuous: treat as continuous timeline with `disconnect` gaps if timekeeping TALs jump — phase 2.

## Library choices

| Path | Pros | Cons | Decision |
|---|---|---|---|
| Extend `third_party/edf_export` with **read** API | One crate; already owns write layout; path dep | Write-only today; need header/TAL/sample decode | **Prefer** — add `decode_edf_plus` (+ tests golden with our encoder) |
| Add `edf` / `edflib` crate | Mature readers | Extra dep; dual ownership of layout | Fallback if decode scope balloons |
| CSV parse in **Dart** | No FFI; easy column matrix | Large Constant files on UI isolate | **Yes** — worker/`compute`; stream if needed |

FFI surface (later): `decodeEdfImport(bytes) → EdfImportResult` mirroring export params (signals, start, patient, annotations).

## UX placement (propose)

History app bar / overflow next to Export:

- **Import…** → file picker (`.edf`, `.csv`)
- Progress `Importing…`
- On success: write `recording_<id>.neurofeed` via `RecordingStore` publish path (or shared assemble helper), sqlite `kind=recording`, invalidate list
- Snackbar with warnings (e.g. “no RAW columns — bands only”)

No redesign of History chrome beyond one action + picker. Implement UI after reader + round-trip tests.

## Implementation plan (scoped)

1. **Done this turn:** export audit fixes + this design + `.ai/export.md` pointer.
2. **Next:** `edf_export` decode (header + EEG signals + TAL texts) + Rust/Dart round-trip test (`encode → decode`).
3. **Next:** Dart Mind Monitor CSV → NFED6 builder (subset first: TimeStamp+bands+RAW @ 1 Hz = our export dialect) + fixture test.
4. **Then:** wire `RecordingStore` / assemble publish; History Import action.
5. **Later:** Constant-rate CSV; IMU/PPG; EDF+D gaps; TAL duration on export; optional feedback detect (none planned).

## User decisions (non-blocking)

| Topic | Recommendation | Needs user? |
|---|---|---|
| Nickname → EDF name | Keep deferred (name=`X`) | No |
| Import single blink / jaw → annotation type | Drop until format PR adds types, **or** map only doubles if detectable | Decide when Elements import lands |
| Import `timeZone` when CSV has no zone | Use `captureIanaTimeZone()` at import + offset on `startedAt` | OK default |
| Where Import button lives | History overflow / app bar beside Export | Soft — propose overflow |

## Export session-only limit

CSV/EDF/PDF/PNG export APIs take `SessionSummary` feedback metadata
(protocol, calibration). Recordings share NFED6 raw/computed but History
deliberately disables Export for `kind == recording`. Import always creates
recordings; exporting those remains a separate future task (generalize
exporter/channel/annotation export without feedback calibration markers).
