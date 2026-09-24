# Import / Export — EDF · EDF+ · Mind Monitor CSV

| Field | Value |
|---|---|
| Status | **Implemented (partial)** — EDF+ decode FFI + CSV 1 Hz/Constant → NFED6 + History Import; computed 1 Hz; ACC/Gyro/PPG streams; Elements doubles; recording CSV/EDF/thumb export |
| Branch | `feature/import_export` |
| Related | [../export.md](../export.md), [../contracts/fileformat_v6.md](../contracts/fileformat_v6.md) |
| Out of scope | History UI chrome redesign; nickname→EDF name product toggle; live-device pass |

## Export audit (post fileformat v6) — findings

| Check | Result | Fix |
|---|---|---|
| CSV columns / units / TimeStamp | Columns `TimeStamp`, `Delta_*`…`Gamma_*`, `RAW_*` match Mind Monitor FAQ names. Band units = Muse absolute (Bels). RAW = µV. 1 Hz rows (last EEG sample / sec) ≈ Mind Monitor default interval, not Constant. | Prefer `startedAt` (+ `timeZone`) for TimeStamp wall clock; fall back to `savedAt − elapsedSeconds`. |
| EDF+ patient code = `subject.id` | Was hardcoded `NeuroFeed`. | Pack EDF Local Patient ID `{code} X X X` from `meta.userId` / `subject.id`. Nickname→name deferred. |
| EDF+ startdate/starttime local (FAQ Q17) | `localWallClockFromIso` ignored `timeZone` (`toLocal()` only). | Delegate to `sessionWallClock` (offset digits / `Etc/GMT±N`). |
| Annotations / markers vs v6 | History list summaries omit calibration + `annotations[]`. Exporter used `meta.gestures` (emptied on v6 file read). | Reload file head metadata; emit calibration free-text + root `annotations[].type` as TAL text. Legacy gestures only if annotations empty. |
| TAL `duration` for intervals | Crate encodes/decodes Duration segment when `duration_seconds > 0`. | **Partial** — crate round-trip done; Dart `EdfExportAnnotation` still onset+text only (needs FRB regen to wire `SessionAnnotation.duration`). |
| Annotation channel record size | Was variable-length (non-EDF+). | Fixed: pad to max TAL size; header `nsamples` matches. |
| Signal header layout | Was signal-major 256-byte blocks (non-spec). | Fixed: **field-major** (`ns` labels, then transducers, …). |
| Sample scaling | Near-midpoint ≈ same; now exact EDF linear map. | `phys↔dig` uses `(phys-pmin)/(pmax-pmin)*(dmax-dmin)+dmin`. |
| Session vs recording | Was session-only. | **Done for CSV/EDF+/PNG thumb**; PDF / PNG charts remain feedback-only (protocol charts). |
| Decode API | Started in crate. | **Done:** `decode_edf_plus` + FFI `decodeEdfImport` + Dart NFED6 builder. |

Tests: `test/session_export_test.dart`, `test/timezone_test.dart`,
`test/session_import_test.dart`.

## Import goal

Contract-aligned ingest into **`.neurofeed` (NFED6)** + sqlite row so History
lists the file. Default **`kind: recording`** unless the source proves a
neurofeed feedback protocol (none of EDF / Mind Monitor CSV do).

Do **not** invent `feedback{}` Trust extras, protocol, calibration, or
`outcomeScalars` on import.

## Implementation status

| Step | Status |
|---|---|
| Export audit fixes + design | [x] |
| `edf_export` decode + Rust round-trip | [x] |
| FFI `decodeEdfImport` + FRB regen | [x] |
| Dart EDF → NFED6 (recording, placeholder thumb, TAL→locked types) | [x] |
| Mind Monitor CSV 1 Hz path (neurofeed subset + fuller headers) | [x] |
| Constant-rate CSV RAW→EEG packets | [x] |
| `RecordingStore.publish` wire-up | [x] |
| History **Import…** (`.edf`/`.csv`, progress, snackbar) | [x] |
| IMU/PPG raw streams from CSV columns | [x] ACC/Gyro/PPG → raw tags + `streams.imu`/`ppg` |
| Elements → annotations (double blink/jaw) | [x] consecutive within 2 s → `double_*`; singles/markers warn+skip |
| EDF+D discontinuous gaps | [ ] decode lacks per-record timekeeping jumps; warn on `EDF+D` |
| TAL duration on export | [~] crate yes; Dart FFI still onset+text (FRB regen) |
| Computed 1 Hz rebuild from bands on import | [x] Bel→linear heuristic; charts via `extractComputed` |
| Export recordings (CSV / EDF+ / PNG thumb) | [x] PDF/PNG charts stay feedback-only |

## Code map

| Piece | Path |
|---|---|
| Crate decode | `third_party/edf_export` `decode_edf_plus` |
| FFI | `rust/src/api/edf_export.rs` `decode_edf_import` |
| Dart builders | `lib/src/feedback/import/` |
| Computed rebuild | `lib/src/feedback/import/computed_rebuild.dart` |
| Facade | `lib/src/feedback/session_import.dart` |
| UI | `lib/src/views/feedback_history.dart` Import… / Export |
| Tests | `test/session_import_test.dart` |

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
| **Recording interval ≈ 1 s (default)** | One row / ~s; RAW = one sample that second | **Implemented** — row → 1 Hz bands + 1-sample/s EEG packets + computed |
| **Recording interval = Constant** | Rows at device rate (~256 Hz EEG, 10 Hz bands, …) | **Implemented** — median Δt detect; RAW → 12-sample EEG packets; bands last-of-second + computed |
| **Band columns present** | `Delta|Theta|Alpha|Beta|Gamma_{TP9,…}` in **Bels** | → raw `bands` tags + computed (Bel→linear when values look like Bels) |
| **RAW columns present** | `RAW_{TP9,…}` µV | → raw EEG stream |
| **Accelerometer / Gyro / PPG** | optional columns | → raw IMU/PPG tags; `streams.imu` / `streams.ppg` |
| **Elements** | Blink, Jaw_Clench, markers | Doubles within 2 s → locked types; singles/markers warn+skip |
| **TimeStamp** | `YYYY-MM-DD HH:MM:SS.mmm` (local wall) | → `startedAt`; `timeZone` = capture IANA at import |

**Neurofeed’s own CSV export** is a **subset**: TimeStamp + bands + RAW only, 1 Hz.
Importer accepts that subset and fuller Mind Monitor files.

## Export recordings

History Export sheet:

| Kind | Feedback | Recording |
|---|---|---|
| PDF report | yes | no (protocol charts) |
| PNG charts | yes | no |
| PNG thumbnail | yes | yes |
| CSV (Mind Monitor) | yes | yes |
| EDF+ raw EEG | yes | yes |

No invented `feedback{}` on import. Design matrix + remaining gaps above.
