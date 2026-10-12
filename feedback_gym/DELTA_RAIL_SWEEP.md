# δ rail: absolute → relative frontal delta (2026-10)

Runner: `runners/delta_rail_sweep.py`. The old rail (absolute frontal δ µV²
> 0.25) fired on 100 % of rows in every corpus. The app now rails on relative
δ (δ ÷ total band power) of AF7/AF8 behind the pad-quality gate (pads with
quality ≥ 80; the pad-mixing round found TP pads and mixes no better). Warn
while rel δ > ceiling.

Sleep-EDF: fair per-recording cal, cal rows not scored, `app_delta_rel`
(Fpz-Cz, app band math; not Muse, no pad gate). Lee 2026 Muse 2 (awake only,
so every warning is a false alarm): AF7/AF8 gated relative δ.

**Result: relative frontal δ does not separate wake from N1.** BA is below
0.5 at every ceiling (it is higher in wake: blinks / eye movement), matching
the fair round (`FAIR_BANDMATH.md`: per-rec AUC 0.39 in the sleep
direction). The rail can only be a low-false-alarm safety net.

**Chosen ceiling: 0.80** (app `guardrailDeltaCeiling`, gym
`guardrail_delta_rel_ceiling`): ≤ 1 % false alarms on Lee awake rest, 4 % in
the cued-artifact task, 12 % of Sleep-EDF wake rows. Because it performs
badly, the protocol builder now defaults `deltaRail` to **false** for new user
programs (catalog rows were already off). Candidate for removal if the
upcoming gym improvements do not rescue it.

Lee AF gate coverage: EO/EC 0.94, artifacts 0.86. Old absolute rail (delta_abs > 0.25) on Sleep-EDF play rows: 1.00.

| ceiling (rel δ) | Sleep-EDF BA W/N1 per-rec median | warn W | warn N1 | Lee EO rest | Lee EC rest | Lee clean rest | Lee artifact task |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0.30 | 0.480 | 0.65 | 0.71 | 0.50 | 0.46 | 0.42 | 0.68 |
| 0.35 | 0.455 | 0.59 | 0.62 | 0.43 | 0.35 | 0.33 | 0.61 |
| 0.40 | 0.435 | 0.53 | 0.54 | 0.36 | 0.27 | 0.26 | 0.54 |
| 0.45 | 0.421 | 0.47 | 0.45 | 0.30 | 0.21 | 0.20 | 0.47 |
| 0.50 | 0.403 | 0.42 | 0.38 | 0.24 | 0.15 | 0.15 | 0.40 |
| 0.55 | 0.385 | 0.37 | 0.30 | 0.19 | 0.11 | 0.11 | 0.33 |
| 0.60 | 0.403 | 0.32 | 0.23 | 0.13 | 0.07 | 0.08 | 0.25 |
| 0.65 | 0.401 | 0.27 | 0.17 | 0.09 | 0.05 | 0.05 | 0.19 |
| 0.70 | 0.414 | 0.22 | 0.12 | 0.05 | 0.03 | 0.03 | 0.13 |
| 0.75 | 0.441 | 0.17 | 0.08 | 0.02 | 0.01 | 0.02 | 0.08 |
| 0.80 | 0.465 | 0.12 | 0.04 | 0.01 | 0.01 | 0.01 | 0.04 |
| 0.85 | 0.479 | 0.07 | 0.02 | 0.00 | 0.00 | 0.00 | 0.01 |
| 0.90 | 0.492 | 0.03 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |


## Decision (2026-10-12): rail removed

windwerfer's rule was to remove relative δ if it was still bad after the gym improvements. Gated results: AUC 0.55 BOAS, 0.36 Muse Sleep-Onset (FAIR_BANDMATH.md). The δ rail is removed from the app (`GuardLane` warns on its threshold rule only; new frames carry no `ceilingOver` / `railDeltaRel`; old sessions still render their ceiling pane in history) and from the gym (`helpers.percentile_warn_over` = feature > threshold; no `rail_rate` / `delta_rail` fields). This runner stays as the evidence record.
