# Export

History overflow → **Export**. Feedback sessions only. Recordings show
`Export is not available for recordings.`

On-screen: **PDF report** · **PNG thumbnail** · **PNG charts** ·
**CSV (Mind Monitor)** · **EDF+ raw EEG**. Spinner `Exporting…`.

Files go to `<save folder>/export/` (`SessionExporter.exportDirName`). On
Android, if History is not SAF-backed, the sheet can pick a folder.

| Kind | What | Source |
|------|------|--------|
| PDF | One vector page per session | Computed 1 Hz charts (`prepareChartDataFromComputed`) |
| PNG thumbnail | The WebP already in the `.neurofeed` file | Container head |
| PNG charts | Thumbnail + each dashboard chart | Same painters as PDF |
| CSV | 1 Hz `TimeStamp`, `Delta_TP9`…, `RAW_TP9`… | Raw body; timestamps ms epoch ÷ 1000 |
| EDF+ | Raw EEG + calibration/gesture markers | `encodeEdfExport` |

Code: `lib/src/feedback/session_export.dart`,
`session_pdf_export.dart`. UI: `feedback_history.dart`. Tests:
`test/session_export_test.dart`.

`third_party/edf_export` is still a path dep — publish to git+tag after a
real-device pass.

## Session-only

Export is **feedback sessions only**. Recordings show
`Export is not available for recordings.` CSV/EDF read raw EEG from the
NFED6 body; markers/calibration come from feedback metadata. Do not
silently run the same path on recordings without a dedicated pass.

## EDF+ / CSV vs fileformat v6

- EDF patient field = `{subject.id} X X X` (anonymous; nickname→name deferred).
- EDF startdate/starttime = site-local from `startedAt` + `timeZone` (FAQ Q17).
- EDF annotations = calibration free-text + root `annotations[].type` (v6 SoT).
- CSV TimeStamp prefers `startedAt` wall clock.

## Import

Design + options matrix: [TODO/import-export.md](TODO/import-export.md).
Import lands as `kind: recording` NFED6 + sqlite; not implemented yet.
