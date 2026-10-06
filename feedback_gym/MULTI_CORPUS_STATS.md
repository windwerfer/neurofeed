# MULTI_CORPUS_STATS

_Generated: 2026-10-06 12:32:47 UTC _
_Board: `results/20261006T123247Z_multi/multi_board.json`_

> Metrics: [`metrics.md`](metrics.md). Aggregates only; sibling corpora are findings-only and their data never lands in neurofeed. **N/A** = the corpus cannot score that feature/lane (e.g. no `ai_*` column).

## Corpora

| corpus | run | N | labels | calibration | license / use |
|--------|-----|--:|--------|-------------|---------------|
| sleep-edf-test | `20261006T123247Z_sleep-edf-test` | 61736 | drowsy/hypnagogic | global cal_n=90 | built-in preset |
| lee2026-eo-ec | `20261006T123247Z_lee2026-eo-ec` | 5900 | eyes_open_rest/eyes_closed_rest | per-recording (25 rec) | CC-BY-4.0 / findings-only |
| lee2026-artifacts | `20261006T123247Z_lee2026-artifacts` | 18054 | clean_rest/cued_artifact_task | per-recording (102 rec) | CC-BY-4.0 / findings-only |

## Protocols (final · r/i/g)

| id | sleep-edf-test | lee2026-eo-ec | lee2026-artifacts |
|----|------:|------:|------:|
| drowsiness | 0.762 (r 0.866 · i 1.000 · g 0.430) | 0.725 (r 0.765 · i 1.000 · g 0.473) | 0.716 (r 0.588 · i 1.000 · g 0.741) |
| twilight | 0.534 (r 0.409 · i 1.000 · g 0.430) | 0.591 (r 0.498 · i 1.000 · g 0.473) | 0.747 (r 0.649 · i 1.000 · g 0.741) |
| alertnessOpen | 0.880 (r 0.831 · i 1.000 · g —) | 0.794 (r 0.712 · i 1.000 · g —) | 0.733 (r 0.627 · i 1.000 · g —) |
| alertnessClosed | 0.745 (r 0.831 · i 1.000 · g 0.430) | 0.698 (r 0.712 · i 1.000 · g 0.473) | 0.736 (r 0.627 · i 1.000 · g 0.741) |
| mindfulness | 0.775 (r 0.892 · i 1.000 · g 0.430) | 0.722 (r 0.760 · i 1.000 · g 0.473) | 0.690 (r 0.535 · i 1.000 · g 0.741) |
| concentration | 0.687 (r 0.731 · i 0.963 · g 0.430) | 0.531 (r 0.526 · i 0.629 · g 0.473) | 0.548 (r 0.410 · i 0.604 · g 0.741) |
| relaxedConcentration | 0.552 (r 0.494 · i 0.879 · g 0.430) | 0.501 (r 0.409 · i 0.773 · g 0.473) | 0.554 (r 0.360 · i 0.759 · g 0.741) |
| recordOnly | N/A (r — · i — · g —) | N/A (r — · i — · g —) | N/A (r — · i — · g —) |
| guardrailOnly | 0.430 (r — · i — · g 0.430) | 0.473 (r — · i — · g 0.473) | 0.741 (r — · i — · g 0.741) |

## Features (score · sep · best_p)

| id | sleep-edf-test | lee2026-eo-ec | lee2026-artifacts |
|----|------:|------:|------:|
| band.atr | 0.825 · sep 0.574 · p50 | 0.717 · sep 0.693 · p50 | 0.476 · sep 0.684 · p50 |
| band.tar | 0.176 · sep 0.574 · p50 | 0.323 · sep 0.693 · p50 | 0.553 · sep 0.684 · p50 |
| band.btr | 0.771 · sep 0.591 · p50 | 0.628 · sep 0.582 · p50 | 0.519 · sep 0.649 · p50 |
| band.alpha | 0.864 · sep 0.523 · p50 | 0.690 · sep 0.711 · p50 | 0.387 · sep 0.751 · p50 |
| band.delta | 0.531 · sep 0.584 · p95 | 0.572 · sep 0.618 · p90 | 0.773 · sep 0.794 · p75 |
| ai.a_vig | 0.785 · sep 0.849 · p95 | N/A (needs_pack) | N/A (needs_pack) |
| ai.wake_light | 0.795 · sep 0.861 · p95 | N/A (needs_pack) | N/A (needs_pack) |
| ai.a_vig_reve | 0.843 · sep 0.872 · p50 | N/A (needs_pack) | N/A (needs_pack) |
| ai.wake_light_reve | 0.842 · sep 0.870 · p50 | N/A (needs_pack) | N/A (needs_pack) |
| ai.drowsiness | 0.785 · sep 0.849 · p95 | N/A (needs_pack) | N/A (needs_pack) |
| device.focus | N/A (n/a) | N/A (n/a) | N/A (n/a) |
| device.calm | N/A (n/a) | N/A (n/a) | N/A (n/a) |
