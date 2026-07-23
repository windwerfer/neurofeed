# Graph + Recording — decisions & todo

## Decisions

| Date | Decision |
|------|----------|
| 2026-07-23 | Kill ticker → `ChangeNotifier` on data source, repaint on data arrival only |
| 2026-07-23 | Storage: pre-alloc `Float64List` ring buffer (configurable cap, no grow logic) |
| 2026-07-23 | Decouple recording from display — `SessionRecorder` and `LiveCache` are independent consumers of the event stream |
| 2026-07-23 | Recording always-on to temp file; explicit Record → rename to timestamped keep |
| 2026-07-23 | Recording in Dart (not Rust) — I/O is light, no new FFI surface needed |
| 2026-07-23 | Binary dump first, transform later (EDF/CSV/Mind Monitor) — one append-only write path in hot loop |
| 2026-07-23 | Temp file created on connect, cleaned on next app start |
| 2026-07-23 | On app background (Android): recording continues — foreground service needed (Phase 2) |
| 2026-07-23 | Live cache: 5 min ring buffer (~20 MB for 4ch @ 256 Hz) |
| 2026-07-23 | FFT in Rust (next to the EEG decoder), emit `Bands` event at 1 Hz — separate from raw EEG |
| 2026-07-23 | `EegDataSource` abstract interface — chart widget is source-agnostic (live or replay) |

## Phase 1 — Data architecture (current)

- [x] Kill ticker, switch to ChangeNotifier
- [x] Float64List ring buffer (pre-alloc, no grow)
- [x] Flexible channel support (CH{n} beyond TP9/AF7/AF8/TP10)
- [ ] Create `EegDataSource` abstract class
- [ ] Create `LiveCache` (5 min ring, implements EegDataSource)
- [ ] Create `SessionRecorder` (binary dump writer)
- [ ] Create `DiskSession` stub (file-backed replay, same interface)
- [ ] Wire into `AppStateNotifier`: replace `eegBuffer` with `liveCache` + `sessionRecorder`
- [ ] Remove old `eeg_data_buffer.dart`
- [ ] Painter: decouple from buffer, source only

## Phase 2 — Android foreground service

- [ ] Kotlin ForegroundService with `muse_connected` notification
- [ ] Process alive while Muse connected
- [ ] No changes to Dart recording code

## Phase 3 — Export & replay

- [ ] EDF export transform
- [ ] Mind Monitor CSV import
- [ ] `DiskSession` full implementation (sparse index, binary seek, replay)
- [ ] Session browser UI

## Phase 4 — FFT & bands

- [ ] FFT in Rust (rustfft crate or custom)
- [ ] Emit `Bands` DTO at 1 Hz
- [ ] `BandsView` UI
