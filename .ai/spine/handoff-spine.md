# Handoff — data-plane spine (coordinator thread)

| Field | Value |
|---|---|
| Date | 2026-09-20 |
| Status | **Ready to implement.** Contract frozen. This file is for a **new coordinator thread**, not an implementer. |
| Spec | [data-plane-contract_grok-build.md](data-plane-contract_grok-build.md) — **Frozen.** D1–D3 accepted. |
| Branch | `refactor/spine` (continue; do **not** open a parallel git branch). |
| Workflow | Coordinator spawns **one** subagent per PR, **sequential**. Subagent implements + tests + **one git commit** if PASS. Coordinator does **not** code and does **not** review diffs. |
| Do not mix | Feedback pipeline Key Decisions, Crown Start, Connect UX, monitor graph freezes, Athena optics, Spur A, new `MuseEventDto` replacement (D3), `rust/src/spine/normalize/`. |

Read the contract first. This file is order, gates, and paste-ready prompts. Do not relitigate Key Decisions here.

---

## Workflow judgment (why this shape)

**Yes — sequential coordinator + one subagent per numbered PR is the right test.** The PRs depend on each other (2 → 3 → 4 → 5 → 6; 7 after 4). Parallel implementers would fight the writer and the format.

**Coordinator must not write code.** That is the point of the new thread: keep the parent context small.

**Coordinator must not “review” the diff** (no nits, no rewrite). It **does** run a **mechanical gate** before spawning the next subagent. That is managing, not reviewing:

1. Subagent final message starts with `PASS` or `FAIL`.
2. If PASS: `git log -1 --oneline` shows **one new commit** whose subject matches the PR’s frozen message (below).
3. If FAIL, missing commit, or the subagent started the next PR: **stop. Ping windwerfer.** Do not spawn the next one.

Without that gate, a failed PR 3 poisons 4–7 and you will not notice until the end.

**Do not** `isolation: worktree`. Commits must land on `refactor/spine` in the shared tree.

**Do not** `git push` or open a GitHub PR unless windwerfer asks.

**Do not** spawn two implementers at once.

---

## Paste this as the coordinator thread’s user prompt

```
You are the spine coordinator on branch refactor/spine.

Read, in order:
1. .ai/spine/handoff-spine.md   (this workflow)
2. .ai/spine/data-plane-contract_grok-build.md  (frozen spec)
3. AGENTS.md (pins only; do not reopen freezes)

You do not write application code. You do not review diffs. You do not
commit. You spawn one general-purpose subagent at a time (isolation none,
shared workspace), using the prompt in the handoff for that PR.

Order: PR 1 → 2 → 3 → 4 → 5 → 6 → 7. Never skip, never parallel.

After each subagent finishes:
- PASS + matching git commit → spawn the next PR.
- FAIL, no commit, or scope creep → stop and tell me. Do not continue.

When PR 7 has PASS+commit (or PR 7 FAIL), stop and report the commit list.
```

---

## Frozen decisions (repeat — do not reopen)

Short form of the contract. If a subagent wants to change these, that is FAIL.

- **D1:** Live inner zstd frames (~64 KiB, level 3). **No outer zstd** on the container raw section (copy `.raw`). **No dual-read**, no flags bit, no leftover `decode_all` on the raw section. Purge comments/docs/code that taught `raw (zstd)` on the container, **same PR** as the encode change. Metadata + computed still zstd at assemble (first compression).
- **D2:** Android FGS in this series, **last** (PR 7). Linux soak does not wait on it. Screen-off overnight; no keep-screen-on.
- **D3:** `MuseEventDto` stays the Dart view / FeatureBus / streaming pipe. Capture must not use it.
- One `SessionRecorder`/writer, prefixes `tmp_` / `recording_` / `session_`. `tmp_` never assembled.
- Fork after derivation, before Dart. Dedicated **writer `std::thread`**. Forwarder only `encode` + `try_send` (bounded ~1–4 MiB of **bytes**). No `write` on the forwarder or JNI thread.
- Assemble writes a **path**. Extra RSS must not grow with session length. Notes/Save copy raw **section** as opaque bytes.
- Soak harness required. 12 h-equivalent, not wall-clock 12 h. Capture drops = 0 under design load (after the writer exists).
- Crown Start still refused. v5 header **size** and tags 1–10 unchanged.

---

## Series map

| PR | Title | Commit subject (exact) | Depends | Coordinator trap |
|---|---|---|---|---|
| **1** | Freeze contract + indexes | `docs(spine): freeze data-plane contract` | — | Docs only. No Rust/Dart product code. |
| **2** | Soak on **current** code | `test(spine): max-rate soak harness on current assemble` | 1 | Harness **must** document today’s O(n) RAM. That is PASS, not FAIL. Do not “fix” assemble here. |
| **3** | Kill outer raw zstd + streaming assemble + purge | `fix(spine): copy raw body into v5; no outer zstd` | 2 | No dual-read. Purge docs in the **same** commit. |
| **4** | Rust writer + fork + thread | `feat(spine): Rust capture writer for tmp/recording/session` | 3 | Dart live encode may still exist until PR 5. Facades over the writer. |
| **5** | Delete Dart live encode | `refactor(spine): remove Dart live encode path` | 4 | Grep production `writeEvent` → `encodeSessionEvent` / `sessionFrameBytes` = empty. |
| **6** | Folder locality | `refactor(spine): move capture under spine/` | 5 | Behavior-preserving. No feature work. |
| **7** | Android FGS | `feat(android): foreground service for keepable capture` | 4 (after 6 in this sequence) | No phone CI. PASS = code + analyze + tests that can run here. Manual 10 min is a note, not a blocker. |

---

## Rules for every implementer subagent

Copy into each prompt (already included below):

- Follow the frozen contract. Deviations: FAIL (do not commit).
- Skill `neurofeed-verify` after edits (`flutter analyze lib/src`; tests from the PR; FFI: `cargo build --manifest-path rust/Cargo.toml` first; format: `cargo test --lib session_format`).
- If FFI surface changes: `flutter_rust_bridge_codegen generate` and commit **both** `rust/src/frb_generated.rs` and `lib/src/rust/`. Then `cargo build --release --manifest-path rust/Cargo.toml` if desktop `flutter run` would be used (loader trap).
- **You are authorized to `git commit` exactly once** if PASS. Do not push. Do not `git commit --amend` of someone else’s commit. Do not start the next PR.
- If FAIL: no commit (or leave the tree dirty and say FAIL). Coordinator will stop.
- Final message **first line** must be `PASS` or `FAIL`, then: files, tests run, commit hash if PASS, why if FAIL.
- Do not unlock Crown Start, reopen Connect/pipeline/monitor freezes, or add `normalize/`.
- Do not kill PulseAudio / Wayland / adb / Dart language-server.
- Packages: `neurofeed` / `rust_lib_neurofeed` only.

---

## PR 1 — contract freeze (docs)

**Goal:** Contract + handoff + indexes are the source of truth. Status Frozen.

**In scope:** `.ai/spine/data-plane-contract_grok-build.md` (already Frozen), `.ai/spine/handoff-spine.md`, `.ai/active-task.md`, `.ai/README.md`. No product code.

**Pass:** indexes point at the grok-build contract + this handoff; Grokbot path not listed as implementable (file is gone); `git commit` with the frozen subject.

**Not:** soak, encode, writer.

### Subagent prompt (PR 1)

```
You implement spine PR 1 only on branch refactor/spine.

Read:
- .ai/spine/handoff-spine.md (PR 1 section)
- .ai/spine/data-plane-contract_grok-build.md (already Frozen)
- AGENTS.md

Work: make .ai/README.md and .ai/active-task.md point at
data-plane-contract_grok-build.md + handoff-spine.md as governing.
Do not edit Rust/Dart product code. Do not start PR 2.

Verify: the README spine table no longer treats a missing Grokbot
data-plane-contract.md as live.

You MAY git commit once if PASS. Do not push.
Subject: docs(spine): freeze data-plane contract

First line of your final message: PASS or FAIL.
Then files, tests (none required), commit hash if PASS.
```

---

## PR 2 — soak harness on current code

**Goal:** Measure. Do not fix.

**In scope:** `rust/src/spine/soak.rs` (or tests next to `session_format` if `spine/` module wiring is required — a tiny `mod spine` is OK). Command documented in `.ai/test-matrix.md`.

**Pass:** harness runs at max rate; prints volume; **shows** today’s assemble is O(n) RAM / whole-file `encode_all` (expected). Commit.

**Fail:** “fixed” assemble in this PR; wall-clock 12 h; no command in test-matrix.

### Subagent prompt (PR 2)

```
You implement spine PR 2 only on branch refactor/spine.

Read:
- .ai/spine/handoff-spine.md (PR 2)
- .ai/spine/data-plane-contract_grok-build.md sections Design load and soak, Two layers
- AGENTS.md
- .grok/skills/neurofeed-verify/SKILL.md

Work: add a max-rate soak/filler that drives current assemble
(container_encode_v5 / read whole raw). Document the command in
.ai/test-matrix.md. Do NOT fix O(n) RAM. The harness existing and
reporting today’s whole-file compress is PASS.

cargo test / the documented command must run. No Dart UI required.

You MAY git commit once if PASS. Do not push. Do not start PR 3.
Subject: test(spine): max-rate soak harness on current assemble

First line of your final message: PASS or FAIL.
```

---

## PR 3 — no outer zstd + streaming assemble + purge

**Goal:** Container raw section = copy of `.raw`. `v5_extract_raw` does not zstd-decode the section. Assemble/notes/Save do not hold 12 h in a `Vec`. Purge every comment/doc/test that taught container `raw (zstd)`.

**In scope (checklist — all in one commit):**

- `rust/src/api/session_format.rs` — stop `encode_all` of `raw_body`; `v5_extract_raw` returns section bytes; comments `[raw (zstd)]` / “Compress metadata, computed, raw separately” gone
- path-based assemble if needed (`container_encode_v5_to_path` or equivalent); production keepable captures must not return the whole file
- `updateNotes` / dashboard Save: copy raw **section** opaque
- `README_feedback_format.md`, `README.md`, `.ai/architecture.md`, `scratch_writer.dart` “uncompressed temp files” lie
- tests: `cargo test --lib session_format`; FFI assemble tests on **small** fixtures
- re-run soak: extra RSS must not scale with filled volume (or no `read_to_end` of keepable raw in assemble)

**Not:** dual-read, flags bit, Dart live encode move, Android.

**Fail:** leftover `zstd::encode_all` on raw_body; leftover “raw (zstd)” in format README; supporting old double-wrapped files.

### Subagent prompt (PR 3)

```
You implement spine PR 3 only on branch refactor/spine.

Read:
- .ai/spine/handoff-spine.md (PR 3)
- .ai/spine/data-plane-contract_grok-build.md (Two layers, Key Decision 3, RAM rules, purge table)
- AGENTS.md
- .grok/skills/neurofeed-verify/SKILL.md

Work: kill the OUTER zstd on the v5 raw section. Copy the framed .raw
into the container. No dual-read, no flags bit, no decode_all fallback
on that section. Metadata + computed stay zstd. Streaming / file-to-file
assemble and notes/Save that do not materialize whole raw.

PURGE in this same commit every comment/doc/test that says the container
raw section is zstd. Do not leave commented-out encode_all(raw).

Verify: cargo test --lib session_format; flutter analyze lib/src;
FFI tests in .ai/test-matrix.md that touch assemble/store/export/charts
(host cargo build first). Grep: no "raw (zstd)" container line in
session_format.rs or README_feedback_format.md.

You MAY git commit once if PASS. Do not push. Do not start PR 4.
Subject: fix(spine): copy raw body into v5; no outer zstd

First line of your final message: PASS or FAIL.
```

---

## PR 4 — Rust capture writer

**Goal:** Forwarder forks: `try_send` encoded bytes to a **dedicated writer thread**; Dart facades start/stop/sidecar/computed; Inspect index; crash recovery can assemble leftover temps.

**In scope:** `rust/src/spine/capture.rs` (and FRB re-exports), forwarder tap, Dart `FeedbackRecorder` / `MonitorRecorder` as facades, lease stays Dart. Threading section of the contract is law.

**Pass:** `flutter analyze lib/src`; recording/session assemble tests; `file_backed_source_test`; soak drops = 0 on the filler if it now talks to the writer. Linux agent Record/Stop if the app is already runnable; do not start a second `flutter run` if one is up.

**Not:** delete Dart `encodeSessionEvent` yet (PR 5); FGS; folder moves of graphs.

**FFI:** codegen both sides if you add `capture_*` functions.

### Subagent prompt (PR 4)

```
You implement spine PR 4 only on branch refactor/spine.

Read:
- .ai/spine/handoff-spine.md (PR 4)
- .ai/spine/data-plane-contract_grok-build.md (Capture API, Threading, Key Decisions 1–2, 5, 9)
- AGENTS.md
- .grok/skills/neurofeed-verify/SKILL.md

Work: Rust-owned capture writer for prefixes tmp / recording / session.
Dedicated std::thread. Forwarder encodes records and try_sends bytes
(bounded 1–4 MiB). Never write() on the forwarder or JNI thread.
Dart lease + start/stop; computed JSONL and sidecar go through the
same writer. Inspect flush index kept. Crash recovery still Dart,
may call assemble-on-temps.

If you add FRB functions: flutter_rust_bridge_codegen generate and
commit both generated sides. Rebuild host lib before FFI tests.

Do not delete the Dart live encode path yet (PR 5) unless the facades
no longer need it — prefer facades calling Rust so PR 5 is a deletion.

You MAY git commit once if PASS. Do not push. Do not start PR 5.
Subject: feat(spine): Rust capture writer for tmp/recording/session

First line of your final message: PASS or FAIL.
```

---

## PR 5 — delete Dart live encode

**Goal:** Production live path does not call `encodeSessionEvent` / `sessionFrameBytes`. FFI helpers may remain for tests/export of **small** fixtures.

**Pass:** grep of `lib/src` production (not `test/`) has no live `sessionFrameBytes` / `encodeSessionEvent` from `writeEvent`. `flutter analyze lib/src`. Existing tests green.

### Subagent prompt (PR 5)

```
You implement spine PR 5 only on branch refactor/spine.

Read:
- .ai/spine/handoff-spine.md (PR 5)
- .ai/spine/data-plane-contract_grok-build.md
- AGENTS.md
- .grok/skills/neurofeed-verify/SKILL.md

Work: remove the production Dart live encode path
(writeEvent → encodeSessionEvent → sessionFrameBytes → writeAsBytesSync).
Keep FFI helpers for tests/export of small fixtures if needed.

Verify: grep lib/src (exclude test) for encodeSessionEvent and
sessionFrameBytes on the live recorder path = none.
flutter analyze lib/src. Run test-matrix FFI assemble/store tests
(host cargo build first).

You MAY git commit once if PASS. Do not push. Do not start PR 6.
Subject: refactor(spine): remove Dart live encode path

First line of your final message: PASS or FAIL.
```

---

## PR 6 — folders

**Goal:** Capture/assemble/soak live under `rust/src/spine/` and Dart adapters under `lib/src/spine/`. Behavior-preserving.

**Pass:** analyze + the same tests as PR 5. No feature changes.

### Subagent prompt (PR 6)

```
You implement spine PR 6 only on branch refactor/spine.

Read:
- .ai/spine/handoff-spine.md (PR 6)
- .ai/spine/data-plane-contract_grok-build.md (Target tree)
- AGENTS.md
- .grok/skills/neurofeed-verify/SKILL.md

Work: behavior-preserving moves so capture/assemble/soak sit under
rust/src/spine/ and thin Dart adapters under lib/src/spine/.
Update imports. Do not add features. Do not move muse.rs DSP,
features.rs, graph panes, or audio.

flutter analyze lib/src. FFI tests as in test-matrix for assemble.

You MAY git commit once if PASS. Do not push. Do not start PR 7.
Subject: refactor(spine): move capture under spine/

First line of your final message: PASS or FAIL.
```

---

## PR 7 — Android FGS

**Goal:** Foreground service, type `connectedDevice`, same process, notification while `recording` or `feedback` (not `tmp_`). Screen stays allowed to sleep.

**Pass:** manifest permissions/types; service start/stop wired to keepable capture; `flutter analyze lib/src`. Cannot prove a phone night in this sandbox — say so. Do not block on a device.

**Not:** keep-screen-on, boot autostart, battery-exemption UI unless trivial, second service beside SoLoud.

### Subagent prompt (PR 7)

```
You implement spine PR 7 only on branch refactor/spine.

Read:
- .ai/spine/handoff-spine.md (PR 7)
- .ai/spine/data-plane-contract_grok-build.md (Android overnight addendum)
- AGENTS.md
- .grok/skills/neurofeed-verify/SKILL.md

Work: Android foreground service (connectedDevice) in the same process
as Flutter/Rust. Persistent notification while CaptureKind is recording
or feedback, not tmp_. Start with keepable capture; stop when it ends
(including unsaved ended session until Save/Discard). Do not keep the
screen on as the overnight mechanism.

flutter analyze lib/src. There is no phone in CI; do not fail the PR
for lack of adb overnight. Note what you could not verify.

You MAY git commit once if PASS. Do not push. This is the last PR.
Subject: feat(android): foreground service for keepable capture

First line of your final message: PASS or FAIL.
```

---

## Coordinator stop conditions

Stop the series and ping windwerfer if:

- Any subagent returns `FAIL`
- No matching commit after a claimed PASS
- A subagent implements two PRs
- A subagent reopens D1–D3, Crown Start, or adds `normalize/`
- Worktree isolation was used (commits missing from `refactor/spine`)

When finished, report:

```
PR 1 <hash> docs(spine): …
…
PR 7 <hash> feat(android): …
```

or the first FAIL.

---

## Queued elsewhere (not these PRs)

Crown run, OSC discovery, Athena optics, Spur A, replacing `MuseEventDto`, battery-exemption Settings.
