# Handoff — live monitor graphs + connect-time recording

| Field | Value |
|---|---|
| Date | 2026-09-13 |
| Status | **Series complete.** Archived. Do not start a new monitor PR from this file. |
| Spec | [../monitor.md](../monitor.md) — **frozen** rev **6**. Bands Y is **dB display**. **PR 8 cancelled** (2026-09-13): Spectrogram stays 1 s / 256-pt; no `FFT 1s ▾`. |
| Branch | `refactor/monitor` (PR 0 `22cfd38` … PR 7 `b197709`). |
| Do not mix | Crown Start, OSC-connect, pipeline-contract Key Decisions, v5 68-byte header / FRB, Android foreground service, Athena optics, growing status-bar pads to 8. |

PRs **0–7 landed**. **PR 8 was cancelled** — FFT-window chrome is not a normal-user control; default 256-pt Hamming is enough. No averaging. PSD Welch stays 1 s / 256-pt.

**Follow-up (post PR 7, same branch):** Bands 1 Hz display — PCHIP strokes, Follow vsync + ~1 s lead (`ViewportController.bandsFollowLeadSeconds`), in-pane `BandToggles` (depressed = visible, last-one-stays). Histogram/PSD strip gets the same Follow slide; its legend stays painted / non-interactive. Spectrogram Follow stays flush-right (`followLeadSeconds = 0`). Inspect freezes the displayed window and may still rebuild at 1 Hz; no ticker. Do not restore `main`’s `SMOOTH` / `REAL TIME` chrome. Live spec: [../monitor.md](../monitor.md).

---

## Landed

| PR | Commit / note |
|---|---|
| **0** | `22cfd38` — `lib/src/session_v5/` (writer, assemble, ComputedFrame, models). Prefix default `session`. Thin re-exports at old paths. |
| **1a** | `2a66eae` — `MonitorController` in `main()` after `appStateProvider.notifier`. Band ring in `monitor/cache/band_cache.dart` (1800). `bandNames`/`bandColors` in `charts/band_style.dart`. Pad quality is a 4-ch **1 s** ring. |
| **1b** | `8a0b9f0` — Exclusive `tmp_` writer + exclusive lease. Connect starts `tmp_$ts.{raw,computed,json}` with `Settings.recordStreams`. Feedback `acquireFeedbackLease` discards tmp; `end()` releases only if `!isRecording`. Launch glob-deletes leftover `tmp_*`. `GET /state` has `captureKind` / `captureElapsedSeconds`. |
| **1c** | `3fb276b` — `RecordingIndex` + `FileBackedSource` under `monitor/cache/`. `flushRaw` callback indexes `(elapsedT, fileLength)` at frame boundaries. `getRange` prepends `sessionHeaderBytes()` then `sessionParseBody`; timestamps are elapsed from `captureStartedAtMs`. tmp rotate clears the index. |
| **2** | `a9717bb` — GraphShell + N stacked sweep EEG panes. `SweepBuffer` on `MonitorController` (`monitor/cache/`). Default 10 s / 2560. Muse-4 vs Crown-8. Follow wipe; Inspect HOLD + fill-right; beyond 5 min calls `FileBackedSource`. Record hidden. Deleted add/remove, `graph_config`, `eeg_chart`, `eeg_dashboard`, `live_cache`, old Raw EEG views. |
| **3 ASCII** | `8e45d37` — Spec rev 5. Bands Y **dB** display; pinch-X **`custom`**; overshoot dashed hold (strippable). |
| **3** | `878cc8a` — Bands on GraphShell. One `TimeSeriesPane`, five series, mean of selected in dB. Electrode toggles (all on, last-one stays). Default 30 s; pinch-X → `custom`. Overshoot hold isolated in `overshoot_hold.dart`. Old `views/bands.dart` + `chart_controller.dart` deleted. Record hidden. |
| **4 ASCII** | `4c968fa` — Spec rev 6. Landscape cinema; spectrogram `mag ▾` color; Histogram/PSD one pane + tap readout; PR 7 Bands context strip; PR 8 Spectrogram FFT 0.5/1/2 s. |
| **4** | `c3a40f5` — Histogram + PSD + Spectrogram painters. `AppView.histogram`. Landscape cinema. `dsp.dart` Hamming `1/N²`, `n` parameterized. Record still hidden. |
| **5a** | `4fc83ec` — Record / Stop / assemble / 409 `recording_active`. |
| **5b** | `d4afac0` — Crash recovery for `recording_*` + sqlite `kind`. |
| **6** | `5195eca` — Unified History + All/Feedback/Recordings filter + Save files to folder. |
| **7** | `b197709` — Bands context strip under Histogram and PSD. |
| **8** | **cancelled** 2026-09-13 — no Spectrogram `FFT 1s ▾`. Stays `kDefaultFftN = 256`. |

### PR 7 shipped

- Histogram and PSD: `HistogramPsdSplit` flex **7 / 3** (~70% / ~30%). Constants `kHistogramPsdPrimaryFlex` / `kBandsContextStripFlex` — not a user setting.
- Bottom pane is `BandsContextStrip`: same `TimeSeriesPane` as sidebar Bands + time-only highlight. Highlight width = GraphShell T (2 / 4 / 8 s). Follow = flush-right (last T of the strip).
- Strip window default **30 s**; pinch-X like Bands (`custom`); compact `30s ▾` on the strip (not a second GraphShell dropdown). Landscape hides that dropdown; both panes stay.
- One electrode-toggle set drives histogram/PSD mean **and** strip mean. Histogram/PSD painters unchanged.
- Spectrogram: no strip. Standalone Bands unchanged. Recording-dashboard Histogram/PSD stay one pane.

---

## Series map (do not collapse)

| PR | Thread title | ASCII? | Depends |
|---|---|---|---|
| **0** | Extract `lib/src/session_v5/` | no | — |
| **1a** | `MonitorController` in `main()` + band cache; no disk | no | 0 |
| **1b** | `tmp_` writer + exclusive lease (kills dual `session_` writers) | no | 1a |
| **1c** | File-backed Inspect of tmp/recording `.raw` | no | 1b |
| **2** | GraphShell + N stacked **sweep** EEG panes; cancel add/remove | **yes** (landed) | 1b; prefer 1c first |
| **3** | Bands on GraphShell + electrode toggles | **yes** (landed) | 2 |
| **4** | Histogram + PSD + Spectrogram (`AppView.histogram` only) | **yes** (landed) | 2; ∥ 3 |
| **5a** | Record / Stop / assemble / 409 `recording_active` | no — landed | 1b, 2 |
| **5b** | Crash recovery + `publish` into `session_metadata.db` (`kind`) | no — landed | 5a |
| **6** | Unified History list + filter + Save files to folder | no — landed | 5b |
| **7** | Bands context strip (~30%) under Histogram and PSD | **yes** — landed | 4, 6 |
| **8** | Spectrogram `FFT 1s ▾` 0.5 / 1 / 2 s (128 / 256 / 512) | — | **cancelled** |

Copy changes update `.ai/ui-map.md` in the same PR.

---

## Current code (after PR 7)

| Piece | Where | After 7 |
|---|---|---|
| Connect writer | `MonitorController` + `MonitorRecorder` | `tmp_$ts` on connect; **Record** starts `recording_$ts.{raw,computed,json}`. |
| Index | `monitor/cache/recording_index.dart` | Same `RecordingIndex` on tmp and recording `flushRaw`. Rotate (tmp only) clears. |
| Assemble | `MonitorRecorder.assemble` → `writeScratchV5(prefix: recording)` | Placeholder WebP. Never assemble tmp. |
| Save/Discard | `monitor/views/recording_save_discard.dart` | Title param. Live Save → `RecordingStore.publish`. Crash recovery title `Incomplete recording detected`. `RecordingSaveHost` on `AppShell`. |
| GraphShell | `monitor/graph_shell.dart` | `showRecord: true` on five live views. `followEnabled: false` on recording dashboard. Landscape hides toolbar. |
| Histogram / PSD | `monitor/views/{histogram,psd}_view.dart` | `HistogramPsdSplit` 7/3 + `BandsContextStrip`. GraphShell `2s/4s/8s` is T. Strip default 30 s. |
| Bands strip | `monitor/panes/bands_context_strip.dart` | Reuses `TimeSeriesPane`. Highlight overlay is time only. Compact `30s ▾` / `custom`. |
| Spectrogram | `monitor/views/spectrogram_view.dart` | One pane. `mag ▾`. FFT **256-pt** (`kDefaultFftN`). No FFT-window chrome (PR 8 cancelled). |
| CaptureLease | `monitor/recording/capture_lease.dart` | idle/tmp/recording/feedback. tmp→recording, recording→idle. Feedback refuses recording. |
| Agent | `agent_commands.dart` | `/record/start\|stop`; `_start` 412 `not_connected` → 409 `crown_refused` → 409 `recording_active`. |
| Feedback Start | `feedback_session.dart` | `_refuseCrownStart` then `_refuseRecordingStart`. |
| Crash recovery | `monitor/recording/crash_recovery.dart` | `recording_*` scan + assemble temps. Launch after feedback dialog + tmp glob. |
| RecordingStore | `monitor/recording/recording_store.dart` | publish = history-root file + sqlite `kind=recording`. Discard deletes scratch. |
| Sqlite | `feedback/session_sqlite.dart` | `kind TEXT NOT NULL DEFAULT 'feedback'`. |
| History list | `views/feedback_history.dart` | On-screen **History**. Filter All \| Feedback \| Recordings. Open by `kind`. |
| Recording dashboard | `monitor/views/recording_dashboard.dart` | Follow disabled. Inspect `v5ExtractRaw`. Histogram/PSD still one pane (no strip). |
| SessionStore | `feedback/session_store_core.dart` | List carries `kind`/`path`. Read/delete by sqlite `path`. `moveAllTo` both prefixes. sqlite-only list. |
| Folder change | `views/settings_view.dart` | Card **Save files to folder**. Dialog counts both prefixes. `sessionListProvider` invalidated from `_applyFolder` and `_resetFolder`. |

---

## PR 8 — cancelled (2026-09-13)

No Spectrogram `FFT 1s ▾`. `dsp.dart` stays parameterized (`n` power-of-two) but live and recording-dashboard spectrograms call **`kDefaultFftN = 256`** (1 s). PSD Welch stays 1 s / 256-pt. No averaging. Do not add this control later without a spec amendment.

---

## Isolation (every thread)

**Monitor may import:** `rust/api/{muse,session_format,device_config}.dart`, `connection_provider.dart` (status / `eventStream` / `lastConnectedKind`), `settings.dart`, `session_v5/`, `charts/{smooth_path,band_style}.dart`, `version.dart`, `feedback/session_storage.dart`, `feedback/session_sqlite.dart` (`RecordingStore.publish` upserts `kind`).

**Monitor must not import:** `feedback_state.dart`, lanes, protocol, `session_store*.dart`, feedback `crash_recovery.dart`.

**Feedback must not import `lib/src/monitor/`** except the lease API (`acquireFeedbackLease` / `releaseFeedbackLease`, PR 1b). `buildSessionMetadata` uses `DeviceConfig.forKind` → `electrodeNames`, **not** `device_montage.dart`. `_refuseRecordingStart` in `views/feedback_session.dart` is the other allowed edge (PR 5a). History list may import `monitor/views/recording_dashboard.dart` (PR 6).

History list stays `lib/src/views/feedback_history.dart`. Recording dashboard / Save-Discard live under `monitor/views/`.

---

## Pitfalls (as shipped)

- **No averaging.** Rejected; PR 8 FFT-window chrome was the alternative and is also cancelled. Visual PCHIP + Follow lead is display-only (not DSP averaging).
- **Do not restore `SMOOTH` / `REAL TIME` Bands chrome.** Always-on PCHIP; Follow lead is 1 s with no toggle.
- **Spectrogram `followLeadSeconds` stays 0.** Only 1 Hz Bands strips set `bandsFollowLeadSeconds`.
- **PSD Welch stays 1 s / 256-pt.** Spectrogram uses the same default `n = 256`.
- **Do not add a Bands strip to Spectrogram.**
- **Do not fork Bands view.** Histogram/PSD strip already reuses `TimeSeriesPane`.
- **v1 History list is sqlite-only** (landed PR 6). Do not add a directory backfill of `recording_*` without a row.
- **`SessionStore` read/delete use sqlite `path`.** Recordings are `recording_$id.muse.feedback`.
- **No `AppView.recordings`.** Enum stays `feedbackHistory`; on-screen **History**.
- Agent HTTP: `persist: false`. Crown 409 stays `crown_refused`.

Do not edit pipeline-contract or connect-simulator-ux.
