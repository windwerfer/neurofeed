# Project docs

Index for agents and humans. Start at [AGENTS.md](../AGENTS.md) for pins and
do/don't, then this folder for maps.

## Live

| File | Contents |
|------|----------|
| [contracts/](contracts/) | **Frozen contracts** (pipeline, data-plane, fileformat v6). What must stay true. |
| [active-task.md](active-task.md) | Current development focus |
| [audio-engine.md](audio-engine.md) | **Implemented** SoLoud engine hardening (lifetime, loads, leftover muffle) |
| [connect-simulator-ux.md](connect-simulator-ux.md) | **Frozen** connect UX: Muse / Neurosity / Simulator + `DeviceKind` Muse\|Neurosity |
| [architecture.md](architecture.md) | Stack: BLE, devices, feature pipeline, session, monitor, audio, streaming, export |
| [testing-guide.md](testing-guide.md) | Build/test loop, FFI tests, Linux agent HTTP, `flutter run` loader trap |
| [ui-map.md](ui-map.md) | Spoken UI names → widgets/files |
| [test-matrix.md](test-matrix.md) | What can be tested, how, what cannot |
| [release.md](release.md) | Release CI, keystore, F-Droid, reproducibility |
| [btleplug.md](btleplug.md) | btleplug fork (`0.12.0-muse-5`) — JNI attach + notification death spiral |
| [muse-rs.md](muse-rs.md) | muse-rs `0.1.1` patch, Classic vs Athena, battery, Athena optical/fNIRS gap |
| [monitor.md](monitor.md) | **Implemented.** Live graphs + connect-time recording. Cinema: mobile landscape / desktop F11. Bands: PCHIP, 1 s Follow lead, in-pane chips. Draw-path perf PRs 1–7 landed; PR 8 skipped. |
| [trust-graphs.md](trust-graphs.md) | **Implemented.** Session Reward / Guard / More chips + Follow-only graphs. Inhibit 0–2 panes under Reward; Guard 1–2 panes from distinct warn signals. |
| [headset-fit.md](headset-fit.md) | Pad colors, Classic vs Athena, status-bar dots |
| [export.md](export.md) | History export: PDF / PNG / CSV / EDF+ |

## Contracts

Landed freezes. Agents read these for what must stay true, not how the
series was implemented. Queued specs stay under [TODO/](TODO/) until they
land (Athena optics keeps its implementer detail there).

| File | Contents |
|------|----------|
| [contracts/pipeline-contract.md](contracts/pipeline-contract.md) | **Implemented.** Features, protocols, lanes. Crown Start refused. Do not reopen Key Decisions. |
| [contracts/data-plane-contract.md](contracts/data-plane-contract.md) | **Implemented.** Capture fork, inner zstd, assemble, soak, Android FGS. D1–D3 frozen. Do not re-run [`archive/handoff-spine.md`](archive/handoff-spine.md). |
| [contracts/fileformat_v6.md](contracts/fileformat_v6.md) | **Implemented / LOCKED.** `.neurofeed` v6 (NFED6). Human spec: [../README_feedback_format.md](../README_feedback_format.md) (update it if the contract changes). Historical v5: [archive/session-format-contract-v5.md](archive/session-format-contract-v5.md). |

## Feedback

| File | Contents |
|------|----------|
| [feedback/architecture.md](feedback/architecture.md) | Lanes, protocol documents, calibration as implemented |
| [feedback/todos.md](feedback/todos.md) | Checklist |

Format / cache / export (repo root + here):
[README_feedback_format.md](../README_feedback_format.md),
[README_history_cache.md](../README_history_cache.md),
[export.md](export.md).

## Queued

Not the active branch. Do not mix into connect-simulator-ux or
pipeline-contract work.

| File | Contents |
|------|----------|
| [TODO/README.md](TODO/README.md) | Index |
| [TODO/athena-optics-contract.md](TODO/athena-optics-contract.md) | Athena optical raw stream (muse-rs `Optics`, session tag 11) |
| [TODO/handoff-athena-optics.md](TODO/handoff-athena-optics.md) | Implementer order, files, LOC |
| [TODO/history-dashboard-unification.md](TODO/history-dashboard-unification.md) | History chips + Feedback overview (locked design) |
| [TODO/handoff-history-dashboard.md](TODO/handoff-history-dashboard.md) | PR manager: sequential subagents, one commit per PR |
| [TODO/github actions appimage.md](TODO/github%20actions%20appimage.md) | GitHub Actions AppImage packaging |

## Archive

Finished work and history live in [archive/](archive/). Do not treat those
files as current orientation.
