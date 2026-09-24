Archived 2026-09-24 — superseded by unified v6 metadata dialect in `.ai/contracts/fileformat_v6.md` (NFED6).

# Session vs recording metadata JSON

| Field | Value |
|---|---|
| Status | **Queued.** Revisit soon. Not a container-layout change. |
| Date | 2026-09-20 |
| Do not mix | Pipeline Key Decisions; Crown Start; Connect UX; v5 header size / tags 1–10; Athena optics; History dashboard unification (UI). |

Feedback `.neurofeed` files and recording `.neurofeed` files are the **same
container** (68-byte `NFED5` + WebP + zstd metadata + zstd computed + raw
copy). The **metadata JSON inside** is two different shapes.

That split is a mistake. Recording grew a nested `RecordingMetadata`
(`formatVersion`, `kind`, `device {}`, ten-key `streams`) because there was
no format contract covering both products. Feedback stayed a flat
`SessionMetadata` (no `kind` / `streams` / `formatVersion` in the file;
sqlite `kind` is set on publish).

**Today (do not silently “fix”):**

- Readers must accept both dialects. `v5ParseHead` returns opaque bytes and
  does not parse `kind`.
- Frozen law: [../contracts/session-format-contract.md](../contracts/session-format-contract.md).
- Human examples: [../../README_feedback_format.md](../../README_feedback_format.md).

**When revisiting:** one metadata dialect, or a documented dual-read with a
migration. Either way it is an explicit PR. Unifying History *chrome*
([history-dashboard-unification.md](history-dashboard-unification.md)) is a
different thread and must not rewrite the JSON as a side effect.
