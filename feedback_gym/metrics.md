# feedback_gym metrics

Define metrics **before** any performance claims. Living scores live in
`PROTOCOL_STATS.md` and `ui/`; this file is the contract.

## Sample clock

All scorers operate at **1 Hz** (one decision sample per second), matching the
app's reward / guard feature tick.

## Metric table

| ID | Applies | Meaning | Range |
|----|---------|---------|-------|
| `hit_rate` | reward / protocol | Fraction of 1 Hz samples that are in-target after the inhibit AND-gate | 0–1 |
| `inhibit_block` | each inhibit | Share of otherwise-in-target samples blocked by that inhibit | 0–1 |
| `warn_feature` | guard | Feature vs percentile threshold only (no delta rail) | 0–1 binary |
| `warn_rail` | guard | Absolute delta-ceiling fires (`delta > 0.25`; band also `feat > 0.25`) | 0–1 binary |
| `warn` | guard | Combined `warn_feature | warn_rail` (app fidelity) | 0–1 binary |
| `warn_rate` / `warn_feature_rate` / `rail_rate` | guard | Means of the three warn masks | 0–1 |
| `label_align` | when labels exist | Align of **`warn_feature`** (not combined) vs labels — used for scoring | 0–1 |
| `stability` | reward & guard | `1 - flip_rate` of binary decisions sample-to-sample | 0–1 |
| `sep` | feature alone | Direction-invariant class separation max(AUC, 1-AUC) when labels exist | 0–1 |
| `latency` | feature | Documented expected latency (metadata; not measured here) | text |
| `best_p` | feature | Percentile with best primary metric in the sweep | 50–95 |

### label_align (detail)

Given binary labels `drowsy=1` / `wake=0` (Sleep-EDF: hypnagogic=1) and binary
**`warn_feature`** (percentile threshold only — **not** the delta rail):

```
label_align = 0.5 * TPR + 0.5 * (1 - FPR)
```

where `TPR = TP / (TP+FN)`, `FPR = FP / (FP+TN)`. Missing labels → metric is
`null` (shown as N/A).

**Why not combined `warn`?** On Sleep-EDF, absolute `delta_abs` is often ≫ 0.25
µV²-scale, so the delta rail is near always-on → combined `label_align≈0.5` even
when the continuous feature separates well (`sep≈0.85`). Scoring on
`warn_feature` recovers threshold quality; combined `warn_rate` / `rail_rate`
remain reported for app fidelity.

### stability (detail)

```
flip_rate = mean( decision[t] != decision[t-1] ) for t in 1..N-1
stability = 1 - flip_rate
```

### sep (detail)

Direction-invariant class separation: max(AUC, 1-AUC) of the continuous feature against binary labels. Tie / single-class →
`null`.

## Protocol composite (v1)

Weights (editable in `sweeps/grids.yaml` → `protocol_rollup`):

| Part | Weight | Primary | Notes |
|------|--------|---------|-------|
| reward | 0.50 | `0.7*hit_rate + 0.3*stability` | Missing reward lane → weight redistributed |
| guard | 0.30 | `label_align(warn_feature)` if labels else softened `warn_rate_health` | Softened fallback peaks at 0.15 within [0.01, 0.55]; part breakdown also reports combined `warn_rate` + `rail_rate` |
| inhibit | 0.20 | mean health over inhibits | Health = `1 - 2*|inhibit_block - 0.25|` clipped to 0; empty inhibit → 1.0 |

**Final** = weighted mean of available parts (weights renormalized if a part is
absent, e.g. `recordOnly`).

Inhibit health penalizes blocking ~everything (`inhibit_block≈1`) or ~nothing
when the protocol declares an inhibit (`inhibit_block≈0`). Target band ≈ 0.25.


## Feature guard score (standalone board)

When `usableFor` includes guard (and that is the sweep role):

```
score = sep_weight * sep + label_align_weight * best_label_align(warn_feature)
```

Defaults (`sweeps/grids.yaml` → `protocol_rollup.guard`): **0.6 / 0.4**.
`best_p` maximizes `label_align(warn_feature)` (or softened feature warn-rate
health when labels are absent). Combined warn / rail rates are still in each
sweep row.

## Dart lane mirror (approximations)

| App | Gym |
|-----|-----|
| `RatioEngine` threshold = sorted baseline at `round(p/100*(n-1))`; `inTarget = value > t` | Same |
| Inhibit AND-gate on relative β/δ from live bands | Same; relative bands come from corpus columns |
| Guard `percentileWarn`: band → `feat > t \|\| feat > 0.25 \|\| delta > 0.25`; AI → `score > t \|\| delta > 0.25` | Same combined; gym **scores** on feature-only warn |
| Dynamic EMA adapt / dirty pads / chime cooldown | **Not simulated** (offline fixed threshold) |
| AI pack forward (CBraMod/REVE) | Uses **precomputed** fixture columns when present |
| Crown `device.*` | Corpus N/A — scored as unavailable |

Default catalog percentiles used when a protocol does not override: reward
**p40** (`defaultBaselinePercentile`), guard warn **p75**
(`defaultWarningThresholdPercentile`).
