# Import / Export — EDF · EDF+ · Mind Monitor CSV

| Field | Value |
|---|---|
| Status | **Implemented** — EDF/EDF+ and Mind Monitor CSV → NFED6 `kind: recording` with montage policy A (native / subset / refuse), rubato resampling to 256 Hz, interval CSV = bands only, `import` provenance, import summary + export loss notice; recording CSV/EDF/thumb export |
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
| TAL `duration` for intervals | Crate + FRB + Dart export/import wire `durationSeconds`. | **Done** — interval annotations (pause/bad_quality/disconnect) emit/parse TAL Duration. |
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

## Import policy A

| Case | Result |
|---|---|
| Channels = a supported montage at 256 Hz | Native import (`lossy: false` unless other content is dropped) |
| Supported montage among other channels (e.g. 64-ch 10-10 cap) | Keep only the montage channels, others → `droppedChannels`; `lossy: true` |
| EEG rate ≠ 256 Hz (EDF, MU-01 CSV at 220 Hz) | Resample each contiguous run in Rust (`rubato` FFT resampler, anti-aliased) → `resampled: true`, `lossy: true` |
| No complete supported montage | Refused (`ImportRefused`, "No supported headset montage …"); missing electrodes are never interpolated |

Supported montages (`montage_match.dart`): Muse `TP9 AF7 AF8 TP10` + optional
contiguous `AUX1…AUX4` (checked first), else Crown `CP3 C3 F5 PO3 PO4 F6 C4 CP4`.
Labels match case-insensitively after stripping an `EEG ` prefix and
`-REF`/`-LE`/`-AVG` suffixes; a consistent suffix becomes `import.reference`.

EDF: bands on import always come from our own FFT of the 256 Hz EEG (same
source as live recording); EDF band-named signals next to EEG are dropped.
A band-signal-only EDF imports those bands. EDF+D record gaps → `disconnect`
annotations; raw EEG is placed at the real record times.

Mind Monitor CSV:

| Recording interval | Import |
|---|---|
| **Constant** (median row Δt ≤ 0.25 s) | RAW (+ AUX) at native rate (256, or 220 → resampled); **every** band value kept at native rate in raw band records; computed = per-second mean; IMU/PPG kept. No band columns → bands from our FFT of RAW (warning). |
| **Interval** (0.5 s, 1 s default, … 60 s) | Rows are snapshots → **bands only**: no RAW/AUX/IMU/PPG (warning). Raw band record at each row time; computed frames on the 1 Hz grid at the row times (0.5 s rows averaged per second; > 1 s intervals are sparse). No band columns → refused. `import.recordingInterval` = median Δt between band rows; `import.intervalCoverage` = min(1, 1 s / interval); ≥ 1.9 s → coverage warning in the import dialog. |

AUX columns (`AUX*`, max 4) → `AUX1…AUXn`. Optics (Athena fNIRS) → dropped with
a warning. Elements doubles → annotations; singles/markers skipped (warning).

Stats weight each computed frame by `frameSeconds` (gap to next frame, capped
at the median gap) so sparse interval imports count their real duration.

Provenance: root `import` object (see fileformat_v6 **Import provenance**).
No sqlite column — the export notice reads the file's `import` block; imports
are also identifiable by `device.model == "imported"`.

UI (History): Import… → progress → **summary dialog** ("Import recording?" /
"Import with losses?", Kept vs Lost or changed, Cancel / Import) → publish.
Exporting a lossy import appends a one-line notice ("Imported from … — already
lost on import: …") to the export result.

## Implementation status

| Step | Status |
|---|---|
| Export audit fixes + design | [x] |
| `edf_export` decode + Rust round-trip | [x] |
| FFI `decodeEdfImport` + FRB regen | [x] |
| Dart EDF → NFED6 (recording, placeholder thumb, TAL→locked types) | [x] |
| Mind Monitor CSV interval path (bands only, real row times) | [x] |
| Constant-rate CSV RAW→EEG packets, all band values | [x] |
| Montage policy A (native / subset / refuse) | [x] |
| Resampling to 256 Hz (`rubato`, `rust/src/api/import_dsp.rs`) | [x] |
| `import` provenance + summary dialog + export loss notice | [x] |
| `RecordingStore.publish` wire-up | [x] |
| History **Import…** (`.edf`/`.csv`, progress, snackbar) | [x] |
| IMU/PPG raw streams from CSV columns | [x] Constant only: ACC/Gyro/PPG → raw tags + `streams.imu`/`ppg` |
| Elements → annotations (double blink/jaw) | [x] consecutive within 2 s → `double_*`; singles/markers warn+skip |
| EDF+D discontinuous gaps | [x] timekeeping TAL jumps → `disconnect` annotations (crate); warn if EDF+D with no recoverable gaps |
| TAL duration on export | [x] FRB `durationSeconds` + Dart export/import |
| Computed 1 Hz rebuild from bands on import | [x] per-second mean in linear power (Bel→linear for CSV bands); charts via `extractComputed` |
| Export recordings (CSV / EDF+ / PNG thumb) | [x] PDF/PNG charts stay feedback-only |

## Code map

| Piece | Path |
|---|---|
| Crate decode | `third_party/edf_export` `decode_edf_plus` |
| FFI | `rust/src/api/edf_export.rs` `decode_edf_import` |
| Dart builders | `lib/src/feedback/import/` (`edf_import`, `csv_import`, `montage_match`, `native_eeg`, `import_summary`) |
| Resample / FFT bands FFI | `rust/src/api/import_dsp.rs` (`resample_eeg`, `eeg_second_bands`) |
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
| **Recording interval 0.5 s / 1 s (default) / … 60 s** | One snapshot row per interval; RAW = one sample | Bands only at the real row times; RAW/AUX/IMU/PPG skipped; computed on the 1 Hz grid (0.5 s averaged, longer sparse) |
| **Recording interval = Constant** | Rows at device rate (RAW 256 Hz, 220 Hz on MU-01; bands ~10 Hz) | RAW → EEG packets (220 → 256 resampled); every band value kept; computed = per-second mean |
| **AUX columns** | 1/2/4 by model | → `AUX1…AUXn` channels (Constant only) |
| **Optics** | Athena fNIRS | Dropped with warning |
| **Band columns present** | `Delta|Theta|Alpha|Beta|Gamma_{TP9,…}` in **Bels** | → raw `bands` tags + computed (Bel→linear when values look like Bels) |
| **RAW columns present** | `RAW_{TP9,…}` µV | → raw EEG stream |
| **Accelerometer / Gyro / PPG** | optional columns | Constant: → raw IMU/PPG tags; `streams.imu` / `streams.ppg`. Interval: skipped |
| **Elements** | Blink, Jaw_Clench, markers | Doubles within 2 s → locked types; singles/markers warn+skip |
| **TimeStamp** | `YYYY-MM-DD HH:MM:SS.mmm` (local wall) | → `startedAt`; `timeZone` = capture IANA at import |

**Neurofeed’s own CSV export** is a **subset**: TimeStamp + bands + RAW only, 1 Hz.
It re-imports as a 1 s interval file (bands only).

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

## Still open

- PDF / PNG charts for recordings need a **protocol-free** chart path (reuse
  recording dashboard band charts if desired). Do not invent feedback
  protocol charts for `kind: recording`.
