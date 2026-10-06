# PROTOCOL_STATS

_Generated: 2026-10-06 14:22:21 UTC _
_Run id: `20261006T142221Z`_
_Corpus: `corpora/external/sleep_edf_test.npz`_

> Metrics are defined in [`metrics.md`](metrics.md). Do not claim performance without them.

UI dashboard: [`ui/index.html`](ui/index.html) (loads `ui/data/latest.json`).

## Protocols (composite + parts)

`guard` = feature-only label alignment (the score); `rail` = protocol `guard.deltaRail`; `warn` / `warn acc` = rate and label alignment of the app-fidelity warning (feature OR delta rail when the rail is on).

| id | final | reward | inhibit | guard | rail | warn | warn acc | notes |
|----|------:|-------:|--------:|------:|:----:|-----:|---------:|-------|
| sleepGuard | 0.634 | — | — | 0.634 | off | 0.789 | 0.634 | no reward lane |
| restAwake | 0.823 | 0.866 | 1.000 | 0.634 | off | 0.789 | 0.634 |  |
| openMonitor | 0.836 | 0.892 | 1.000 | 0.634 | off | 0.789 | 0.634 |  |
| alertOpen | 0.880 | 0.831 | 1.000 | — | — | — | — | no guard lane |
| alertClosed | 0.806 | 0.831 | 1.000 | 0.634 | off | 0.789 | 0.634 |  |
| concentrate | 0.748 | 0.731 | 0.963 | 0.634 | off | 0.789 | 0.634 |  |
| calibrateRecord | N/A | — | — | — | — | — | — | no reward lane; no guard lane; calibrateRecord — no lanes; composite N/A |
| recordOnly | N/A | — | — | — | — | — | — | no reward lane; no guard lane; recordOnly — no lanes; composite N/A |

## Features (standalone board)

| id | role | orphan | best_p | score | sep | status | latency |
|----|------|--------|-------:|------:|----:|--------|---------|
| band.atr | reward |  | 50 | 0.825 | 0.574 | ok | ~1s |
| band.tar | reward | yes | 50 | 0.176 | 0.574 | ok | ~1s |
| band.btr | reward |  | 50 | 0.771 | 0.591 | ok | ~1s |
| band.alpha | reward |  | 50 | 0.864 | 0.523 | ok | ~1s |
| band.delta | guard | yes | 95 | 0.531 | 0.584 | ok | ~1s |
| ai.a_vig | guard |  | 95 | 0.785 | 0.849 | ok | ~2s window / 1 Hz tick |
| ai.wake_light | guard | yes | 95 | 0.795 | 0.861 | ok | ~2s window / 1 Hz tick |
| ai.a_vig_reve | guard | yes | 50 | 0.843 | 0.872 | ok | ~4s window / 1 Hz tick |
| ai.wake_light_reve | guard | yes | 50 | 0.842 | 0.870 | ok | ~4s window / 1 Hz tick |
| ai.drowsiness | guard | yes | 95 | 0.785 | 0.849 | ok | ~2s window / 1 Hz tick |
| device.focus | reward,guard | yes | — | — | — | n/a | device-native |
| device.calm | reward,guard | yes | — | — | — | n/a | device-native |

## Sweeps

Per-feature percentile curves are in the UI **Sweeps** tab and in `results/20261006T142221Z/features.json`.

## Approximations vs Dart lanes

- Fixed calibration threshold (no EMA dynamic adapt).
- No dirty-pad / quality gating.
- AI uses precomputed emb_cache + linear heads (no CBraMod/REVE forward).
- Guard **scores** use `warn_feature` (percentile only); combined warn + rail still reported (Sleep-EDF abs delta often trips the 0.25 rail).
- REVE columns are subsample-aligned (≤80/class/rec) and NaN-padded — Diggus: directional only vs full CBraMod.
- Crown `device.*` marked N/A (no corpus).
