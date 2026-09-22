# Handoff — History dashboard unification (PR manager)

| Field | Value |
|---|---|
| Date | 2026-09-20 |
| Spec | [history-dashboard-unification.md](history-dashboard-unification.md) — **locked.** Do not reopen Open Questions or Key Decisions. |
| This file | Coordinator / PR-manager instructions only. The manager does **not** write app code. |
| Suggested branch | `feat/history-dashboard` from `main`. Do **not** pile onto `refactor/spine` or mix into Connect / pipeline / Crown Start. |
| Order | **Strictly sequential.** One subagent, one PR, wait for `PASS` + matching commit, then the next. **No async. No parallel.** PR 1 then 2 even though they have no code dependency. |
| Commits | One commit per PR. Frozen subject below. Subagent may `git commit` once on PASS (this file authorizes it). **No push** unless the human asks. |

The new thread is **only** the PR manager. It spawns a subagent for each PR and, on PASS, starts the next.

---

## Manager role (do / don't)

You are the coordinator. You **do not**:

- Edit application source, tests, or generated FRB.
- Review diffs, rewrite the subagent's code, or "just fix a nit."
- Spawn two PRs at once, background a PR "while starting the next," or `parallel()`.
- Skip a PR, fold two PRs into one agent, or reopen spec decisions.
- `git push` unless the human asked.

You **do**:

1. Confirm branch (`feat/history-dashboard` from `main`, or the branch the human named). Working tree clean before PR 1.
2. Spawn **one** `general-purpose` subagent, `isolation: none` (shared tree), **wait until it finishes** (`background: false`).
3. Read its report. Mechanical gate (all must hold):
   - First line of the subagent's final message is `PASS` or `FAIL`.
   - `git log -1 --format=%s` **equals** the frozen subject for that PR.
   - `git status --porcelain` is empty (no leftover uncommitted files).
4. On `PASS` + matching subject + clean tree: spawn the next PR.
5. On `FAIL`, missing commit, wrong subject, dirty tree, two PRs in one agent, or scope creep: **stop** and ping the human. Do not start the next PR. Do not "fix it yourself."

After PR 4: if the overview already paints recalibration hairlines mapped through `pauseIntervals`, **skip PR 7**. After PR 6 (and PR 7 if needed): report the commit hashes in order and stop.

---

## Frozen — do not reopen

From the spec Key Decisions and owner locks. Repeat in every implementer prompt:

- Pipeline-contract Key Decisions, Crown Start, Connect UX, `DeviceKind` Muse | Neurosity.
- v5 **68-byte header** / tags 1–10. Extra **computed JSONL keys** and metadata JSON **are** in path (PRs 2–3). That is not a header change.
- Live GraphShell Follow/Inspect; live trust-graph Key Decisions (`.ai/trust-graphs.md`). History is a **sibling** surface. Do not reuse `RewardTrustPane` / `TimeSeriesPane` / `BandCache` / `ViewportController` for the Feedback overview.
- RatioEngine 80/40. Dirty still skips `output.onSample` and `recordEpoch`. JSONL **does** get dirty seconds after PR 3.
- Monitor: no Spectrogram FFT chrome, no Bands `SMOOTH` / `REAL TIME`, no Bands strip on Spectrogram.
- Spine / data-plane contract: not this series.
- Width/alpha-as-variance: **rejected for v1.** Error bars are the zoom-out encoding.
- Recordings **never** get a Feedback chip.
- History list WebP = Feedback overview graph, **not** the stats card.
- On-screen History chip = **`Feedback`**. Live session chip stays **`Reward`**.
- Spoken names: `.ai/ui-map.md`. Update ui-map in the **same** PR as chrome.

---

## Series order (no async)

| # | Frozen commit subject | Depends on |
|---|------------------------|------------|
| 1 | `refactor(history): extract recording graph body; cinemaEnabled false` | — |
| 2 | `feat(session): extend computed FeedbackInfo/GuardrailInfo for live-trust fields` | — (still **after** 1) |
| 3 | `feat(feedback): emit live-trust fields; persist baseline and pauseIntervals` | 2 |
| 4 | `feat(history): Feedback chip training overview and overview thumbnail` | 3 |
| 5 | `feat(history): session monitor chips and HR+SpO2 pane` | 1, 4 |
| 5b | `feat(history): HR+SpO2 chip on recordings` | 1, 5 |
| 6 | `feat(history): TrainingExportChart and History notes collapsed` | 4 |
| 7 | `feat(history): recalibration hairlines on training overview` | 3, 4 — **skip** if PR 4 already did it |

---

## Shared implementer rules (paste into every PR prompt)

```
Workspace: /workspaces/flutter_muse_ml
Governing spec: .ai/TODO/history-dashboard-unification.md (locked).
Handoff: .ai/TODO/handoff-history-dashboard.md.
Verify skill: .grok/skills/neurofeed-verify/SKILL.md.
UI names: .ai/ui-map.md.

Do not reopen frozen decisions listed in the handoff.
Do not add code comments unless the spec requires a non-obvious constraint.
Do not commit secrets. One git commit on PASS; do not push.
flutter analyze lib/src must stay clean.
Do not run flutter run unless verify requires a widget you cannot unit-test
(prefer tests). Do not cargo check --target aarch64-linux-android.

When rust/src/api/ FFI surface changes: flutter_rust_bridge_codegen generate
and commit BOTH rust/src/frb_generated.rs and lib/src/rust/. Then
cargo build --release --manifest-path rust/Cargo.toml if a desktop loader
will be used (debug/cargokit is not what flutter run loads from
rust/target/release/).

Format / ComputedFrame changes: cargo test --lib session_format
(from rust/ or --manifest-path rust/Cargo.toml --lib session_format).

New test files: add them to .ai/test-matrix.md in this same PR
(pure-Dart list vs FFI list). Capture FFI tests stay --concurrency=1.

Final message MUST start with a single line PASS or FAIL.
Second line: the commit subject you used (must match the frozen subject).
Then: files changed, tests run, and any follow-up the next PR must know.
On FAIL: do not commit; say what blocked.
```

---

## Mechanical gate (manager, after each subagent)

```bash
git log -1 --format=%s
git status --porcelain
```

`PASS` iff:

1. Subagent final text starts with `PASS`.
2. `git log -1 --format=%s` is **exactly** the frozen subject for that PR.
3. Porcelain is empty.
4. Scope matches the PR (no "while I was here" files from a later PR).

Otherwise `FAIL` — stop.

---

## PR 1 — Extract recording graph body

**Frozen subject:** `refactor(history): extract recording graph body; cinemaEnabled false`

**Files:** `lib/src/monitor/views/recording_dashboard.dart`; new `lib/src/history/{history_chip_bar,history_dash_graph,recording_graph_body}.dart` (or equivalent under `lib/src/history/`); `lib/src/monitor/graph_shell.dart` (`cinemaEnabled`); `test/monitor/graph_shell_test.dart`; `.ai/test-matrix.md` only if a new test file is added.

**Do:** Move the **whole** recording-dashboard internals (`ViewportController`, `SweepBuffer.freeze()`, pinch, `_uv/_hz/_mag`, `ElectrodeToggles`, `fileSamples:` / `meanFromRecords` / `bandSeriesFromRecords`, pane `switch`, chip bar) into `RecordingGraphBody`. `RecordingDashboardView` becomes loader + that body. Golden behavior unchanged: default Raw EEG, Follow disabled, Histogram/PSD one-pane (no Bands strip). Add `GraphShell.cinemaEnabled` default `true`; this body passes `false` so History does not hide the toolbar in mobile landscape (`GraphCinema.of` is true without a scope today). Document that `_setGraph` still resets the Inspect window per kind.

**Do not:** `TrainingOutcomePane`, schema/FRB, session-summary edits, HR chip.

**Verify:** `flutter analyze lib/src`; `flutter test test/monitor/graph_shell_test.dart` (and existing recording/file-backed tests if you touch loaders). `cinemaEnabled: false` keeps Follow/Inspect/window visible in a landscape-sized test.

---

## PR 2 — Computed JSONL schema + FRB (no emit yet)

**Frozen subject:** `feat(session): extend computed FeedbackInfo/GuardrailInfo for live-trust fields`

**Files:** `rust/src/api/session_format.rs`; `lib/src/session_v5/computed_frame.dart`; `lib/src/spine/assemble.dart` `toFfiFrame`; generated `rust/src/frb_generated.rs` + `lib/src/rust/`; `lib/src/monitor/recording/monitor_sampler.dart`; `test/session_computed_charts_test.dart`; `cargo test --lib session_format`.

**Do:** Keep existing `ratio` / `threshold` / `inTarget` / `pct` and `guardrail.{sleepDir,clarity,warning,delta}`. Add the 1 Hz fields from spec § "Add at 1 Hz". On `ComputedFrame`, `FeedbackInfo`, `GuardrailInfo`, `PeakAlphaInfo`:

```rust
#[serde(rename_all = "camelCase")]
```

plus snake_case **aliases** on existing fields so in-memory Rust fixtures still round-trip. Canonical on-disk keys (Dart `toJson`):

- frame: `t`, `bands`, `pulse`, `movement`, `peakAlpha`, `spo2`, `lineNoise`, `signalQuality`, `gestures`, `guardrail`, `feedback`
- feedback extras: `percentile`, `thresholdPercentile`, `heldBack`, `inhibitTags`, `clean`, `dirtyReason`, `betaRel`, `deltaRel`
- guardrail extras: `featurePercentile`, `warnOver`, `ceilingOver`, `clean`, `dirtyReason`

`#[serde(default)]` on new fields. **Do not store `plotPercentile`.** `MonitorSampler` leaves `feedback.percentile`, `feedback.clean`, `guardrail.featurePercentile`, `guardrail.clean` as **`None`** — never `0` / `false`. FRB generate **both** sides. No emit-behavior change. No UI.

**Must-pass test:** Dart `toJsonBytes()` line → `v5ExtractComputed` → `feedback.percentile` and `feedback.clean` are `Some`, not `None`.

**Verify:** `flutter_rust_bridge_codegen generate`; `cargo test --manifest-path rust/Cargo.toml --lib session_format`; `cargo build --manifest-path rust/Cargo.toml`; `flutter analyze lib/src`; `flutter test --concurrency=1 test/session_computed_charts_test.dart`.

---

## PR 3 — Emit live-trust fields; baseline; pauseIntervals

**Frozen subject:** `feat(feedback): emit live-trust fields; persist baseline and pauseIntervals`

**Files:** `lib/src/feedback/{reward_lane,computed_sampler,feedback_state,session_metadata}.dart`; tests (dirty JSONL line; `baselineSamples` / `inhibitCeilingOverrides` / `pauseIntervals` round-trip). Add new test files to `.ai/test-matrix.md`.

**Do:**

- Grow `ComputedSampler.updateFeedback` / `updateGuardrail` to the 1 Hz tables.
- **Single copy site** in `FeedbackStateNotifier._onFeature`: after `_reward.onFeature` + `_trust.pushReward`, copy `last*` into `updateFeedback` (including dirty). After `_trust.pushGuard` (same tick, **band-math and dirty**, not only `onReveExtras`), copy guard extras.
- Dirty still skips `output.onSample` and `recordEpoch`. JSONL dirty line: `clean: false`, `inTarget: false`, `heldBack: false`, `inhibitTags: []`, finite **dirty** `percentile` (not last-clean Y).
- Persist `SessionCalibration.baselineSamples` (and recal vectors) + `inhibitCeilingOverrides`.
- Persist `SessionMetadata.pauseIntervals: [{startT, endT}]` in **`ComputedFrame.t` domain**: stamp `now - recordingStart` in `pause()` / `resume()` / `end()` if still paused. Sampler **keeps** emitting latched values during pause; `elapsedSeconds` ticker stays stopped.

**Do not:** UI, overview painter, FRB field adds (those landed in PR 2).

**Verify:** `flutter analyze lib/src`; pure-Dart tests for sampler/metadata; `flutter test test/session_metadata_roundtrip_test.dart` plus new tests. FFI only if you touch extract.

---

## PR 4 — Feedback chip + overview + thumbnail

**Frozen subject:** `feat(history): Feedback chip training overview and overview thumbnail`

**Files:** `lib/src/history/{training_outcome,training_outcome_pane,history_dashboard_shell}.dart`; bucket helper; `lib/src/views/feedback_dashboard.dart` (`_thumbKey` / `_capture`); `.ai/ui-map.md`; tests §11 + omit-None + pause gaps + pixel buckets; `.ai/test-matrix.md`.

**Depends on PR 3.** PR 1 is already on the branch; do **not** mount monitor chips yet.

**Merge gates (do not ship without):**

- `readOnly: false`: AppBar or sticky Save/Discard and `canPop: false`.
- Notes field still present (default-open on live is OK; collapse-on-History may wait for PR 6).
- **`_thumbKey` wraps `TrainingOutcomePane` or an offscreen 640×360 paint of the same painter.** Stats strip **outside** that boundary. Save uses `addPostFrameCallback` if needed. **No stats-card fallback.** `recordOnly` / pre-schema / empty overview → placeholder WebP.
- Stats strip Target time = spec formula (`double?`, `—` if null).
- **No** Raw EEG / Bands / Histogram / PSD / Spectrogram / HR+SpO2 chips.
- **`recordOnly` is not a blank `Expanded`.** Keep the existing stacked ListView until PR 5.

**Paint spec (one pane, not the live 1–4 stack):**

- X = `ComputedFrame.t` including calibration. Pause intervals = **dashed unvalued gaps**.
- Y fixed 0–100. Stroke = **`plotPercentile`** (read-time last-clean, `TrustTrace` rule). Line = `thresholdPercentile`. Stored dirty `percentile` is **not** the stroke.
- Ribbon from stored `clean` / `heldBack` / `inTarget`. Inhibit = gray wash + tags. History **`below`** = live **`Below the line`**.
- `schemaReady`: reward needs `feedback.clean` and `percentile`; guardrail-only needs `guardrail.clean` only. Pre-schema → empty copy, **no inference**.
- Playing `None` (`clean`/`percentile` still null) → **omit** (not noisy, not in Target time).
- `!hasReward` after clean: `noisy` or `quiet` only — **never** `below`.
- Zoom-out (default full session): if `n > widthPx`, **one bucket per pixel**; stroke = mean of `plotPercentile`; **stddev error bars** at ~8–12 columns; noisy-wins; skip pause / cal / omitted `None`. If `n ≤ widthPx`, every mapped sample, no bars. **No** width/alpha.
- Recal hairlines: pull in **if cheap** (playing-time → `t` via `pauseIntervals` + `trainingStartOffsetSecs`, formula in spec §5.3). If not, leave for PR 7 and say so in the PASS notes.

**Thumbnail:** first Save after this PR writes the **overview** WebP (`encodeThumbnailWebP` 640×360). Assemble-at-`end()` placeholder until Save is OK. sqlite BLOB pixels only.

**Verify:** `flutter analyze lib/src`; new `test/history/*` mapping tests (pure Dart). ui-map rows: Feedback chip vs live Reward; History `below`; History row preview = training overview WebP.

---

## PR 5 — Session monitor chips + session HR+SpO2

**Frozen subject:** `feat(history): session monitor chips and HR+SpO2 pane`

**Files:** `lib/src/views/feedback_dashboard.dart`; `RecordingGraphBody` from PR 1; `lib/src/history/hr_spo2_history_pane.dart`; `.ai/ui-map.md`; `.ai/test-matrix.md`.

**Do:** Compose `RecordingGraphBody` under session chips Raw EEG / Bands / Histogram / PSD / Spectrogram. Lazy `v5ExtractRaw` on first monitor-chip tap. Empty `recordedData` = assume all streams; hide a chip only when the list is **non-empty** and lacks that name. Bands computed fallback uses `linearToDb`. Follow disabled; `cinemaEnabled: false`. Independent viewports: Feedback keeps last full-span zoom; monitor chips keep last per-kind Inspect window (10 s at t=0 jump is OK; ui-map it). **HR+SpO2** chip: new dual-axis computed pane (40–200 bpm / 50–100 SpO₂), existing empty copy, **not** live `HrSpo2View`. `recordOnly` default chip = Bands. Do not ship a chip that errors.

**Verify:** `flutter analyze lib/src`; tests that the Feedback-chip path does not load raw; file-backed source tests if touched (`cargo build` first for FFI).

---

## PR 5b — HR+SpO2 on recordings

**Frozen subject:** `feat(history): HR+SpO2 chip on recordings`

**Files:** recording graph body / `HistoryDashGraph.hrSpo2`; `.ai/ui-map.md`; `.ai/test-matrix.md`.

**Do:** Add the chip to the **recording** row. Reuse `HrSpo2HistoryPane`. Empty copy if no pulse/spo2. **Default chip stays Raw EEG.** Not live optical GraphShell.

**Do not:** fold this into PR 5 in the same agent. This is its own commit.

**Verify:** `flutter analyze lib/src`; ui-map recording chip row includes `HR+SpO2`.

---

## PR 6 — Export Training page; notes collapsed on History

**Frozen subject:** `feat(history): TrainingExportChart and History notes collapsed`

**Files:** `lib/src/feedback/session_export.dart`, `session_pdf_export.dart`; `.ai/ui-map.md`; `.ai/export.md`; `test/session_export_test.dart`; `feedback_dashboard.dart` notes default; optional capture letterbox/pixelRatio only.

**Do:** History notes **collapsed** (live Save/Discard stays expanded). `TrainingExportChart` as PDF/PNG **page 0** (ribbon + reduced `plotPercentile` mean + same error-bar rule as on-screen full-span). **Not** `ExportChartLine`. Keep Bands / Movement / Heart rate / SpO₂ line pages. **Drop Alpha vs Theta** from the default PDF. New Save writes nullable `stats.targetPct`. Dirty-notes dialog unchanged. Thumbnail-as-graph already shipped in PR 4 — do not wait until here.

**Verify:** `cargo build --manifest-path rust/Cargo.toml`; `flutter test --concurrency=1 test/session_export_test.dart`; `flutter analyze lib/src`.

---

## PR 7 — Recalibration hairlines (skip if PR 4 did it)

**Frozen subject:** `feat(history): recalibration hairlines on training overview`

**Skip when:** PR 4 PASS notes say hairlines landed, **and** the overview maps `SessionRecalibration.atSecs` through `pauseIntervals` (not `atSecs + trainingStartOffset` alone).

**Do:** Map playing-time → `ComputedFrame.t` using the spec §5.3 loop. Paint hairlines on the overview. Test the mapping.

**Verify:** `flutter analyze lib/src`; mapping unit tests.

---

## Subagent prompt template

Paste the shared implementer rules, then the PR section, then:

```
You implement ONLY PR N.
Frozen commit subject (exact): <subject>
Read the spec sections named in that PR before coding.
When tests are green and analyze is clean: git add the PR files and
git commit -m "<subject>"
(no other commits). Then reply:

PASS
<subject>
<files>
<tests>
<notes for the next PR>

If blocked: FAIL on the first line, no commit.
```

Spawn: `subagent_type: general-purpose`, `isolation: none`, `background: false`. Wait. Gate. Next.

---

## Done when

Commits 1–6 exist on the branch with the frozen subjects (and 7 unless skipped). Tree clean. Report the seven-or-fewer hashes to the human. Do not open a PR on GitHub unless asked.
