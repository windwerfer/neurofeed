# MULTI_CORPUS_STATS

_Generated: 2026-10-12 08:36:31 UTC _
_Board: `results/20261012T083631Z_multi/multi_board.json`_

> Metrics: [`metrics.md`](metrics.md). Aggregates only; sibling corpora are findings-only and their data never lands in neurofeed. **N/A** = the corpus cannot score that feature/lane (e.g. no `ai_*` column).

## Corpora

| corpus | run | N | labels | calibration | license / use |
|--------|-----|--:|--------|-------------|---------------|
| sleep-edf-test | `20261012T083631Z_sleep-edf-test` | 61736 | drowsy/hypnagogic | global cal_n=90 | built-in preset |
| lee2026-eo-ec | `20261012T083631Z_lee2026-eo-ec` | 5509 | eyes_open_rest/eyes_closed_rest | per-recording (25 rec) | CC-BY-4.0 / findings-only |
| lee2026-artifacts | `20261012T083631Z_lee2026-artifacts` | 15863 | clean_rest/cued_artifact_task | per-recording (102 rec) | CC-BY-4.0 / findings-only |
| universe-stress | `20261012T083631Z_universe-stress` | 43665 | rest_or_low/stress_or_high | per-recording (44 rec) | CC-BY-4.0 / findings-only |
| boas-wake-n1 | `20261012T083631Z_boas-wake-n1` | 477662 | wake/N1 | per-recording (126 rec) | CC0 / findings-only (gym) |
| ds001787-mw-muse | `20261012T083631Z_ds001787-mw-muse` | 24973 | on_task/mind_wandering | per-recording (38 rec) | CC0 / findings-only (gym) |
| ds001787-mw-crown | `20261012T083631Z_ds001787-mw-crown` | 26204 | on_task/mind_wandering | per-recording (38 rec) | CC0 / findings-only (gym) |
| muse-sleeponset-labonly | `20261012T083631Z_muse-sleeponset-labonly` | 142540 | early_wake/pre_n2_300s | per-recording (343 rec) | CC-BY-NC-SA-4.0 / LAB-ONLY (NC): internal evaluation only; results never in product docs |

## Protocols (final · r/i/g)

| id | sleep-edf-test | lee2026-eo-ec | lee2026-artifacts | universe-stress | boas-wake-n1 | ds001787-mw-muse | ds001787-mw-crown | muse-sleeponset-labonly |
|----|------:|------:|------:|------:|------:|------:|------:|------:|
| sleepGuard | 0.774 (r — · i — · g 0.774) | N/A (r — · i — · g N/A) | N/A (r — · i — · g N/A) | N/A (r — · i — · g N/A) | 0.675 (r — · i — · g 0.675) | N/A (r — · i — · g N/A) | N/A (r — · i — · g N/A) | 0.721 (r — · i — · g 0.721) |
| restAwake | 0.865 (r 0.866 · i 1.000 · g 0.774) | 0.829 (r 0.761 · i 1.000 · g N/A) | 0.714 (r 0.599 · i 1.000 · g N/A) | 0.750 (r 0.650 · i 1.000 · g N/A) | 0.781 (r 0.756 · i 1.000 · g 0.675) | 0.770 (r 0.678 · i 1.000 · g N/A) | 0.741 (r 0.637 · i 1.000 · g N/A) | 0.799 (r 0.766 · i 1.000 · g 0.721) |
| openMonitor | 0.878 (r 0.892 · i 1.000 · g 0.774) | 0.823 (r 0.752 · i 1.000 · g N/A) | 0.682 (r 0.555 · i 1.000 · g N/A) | 0.711 (r 0.596 · i 1.000 · g N/A) | 0.803 (r 0.802 · i 1.000 · g 0.675) | 0.754 (r 0.655 · i 1.000 · g N/A) | 0.751 (r 0.651 · i 1.000 · g N/A) | 0.832 (r 0.832 · i 1.000 · g 0.721) |
| alertOpen | 0.880 (r 0.831 · i 1.000 · g —) | 0.788 (r 0.704 · i 1.000 · g —) | 0.746 (r 0.644 · i 1.000 · g —) | 0.814 (r 0.739 · i 1.000 · g —) | 0.763 (r 0.669 · i 1.000 · g —) | 0.763 (r 0.668 · i 1.000 · g —) | 0.731 (r 0.623 · i 1.000 · g —) | 0.784 (r 0.698 · i 1.000 · g —) |
| alertClosed | 0.848 (r 0.831 · i 1.000 · g 0.774) | 0.788 (r 0.704 · i 1.000 · g N/A) | 0.746 (r 0.644 · i 1.000 · g N/A) | 0.814 (r 0.739 · i 1.000 · g N/A) | 0.737 (r 0.669 · i 1.000 · g 0.675) | 0.763 (r 0.668 · i 1.000 · g N/A) | 0.731 (r 0.623 · i 1.000 · g N/A) | 0.765 (r 0.698 · i 1.000 · g 0.721) |
| calibrateRecord | N/A (r — · i — · g —) | N/A (r — · i — · g —) | N/A (r — · i — · g —) | N/A (r — · i — · g —) | N/A (r — · i — · g —) | N/A (r — · i — · g —) | N/A (r — · i — · g —) | N/A (r — · i — · g —) |

## Features (score · sep · best_p)

| id | sleep-edf-test | lee2026-eo-ec | lee2026-artifacts | universe-stress | boas-wake-n1 | ds001787-mw-muse | ds001787-mw-crown | muse-sleeponset-labonly |
|----|------:|------:|------:|------:|------:|------:|------:|------:|
| band.atr | 0.825 · sep 0.574 · p50 | 0.680 · sep 0.650 · p50 | 0.500 · sep 0.611 · p50 | 0.541 · sep 0.517 · p50 | 0.665 · sep 0.608 · p50 | 0.585 · sep 0.535 · p50 | 0.493 · sep 0.529 · p50 | 0.676 · sep 0.586 · p50 |
| band.tar | 0.176 · sep 0.574 · p50 | 0.327 · sep 0.650 · p50 | 0.517 · sep 0.611 · p50 | 0.456 · sep 0.517 · p50 | 0.336 · sep 0.608 · p50 | 0.412 · sep 0.535 · p50 | 0.495 · sep 0.529 · p50 | 0.323 · sep 0.586 · p50 |
| band.btr | 0.771 · sep 0.591 · p50 | 0.592 · sep 0.509 · p50 | 0.553 · sep 0.583 · p50 | 0.638 · sep 0.522 · p50 | 0.523 · sep 0.611 · p50 | 0.541 · sep 0.545 · p50 | 0.473 · sep 0.560 · p50 | 0.556 · sep 0.544 · p50 |
| band.alpha | 0.864 · sep 0.523 · p50 | 0.673 · sep 0.697 · p50 | 0.425 · sep 0.681 · p50 | 0.450 · sep 0.507 · p50 | 0.738 · sep 0.545 · p50 | 0.537 · sep 0.519 · p50 | 0.517 · sep 0.517 · p50 | 0.764 · sep 0.645 · p50 |
| band.delta | 0.531 · sep 0.584 · p95 | 0.559 · sep 0.618 · p95 | 0.714 · sep 0.726 · p70 | 0.515 · sep 0.527 · p95 | 0.531 · sep 0.557 · p95 | 0.535 · sep 0.539 · p60 | 0.572 · sep 0.580 · p55 | 0.603 · sep 0.691 · p95 |
| ai.a_vig | 0.785 · sep 0.849 · p95 | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | 0.677 · sep 0.731 · p95 | N/A (needs_pack) | N/A (needs_pack) | 0.755 · sep 0.786 · p95 |
| ai.wake_light | 0.795 · sep 0.861 · p95 | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | 0.677 · sep 0.731 · p95 | N/A (needs_pack) | N/A (needs_pack) | 0.761 · sep 0.793 · p95 |
| ai.a_vig_reve | 0.843 · sep 0.872 · p50 | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) |
| ai.wake_light_reve | 0.842 · sep 0.870 · p50 | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) |
| ai.drowsiness | 0.785 · sep 0.849 · p95 | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) | N/A (needs_pack) |
| device.focus | N/A (n/a) | N/A (n/a) | N/A (n/a) | N/A (n/a) | N/A (n/a) | N/A (n/a) | N/A (n/a) | N/A (n/a) |
| device.calm | N/A (n/a) | N/A (n/a) | N/A (n/a) | N/A (n/a) | N/A (n/a) | N/A (n/a) | N/A (n/a) | N/A (n/a) |
