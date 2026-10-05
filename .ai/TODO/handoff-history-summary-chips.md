# Handoff — History Dashboard chip and Feedback chip

| Field | Value |
|---|---|
| Date | 2026-10-02 |
| Status | **Locked.** This is the series to implement. |
| Supersedes | The 2026-09-20 overview-painter docs. Those files are removed. Do not revive that series. |
| Suggested branch | `feat/history-summary-chips` from `main`. |
| Order | Strictly sequential. One PR, then the next. No parallel. |
| Commits | One commit per PR. Frozen subject below. Commit on PASS. Do not push unless the human asks. |

Owner walkthrough (2026-10-02) locked the page. v6 is the file. The session summary reuses the recording page and adds chips. This series is Dashboard + Feedback only.

---

## What shipped already (do not redo)

v6 computed frames already carry the trust fields: `percentile`, `thresholdPercentile`, `heldBack`, `inhibitTags`, `clean`, `dirtyReason`, `betaRel`, `deltaRel`, and the guard counterparts `featurePercentile`, `warnOver`, `ceilingOver`, `clean`, `dirtyReason`. The reward lane writes a dirty second with `clean: false` and a finite percentile, and still skips audio and `recordEpoch`. `baselineSamples`, `inhibitCeilingOverrides`, and `feedback.audioEvents` (`reward_chime`, `guard_chime`) are on the file. Pause stops the sampler; the timeline is root `annotations[]` `{onset, duration, type}`. Content `t` freezes during pause.

`assembleBaseStats` already writes nested `stats` (`hr`, `spo2`, `peakAlpha`, `movement.stillnessPct`, `quality`, `annotationSeconds`, `battery`, optional `experimental`).

## What this series builds

Two History chips.

**Dashboard** is the first chip on a feedback session and on a recording. Important numbers sit in a short block, in the spirit of today's Session summary card. **More** unfolds the rest. The open or closed choice is remembered in app settings. The last choice is the next open. First launch is closed.

**Feedback** is the next chip, on a feedback session only. It replays the live trust panes (reward, 0–2 inhibit, guard warn, guard ceiling when that protocol has one). The live More block stays off this page: no verdict line, no glyph strip, no needle, no "in for Ns". A few session totals sit under the panes.

```
┌─ Quiet Focus — Session ──────────────────── [ Save ] [ Discard ] ┐
│ (Dashboard)  Feedback                                            │
│  18:00        62% in zone        86% good         71% still      │
│  Peak α 10.2 Hz     64 bpm      SpO₂ 97%         14 chimes      │
│  ▸ More                                                          │
│  … today's charts stay under this block until a later series …  │
└──────────────────────────────────────────────────────────────────┘

┌─ Quiet Focus — Session ──────────────────────────────────────────┐
│ Dashboard  (Feedback)                                            │
│ (Reward)   Guard                              16:45 – 18:00      │
│ α / β trust panes, shared 75 s window                            │
│ 62% in zone · 14 chimes · 11% inhibited                          │
└──────────────────────────────────────────────────────────────────┘
```

A recording chip row is `Dashboard`, then today's `Bands`, `Raw EEG`, `Histogram`, `PSD`, `Spectrogram`. Opening a recording still lands on **Bands**. Opening a feedback session lands on **Dashboard**.

## Locked decisions

1. **File is v6.** No `pauseIntervals`. No new metadata keys. No header change. No FFI change.
2. **Live trust graphs stay Follow-only.** Do not add pan or Inspect to `TrustViewport`. Do not change `TrustGraphsColumn` behavior on the live session route. History gets its own window type.
3. **Do not push history samples through `TrustTrace`.** Its cap is 5 minutes and it prunes. Build `List<TrustRewardSample>` / `List<TrustGuardSample>` and pass those lists to the existing panes.
4. **Last-clean plot Y matches `TrustTrace.pushReward` / `pushGuard`.** A dirty second holds the previous clean percentile (and beta / delta plot values). The stroke stays the series color. The gray wash stays inhibit-out only.
5. **Session totals, not the visible 75 s.** In-zone, inhibited, warning, and ceiling percents are the whole session after training starts. Chime counts are the whole `audioEvents` list. The graph window does not change the numbers.
6. **Denominator is weighted clean seconds.** Use `frameSeconds` (`lib/src/session_format/stats_assemble.dart`). A missing second is not one second and is not sixty. Count a second only when `clean == true`. In zone = `clean && inTarget`. Inhibited = `heldBack` (already false when dirty). Guard warning = `clean && warning`. Ceiling = `clean && ceilingOver`. Seconds before `calibration.trainingStartOffsetSecs` are out of the denominator. Null when the lane did not run or the clean weight is 0. On screen that null is `—`.
7. **Do not display `outcomeScalars.pctInTarget` or `ComputedScalars.pctInTarget`.** Today's writer is `inTarget` frames divided by every frame, which includes calibration and noisy seconds. The reader in PR 1 is the number on screen.
8. **Chimes** are `audioEvents` rows with `type` `reward_chime` or `guard_chime`. That list is the plays that actually happened.
9. **Feedback chip is omitted** when the reader produces no reward samples and no guard samples. A recording never shows it. `recordOnly` does not show it. `guardrailOnly` shows it with the guard panes only.
10. **Reward / Guard on the Feedback chip are local to that page.** Default Reward on when reward samples exist. Default Guard on when reward samples do not exist and guard samples do. Otherwise Guard starts off. Do not write `Settings.trustRewardVisible` / `trustGuardVisible` from History.
11. **More fold** is `Settings`, key `history_dashboard_more_expanded`, default false. One flag for both History pages.
12. **Dashboard reads nested `stats` from the container metadata JSON.** `SessionStatsData` is the old flat card (`peakAlphaFreq`, `targetPct`, `avgBpm`). `RecordingMetadata.fromJson` drops `stats`. Keep the decoded map, or parse a small view model from it. Do not round-trip a recording through `RecordingMetadata.toJson` (that write would strip `stats`).
13. **Missing stats show `—`.** Do not invent a number. Experimental bands appear inside More only when `stats.experimental` is present.
14. **Save / Discard, unsaved `canPop: false`, notes, and the thumbnail capture stay.** They live with the Dashboard chip. Save and Discard stay in the app bar on the live unsaved summary. The thumbnail remains a capture of the summary block, not the trust graph.
15. **Superseded 2026-10-05.** The Dashboard chip has no graphs. The old relative-power Bands chart, Movement score, Heart rate / SpO₂, sleep guardrail, and music cutoff chart are gone from that chip. The music track list and the gesture-marker list stay. PDF / PNG `chartsFor` is unchanged. Alpha and theta remain series on the Bands chip. Do not restore the old Dashboard charts.
16. **Gesture marks** on the history panes come from root `annotations` with `duration == 0` and type `double_blink` or `double_jaw_clench`. Eye up / eye down stay unmarked, same as live.
17. **HR+SpO2 and Movement are chips on both History pages,** after Spectrogram. HR+SpO2 reuses `OpticalOverviewPane` (sidebar overview: HR 40–200, SpO₂ 50–100). When `session_parse_body` kept infrared PPG (channel 1), the chip also mounts `OpticalPpgPane` under it (flex 6/4). Detail window is page-local, 2/4/8/10 s, default 10 s, and its right edge stays on the overview’s visible end. No strip and no warning when the file has no IR samples. Movement is an inspect-only 0–1.5 g series (`MovementPane`). Overview window family is 15/30/60/120, default 30. No electrode toggles on those two chips.

## Not this series

Designed with the owner, explicitly deferred:

- Bands overview under history Raw EEG, Histogram, PSD, and Spectrogram (tap jumps the shaded window, drag of the shade moves the window, drag of the plot pans the plot). Live sidebar Spectrogram stays without a strip.
- `cinemaEnabled: false` on History.
- Removing Alpha vs Theta from the summary and from the default PDF. Done 2026-10-05. Do not restore that chart.
- Dashboard graphs removed 2026-10-05 (decision 15). HR+SpO2 and Movement chips added the same day (decision 17). Do not put those graphs back on the Dashboard chip.
- Making the History thumbnail the trust graph.
- A shared extraction of `RecordingGraphBody`. Done 2026-10-05 as `HistorySignalGraphs`. The feedback summary chip row is Dashboard, Feedback (when a lane exists), Bands, Raw EEG, Histogram, PSD, Spectrogram, HR+SpO2, Movement. Opening a feedback session still lands on Dashboard. A recording still opens on Bands.

Also frozen and untouched: pipeline Key Decisions, Crown Start, Connect UX, `DeviceKind`, live GraphShell Follow/Inspect, live trust Key Decisions in `.ai/trust-graphs.md`, data-plane contract, NFED6 header.

## Dashboard contents

Top block, both kinds, in this order. Skip a cell whose value is absent.

| Cell | Source |
|---|---|
| Duration | `durationS`, else `elapsedSeconds` |
| % in zone | PR 1 reader. Feedback file only. |
| % good | `stats.quality.pctGood` |
| % still | `stats.movement.stillnessPct` |
| Peak α | `stats.peakAlpha.maxPowerHz` |
| Heart rate | `stats.hr.mean` |
| SpO₂ | `stats.spo2.mean` |
| Reward chimes | count of `reward_chime`. Feedback file only. |

More, when unfolded:

| Row | Source |
|---|---|
| % inhibited, % guard warning, guard chimes | PR 1 reader and `guard_chime`. Feedback file only. |
| Heart rate min–max | `stats.hr.min` / `stats.hr.max` |
| SpO₂ min–max | `stats.spo2.min` / `stats.spo2.max` |
| Battery | `stats.battery.startPct` → `endPct` |
| Pause, bad contact, disconnect | `stats.annotationSeconds` |
| Per channel | `stats.quality.channelUsable` |
| Experimental bands | `stats.experimental`, only if present |

Spoken name of the fold control is `More`.

## Feedback chip contents

- Panes: existing `RewardTrustPane`, `InhibitTrustPane`, `GuardWarnPane`, `GuardCeilingPane`. `showMore: false`. Inhibit specs come from the saved protocol's ceilings, overlaid with `sessionSettings.inhibitCeilingOverrides` when that map is on the file. Guard pane list comes from `trustGuardPaneSpecs` for the saved guard feature id.
- Window: new `HistoryTrustViewport` in `lib/src/history/`. Default 75 s ending at the last sample `t`. Pinch and Ctrl/Meta+scroll zoom, clamped to the live limits (15–300 s). Drag pans. The right edge is not "now".
- Footer under the reward panes, one line: `{n}% in zone · {n} chimes · {n}% inhibited`. Hide the line when there is no reward lane.
- Footer under the guard panes: `{n}% warning · {n} chimes`, and ` · {n}% over ceiling` when the ceiling pane is shown.

## Series

| # | Frozen commit subject | Depends on |
|---|------------------------|------------|
| 1 | `feat(history): read trust samples and session totals from computed frames` | — |
| 2 | `feat(history): Dashboard chip on recordings` | — (still after 1) |
| 3 | `feat(history): session summary Dashboard chip` | 2 |
| 4 | `feat(history): Feedback chip replays trust panes` | 1, 3 |

### PR 1 — Reader

**Files:** `lib/src/history/session_trust.dart` (new), `test/history/session_trust_test.dart` (new), `.ai/test-matrix.md`.

Pure Dart. No widgets. No Flutter binding required if the types allow it. `TrustRewardSample` lives in `lib/src/feedback/trust/trust_trace.dart`.

Input: computed frames, `trainingStartOffsetSecs`, annotations, `audioEvents`. Output: reward samples, guard samples, marks, and the four percents plus the two chime counts.

Rules are the locked decisions above. A frame with `feedback.clean == null` is not a reward sample. A frame with `guardrail.clean == null` is not a guard sample. Recordings omit those keys, so both lists stay empty.

Tests, at least:

- Dirty second holds the previous clean percentile. First dirty second, with no clean before it, uses its own percentile.
- In-zone percent ignores a calibration second and a noisy second, and weights a 60 s gap as the median gap rather than 60.
- `heldBack` on a dirty second does not add inhibited time.
- Null percent when every second is noisy, and when the frames are a recording.
- Chime count ignores any other `audioEvents` type.
- Marks: `double_blink` and `double_jaw_clench` only.

### PR 2 — Recording Dashboard chip

**Files:** `lib/src/history/history_dashboard_summary.dart` (new), `lib/src/monitor/views/recording_dashboard.dart`, `lib/src/settings.dart`, `test/history/history_dashboard_summary_test.dart` (new), `.ai/ui-map.md`, `.ai/test-matrix.md`.

- Parse nested `stats` from the metadata JSON the recording page already decodes, before `RecordingMetadata.fromJson` drops it.
- `RecordingDashGraph` gains `dashboard` as the first segment. Selected chip on open stays `bands`.
- The summary widget takes a stats map plus optional feedback totals. Recordings pass no feedback totals, and the in-zone / chime cells are absent.
- `More` uses the settings flag. Widget test: default closed; toggling writes the pref; a second pump opens when the pref is true.
- Empty stats render without throwing. Cells with no value are omitted, not `0`.
- Update `.ai/ui-map.md` Recording dashboard: chip order and the `More` control.

### PR 3 — Session summary hosts the same chip

**Files:** `lib/src/views/feedback_dashboard.dart`, the summary widget from PR 2, `.ai/ui-map.md`, a widget test if the page can be pumped with a fixture.

- Chip row: `Dashboard`, and nothing else yet. Default `Dashboard`.
- Body: the PR 2 summary, then the existing chart list (Alpha vs Theta through gestures). Do not restyle those charts.
- Feedback totals for the summary come from PR 1 over the frames this page already loads. A failure of that pass leaves the feedback cells out. Base `stats` still render.
- App bar Save / Discard on the unsaved summary. `canPop: false` while scratch remains. Notes stay editable on this chip. Thumbnail capture stays on the summary block.
- History (`readOnly`) has Back, no Save / Discard. Same summary.
- ui-map Feedback summary: chip name `Dashboard`, `More`, and the note that the old charts are still on this chip.

### PR 4 — Feedback chip

**Files:** `lib/src/history/history_trust_viewport.dart` (new), `lib/src/views/feedback_dashboard.dart`, `test/history/history_trust_viewport_test.dart`, `test/history/feedback_chip_test.dart`, `.ai/ui-map.md`, `.ai/test-matrix.md`.

- Second chip, label `Feedback`, only when PR 1 returned a lane. `recordOnly` fixture has no chip.
- Viewport tests: default window ends at the last sample and is 75 s; drag moves the start; pinch clamps to 15–300; a live `TrustViewport` is not involved.
- Panes receive the PR 1 lists. `showMore` is false. Assert the live More strings (`In zone`, `Above the line`, `in for`) are absent, and the footer strings are present.
- Reward / Guard toggles do not change `Settings` trust visibility. Cover with a test that sets the prefs to the opposite and still sees the history defaults.
- Guard footer gains the ceiling percent only when the ceiling pane is in the spec.
- Live `FeedbackSessionView` is unchanged. A widget test is not required there if the diff does not touch it. Say so in the report.

## Shared implementer rules

```
Workspace: /workspaces/flutter_muse_ml
Governing spec: .ai/TODO/handoff-history-summary-chips.md (locked).
Do not revive the removed 2026-09-20 overview-painter series.
Verify skill: .grok/skills/neurofeed-verify/SKILL.md.
UI names: .ai/ui-map.md. Update it in the same PR as chrome.

Do not reopen the locked decisions in this file.
Do not add code comments unless a constraint is not obvious from the code.
Do not commit secrets. One git commit on PASS. Do not push.
flutter analyze lib/src must stay clean.
No FFI change, so no flutter_rust_bridge codegen.
Do not cargo check --target aarch64-linux-android.

Final message MUST start with a single line PASS or FAIL.
Second line: the commit subject (must match the frozen subject).
Then: files changed, tests run, and anything the next PR must know.
On FAIL: do not commit.
```

## Manager

Do not write application code in the manager thread. Spawn one implementer, wait until it finishes, then:

```bash
git log -1 --format=%s
git status --porcelain
```

PASS means the report starts with `PASS`, the subject matches, and the tree is clean. On FAIL, a wrong subject, or a dirty tree: stop and ping the human. Do not start the next PR. Do not fix the code yourself.

After PR 4, report the four commit hashes and stop.
