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
| PNG thumbnail | The WebP already in the v5 file | Container head |
| PNG charts | Thumbnail + each dashboard chart | Same painters as PDF |
| CSV | 1 Hz `TimeStamp`, `Delta_TP9`…, `RAW_TP9`… | Raw `.muse` body; timestamps ms epoch ÷ 1000 |
| EDF+ | Raw EEG + calibration/gesture markers | `encodeEdfExport` |

Code: `lib/src/feedback/session_export.dart`,
`session_pdf_export.dart`. UI: `feedback_history.dart`. Tests:
`test/session_export_test.dart`.

`third_party/edf_export` is still a path dep — publish to git+tag after a
real-device pass.
