# Export

History overflow → **Export**.

On-screen: **PDF report** · **PNG thumbnail** · **PNG charts** ·
**CSV (Mind Monitor)** · **EDF+ raw EEG**. Spinner `Exporting…`.

Files go to `<save folder>/export/` (`SessionExporter.exportDirName`). On
Android, if History is not SAF-backed, the sheet can pick a folder.

| Kind | Feedback | Recording | Source |
|------|----------|-----------|--------|
| PDF | yes | no | Computed 1 Hz charts (`prepareChartDataFromComputed`); needs protocol |
| PNG thumbnail | yes | yes | WebP already in the `.neurofeed` file |
| PNG charts | yes | no | Same painters as PDF (protocol charts) |
| CSV | yes | yes | Raw body; timestamps from `startedAt` |
| EDF+ | yes | yes | Raw EEG + annotations when present |

Code: `lib/src/feedback/session_export.dart`,
`session_pdf_export.dart`. UI: `feedback_history.dart`. Tests:
`test/session_export_test.dart`.

`third_party/edf_export` is still a path dep — publish to git+tag after a
real-device pass.

## Session vs recording

CSV / EDF+ / PNG thumbnail work for both `kind: feedback` and
`kind: recording`. PDF and PNG charts stay **feedback-session only**
(they need a protocol document for metric/condition series). The Export
sheet hides those options when the selection is recordings-only and notes
the limit when mixed.

## EDF+ / CSV vs fileformat v6

- EDF patient field = `{subject.id} X X X` (anonymous; nickname→name deferred).
- EDF startdate/starttime = site-local from `startedAt` + `timeZone` (FAQ Q17).
- EDF annotations = calibration free-text + root `annotations[].type` (v6 SoT).
- TAL Duration segment is written by the crate when `duration_seconds > 0`;
  Dart FFI still passes onset+text only until FRB regen exposes duration.
- CSV TimeStamp prefers `startedAt` wall clock.

## Import

**Implemented (partial).** History app bar **Import…** (next to Refresh)
picks `.edf` / `.csv` → NFED6 `kind: recording` + `RecordingStore.publish`
(sqlite lists it). Progress dialog + snackbar warnings.

| Input | Behaviour |
|-------|-----------|
| EDF / EDF+ | `decodeEdfImport` → raw EEG packets; optional band-named signals → tags + computed; patient code → `subject.id` when not `X`; TALs mapped to locked annotation types when possible; placeholder thumb; `EDF+D` warns (disconnect gaps not mapped yet) |
| Mind Monitor / neurofeed CSV | 1 Hz + Constant; bands → tags + computed 1 Hz; RAW → EEG; ACC/Gyro/PPG → raw streams; Elements doubles → annotations |

No invented `feedback{}`. Design matrix + remaining gaps:
[TODO/import-export.md](TODO/import-export.md).

Code: `lib/src/feedback/session_import.dart`, `lib/src/feedback/import/`.
Tests: `test/session_import_test.dart`.
