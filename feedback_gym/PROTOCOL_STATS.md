# PROTOCOL_STATS

_Generated: 2026-09-18 10:10:47 UTC _
_Run id: `20260918T101047Z`_
_Corpus: `corpora/synthetic/demo_session.npz`_

> Metrics are defined in [`metrics.md`](metrics.md). Do not claim performance without them.

UI dashboard: [`ui/index.html`](ui/index.html) (loads `ui/data/latest.json`).

## Protocols (composite + parts)

| id | final | reward | inhibit | guard | notes |
|----|------:|-------:|--------:|------:|-------|
| drowsiness | 0.652 | 0.395 | 1.000 | 0.850 |  |
| twilight | 0.873 | 0.835 | 1.000 | 0.850 |  |
| alertnessOpen | 0.585 | 0.419 | 1.000 | — | no guard lane |
| alertnessClosed | 0.664 | 0.419 | 1.000 | 0.850 |  |
| mindfulness | 0.658 | 0.406 | 1.000 | 0.850 |  |
| concentration | 0.582 | 0.393 | 0.650 | 0.850 |  |
| relaxedConcentration | 0.566 | 0.373 | 0.623 | 0.850 |  |
| recordOnly | N/A | — | — | — | no reward lane; no guard lane; recordOnly — no lanes; composite N/A |
| guardrailOnly | 0.850 | — | — | 0.850 | no reward lane |

## Features (standalone board)

| id | role | orphan | best_p | score | sep | status | latency |
|----|------|--------|-------:|------:|----:|--------|---------|
| band.atr | reward |  | 50 | 0.190 | 0.999 | ok | ~1s |
| band.tar | reward |  | 50 | 0.816 | 0.999 | ok | ~1s |
| band.btr | reward |  | 50 | 0.155 | 0.999 | ok | ~1s |
| band.alpha | reward |  | 50 | 0.190 | 0.997 | ok | ~1s |
| band.delta | guard |  | 95 | 0.936 | 1.000 | ok | ~1s |
| ai.a_vig | guard | yes | 95 | 0.979 | 1.000 | ok | ~2s window / 1 Hz tick |
| ai.wake_light | guard | yes | 95 | 0.945 | 1.000 | ok | ~2s window / 1 Hz tick |
| ai.a_vig_reve | guard | yes | 95 | 0.974 | 1.000 | ok | ~4s window / 1 Hz tick |
| ai.wake_light_reve | guard | yes | 95 | 0.955 | 1.000 | ok | ~4s window / 1 Hz tick |
| ai.drowsiness | guard | yes | 95 | 0.979 | 1.000 | ok | ~2s window / 1 Hz tick |
| device.focus | reward,guard | yes | — | — | — | n/a | device-native |
| device.calm | reward,guard | yes | — | — | — | n/a | device-native |

## Sweeps

Per-feature percentile curves are in the UI **Sweeps** tab and in `results/20260918T101047Z/features.json`.

## Approximations vs Dart lanes

- Fixed calibration threshold (no EMA dynamic adapt).
- No dirty-pad / quality gating.
- AI uses precomputed fixture columns (no CBraMod/REVE forward).
- Crown `device.*` marked N/A (no corpus).
