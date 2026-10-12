# AI guard: fixed probability vs percentile-of-calibration (2026-10)

Runner: `runners/ai_threshold_sweep.py` (Lee AI sidecars from
`runners/lee_ai_columns.py`). Corpora: fair Sleep-EDF test corpus
(`sleep_edf_test.npz`, per-recording cal = leading wake run, cal rows never
scored, 17 recordings) for W vs N1; Lee 2026 Muse 2 awake rows (eyes-open /
eyes-closed rest, cued artifact task, clean rest) for false alarms. Warn rule
= app GuardLane with deltaRail off: warn while P(class 1) > threshold.

**Direction check:** `ai.a_vig` = P(hypnagogic), high = drowsy. Warn rate on
N1 rows is above wake at every cut (e.g. 0.79 vs 0.25 at P > 0.50), so `>` is
right.

**Choice:** `fixed`, P > **0.50** for every `ai.*` guard (app
`defaultAiGuardFixedThreshold`). Best per-recording BA for both heads
(a_vig 0.836, wake_light 0.834), wake warnings 25% vs 53% for p90 of cal,
Lee awake false alarms ≤ 2%, no recording missed, median latency into N1 0 s.
0.55 is the runner-up (fewer wake warnings, slightly lower BA). Band guards
keep the percentile rule.

#### `ai.a_vig`

| rule | BA W/N1 per-rec median [IQR] | BA pooled | warn W | warn N1 | Lee EO rest | Lee EC rest | Lee artifact task | Lee clean rest | latency into N1, median (p75) | missed recs |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|
| p75 of cal | 0.687 [0.594–0.735] | 0.652 | 0.61 | 0.91 | 0.32 | 0.76 | 0.06 | 0.36 | 0 s (0 s) | 0/17 |
| p90 of cal | 0.712 [0.627–0.757] | 0.681 | 0.53 | 0.89 | 0.20 | 0.64 | 0.04 | 0.24 | 0 s (0 s) | 0/17 |
| P > 0.30 | 0.698 [0.622–0.745] | 0.677 | 0.59 | 0.94 | 0.01 | 0.21 | 0.00 | 0.11 | 0 s (0 s) | 0/17 |
| P > 0.35 | 0.721 [0.679–0.801] | 0.703 | 0.51 | 0.92 | 0.00 | 0.12 | 0.00 | 0.05 | 0 s (0 s) | 0/17 |
| P > 0.40 | 0.762 [0.657–0.819] | 0.731 | 0.42 | 0.89 | 0.00 | 0.06 | 0.00 | 0.02 | 0 s (0 s) | 0/17 |
| P > 0.45 | 0.799 [0.665–0.834] | 0.759 | 0.33 | 0.85 | 0.00 | 0.03 | 0.00 | 0.01 | 0 s (0 s) | 0/17 |
| P > 0.50 | 0.836 [0.690–0.871] | 0.772 | 0.25 | 0.79 | 0.00 | 0.02 | 0.00 | 0.01 | 0 s (0 s) | 0/17 |
| P > 0.55 | 0.802 [0.702–0.859] | 0.765 | 0.17 | 0.71 | 0.00 | 0.02 | 0.00 | 0.01 | 0 s (2 s) | 0/17 |
| P > 0.60 | 0.745 [0.707–0.845] | 0.740 | 0.11 | 0.59 | 0.00 | 0.02 | 0.00 | 0.01 | 2 s (20 s) | 0/17 |
| P > 0.65 | 0.738 [0.638–0.788] | 0.695 | 0.06 | 0.45 | 0.00 | 0.02 | 0.00 | 0.01 | 7 s (28 s) | 0/17 |
| P > 0.70 | 0.650 [0.557–0.713] | 0.632 | 0.02 | 0.29 | 0.00 | 0.02 | 0.00 | 0.01 | 28 s (174 s) | 0/17 |
| P > 0.75 | 0.557 [0.511–0.626] | 0.560 | 0.00 | 0.12 | 0.00 | 0.02 | 0.00 | 0.01 | 134 s (242 s) | 0/17 |
| P > 0.80 | 0.504 [0.500–0.508] | 0.511 | 0.00 | 0.02 | 0.00 | 0.02 | 0.00 | 0.01 | 302 s (1121 s) | 5/17 |

#### `ai.wake_light`

| rule | BA W/N1 per-rec median [IQR] | BA pooled | warn W | warn N1 | Lee EO rest | Lee EC rest | Lee artifact task | Lee clean rest | latency into N1, median (p75) | missed recs |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|
| p75 of cal | 0.699 [0.611–0.724] | 0.657 | 0.61 | 0.93 | 0.32 | 0.76 | 0.06 | 0.36 | 0 s (0 s) | 0/17 |
| p90 of cal | 0.727 [0.644–0.771] | 0.694 | 0.52 | 0.91 | 0.18 | 0.62 | 0.03 | 0.23 | 0 s (0 s) | 0/17 |
| P > 0.30 | 0.738 [0.633–0.800] | 0.702 | 0.54 | 0.94 | 0.01 | 0.15 | 0.00 | 0.08 | 0 s (0 s) | 0/17 |
| P > 0.35 | 0.747 [0.701–0.816] | 0.726 | 0.46 | 0.91 | 0.00 | 0.08 | 0.00 | 0.04 | 0 s (0 s) | 0/17 |
| P > 0.40 | 0.786 [0.697–0.829] | 0.751 | 0.38 | 0.88 | 0.00 | 0.05 | 0.00 | 0.02 | 0 s (0 s) | 0/17 |
| P > 0.45 | 0.818 [0.672–0.863] | 0.772 | 0.30 | 0.84 | 0.00 | 0.03 | 0.00 | 0.01 | 0 s (0 s) | 0/17 |
| P > 0.50 | 0.834 [0.702–0.886] | 0.782 | 0.23 | 0.79 | 0.00 | 0.02 | 0.00 | 0.01 | 0 s (1 s) | 0/17 |
| P > 0.55 | 0.824 [0.733–0.862] | 0.775 | 0.17 | 0.72 | 0.00 | 0.02 | 0.00 | 0.01 | 0 s (2 s) | 0/17 |
| P > 0.60 | 0.753 [0.722–0.855] | 0.754 | 0.11 | 0.62 | 0.00 | 0.02 | 0.00 | 0.01 | 2 s (12 s) | 0/17 |
| P > 0.65 | 0.753 [0.669–0.818] | 0.718 | 0.06 | 0.50 | 0.00 | 0.02 | 0.00 | 0.01 | 2 s (20 s) | 0/17 |
| P > 0.70 | 0.701 [0.589–0.749] | 0.666 | 0.03 | 0.36 | 0.00 | 0.02 | 0.00 | 0.01 | 18 s (46 s) | 0/17 |
| P > 0.75 | 0.605 [0.539–0.668] | 0.598 | 0.01 | 0.20 | 0.00 | 0.01 | 0.00 | 0.01 | 28 s (174 s) | 0/17 |
| P > 0.80 | 0.525 [0.507–0.574] | 0.535 | 0.00 | 0.07 | 0.00 | 0.01 | 0.00 | 0.00 | 134 s (270 s) | 0/17 |
