# TODO

Queued work. Not the active branch. Do not start these from
`feat/connect-simulator-ux` or mix them into pipeline-contract /
Crown-start threads.

| Thread | Spec | Handoff |
|--------|------|---------|
| Athena optics (raw stream) | **Landed 2026-11-11** (first milestone, see `log/devlog.md`). [athena-optics-contract.md](athena-optics-contract.md) | [handoff-athena-optics.md](handoff-athena-optics.md) (do not implement from this) |
| History Dashboard + Feedback chips | [handoff-history-summary-chips.md](handoff-history-summary-chips.md) | same file |
| Import / export (EDF · Mind Monitor CSV) | **Landed** in Rust (`crates/nf-import`). [import-export.md](import-export.md) is the Flutter-era spec | — |
| App folder, cache, models, export | **Landed.** [../contracts/app-folder.md](../contracts/app-folder.md) | [handoff-app-folder.md](handoff-app-folder.md) (do not implement from this) |

When a thread lands, slim the spec to frozen law and move it to
[`.ai/contracts/`](../contracts/). Keep the full implementer spec here
until then.
Delete or stub the row here after the move.

Archived (file format): [../archive/fileformat-v6-implementation.md](../archive/fileformat-v6-implementation.md),
[../archive/session_vs_recording_metadata.md](../archive/session_vs_recording_metadata.md).
Live format law: [../contracts/fileformat_v6.md](../contracts/fileformat_v6.md).
