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
- TAL Duration segment is written when `durationSeconds > 0` (interval
  annotations); instants omit Duration. Import restores `SessionAnnotation.duration`.
- Every data record starts with a timekeeping TAL `+<start>\x14\x14\x00`;
  annotation onsets are absolute seconds from the file start.
- EDF+D timekeeping jumps decode to `disconnect` annotations; raw EEG is
  placed at each record's start (gaps stay gaps).
- CSV TimeStamp prefers `startedAt` wall clock.
- Exporting a recording whose `import.lossy` is true adds a one-line notice
  to the result ("Imported from … — already lost on import: …").

## Import

History app bar **Import…** (next to Refresh) picks `.edf` / `.csv` →
`importFile` (convert only) → summary dialog (Kept / Lost or changed,
Cancel / Import) → NFED6 `kind: recording` + `RecordingStore.publish`.
Every import carries the root `import` provenance object.

| Input | Behaviour |
|-------|-----------|
| EDF / EDF+ | Montage policy A: Muse 4 (+AUX) or Crown 8 kept, other channels dropped, no complete montage → refused; EEG resampled to 256 Hz (`rubato`); bands from our FFT; patient code → `subject.id` when not `X`; TALs (with duration) → locked annotation types; EDF+D gaps → `disconnect`; placeholder thumb |
| Mind Monitor / neurofeed CSV | Same montage rule. Constant: RAW (+AUX) at 256 Hz (220 Hz resampled), every band value, IMU/PPG. Interval (0.5–60 s): bands only at the real row times. Optics dropped; Elements doubles → annotations |

No invented `feedback{}`. Design matrix + remaining gaps:
[TODO/import-export.md](TODO/import-export.md).

Code: `lib/src/feedback/session_import.dart`, `lib/src/feedback/import/`.
Tests: `test/session_import_test.dart`.
