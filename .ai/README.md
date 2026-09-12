# Project docs

Index for agents and humans. Start at [AGENTS.md](../AGENTS.md) for pins and
do/don't, then this folder for maps.

## Live

| File | Contents |
|------|----------|
| [active-task.md](active-task.md) | Current development focus |
| [audio-engine.md](audio-engine.md) | **Implemented** SoLoud engine hardening (lifetime, loads, leftover muffle) |
| [connect-simulator-ux.md](connect-simulator-ux.md) | **Frozen** connect UX: Muse / Neurosity / Simulator + `DeviceKind` Muse\|Neurosity |
| [architecture.md](architecture.md) | Stack: BLE, devices, feature pipeline, session, audio, streaming, export |
| [testing-guide.md](testing-guide.md) | Build/test loop, FFI tests, Linux agent HTTP, `flutter run` loader trap |
| [ui-map.md](ui-map.md) | Spoken UI names → widgets/files |
| [test-matrix.md](test-matrix.md) | What can be tested, how, what cannot |
| [release.md](release.md) | Release CI, keystore, F-Droid, reproducibility |
| [btleplug.md](btleplug.md) | btleplug fork (`0.12.0-muse-5`) — JNI attach + notification death spiral |
| [muse-rs.md](muse-rs.md) | muse-rs `0.1.1` patch, Classic vs Athena, battery, Athena optical/fNIRS gap |
| [monitor.md](monitor.md) | **Frozen** live graphs + connect-time recording (Follow/Inspect, sweep EEG, tmp_/recording_). Implementer: [TODO/handoff-monitor.md](TODO/handoff-monitor.md) |

## Feedback

| File | Contents |
|------|----------|
| [feedback/pipeline-contract.md](feedback/pipeline-contract.md) | Frozen pipeline spec (PRs 1–7 implemented). Do not reopen Key Decisions. |
| [feedback/architecture.md](feedback/architecture.md) | Lanes, protocol documents, calibration as implemented |
| [feedback/todos.md](feedback/todos.md) | Checklist |

Format / cache byte-level docs (repo root, not here):
[README_feedback_format.md](../README_feedback_format.md),
[README_history_cache.md](../README_history_cache.md).

## Queued

Not the active branch. Do not mix into connect-simulator-ux or
pipeline-contract work.

| File | Contents |
|------|----------|
| [TODO/README.md](TODO/README.md) | Index |
| [TODO/handoff-monitor.md](TODO/handoff-monitor.md) | Monitor series: **PR 5a next** (Record / Stop), then 5b–6, **7** Bands context strip, **8** Spectrogram FFT window |
| [TODO/athena-optics-contract.md](TODO/athena-optics-contract.md) | Athena optical raw stream (muse-rs `Optics`, session tag 11) |
| [TODO/handoff-athena-optics.md](TODO/handoff-athena-optics.md) | Implementer order, files, LOC |

## Archive

Finished work and history live in [archive/](archive/). Do not treat those
files as current orientation.
