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
| `warn_rate` | guard | Share of samples over `percentileWarn` (plus absolute delta rail when applicable) | 0–1 |
| `label_align` | when labels exist | Warn TP rate vs false-alarm balance on sleep/drowsy labels (see below) | 0–1 |
| `stability` | reward & guard | `1 - flip_rate` of binary decisions sample-to-sample | 0–1 |
| `sep` | feature alone | Direction-invariant class separation max(AUC, 1-AUC) when labels exist | 0–1 |
| `latency` | feature | Documented expected latency (metadata; not measured here) | text |
| `best_p` | feature | Percentile with best primary metric in the sweep | 50–95 |

### label_align (detail)

Given binary labels `drowsy=1` / `wake=0` and binary `warn`:

```
label_align = 0.5 * TPR + 0.5 * (1 - FPR)
```

where `TPR = TP / (TP+FN)`, `FPR = FP / (FP+TN)`. Missing labels → metric is
`null` (shown as N/A).

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
| guard | 0.30 | `label_align` if present else calibrated `warn_rate` health | Calibrated warn: peak at 0.15, falls to 0 outside [0.02, 0.40] |
| inhibit | 0.20 | mean health over inhibits | Health = `1 - 2*|inhibit_block - 0.25|` clipped to 0; empty inhibit → 1.0 |

**Final** = weighted mean of available parts (weights renormalized if a part is
absent, e.g. `recordOnly`).

Inhibit health penalizes blocking ~everything (`inhibit_block≈1`) or ~nothing
when the protocol declares an inhibit (`inhibit_block≈0`). Target band ≈ 0.25.

## Dart lane mirror (approximations)

| App | Gym |
|-----|-----|
| `RatioEngine` threshold = sorted baseline at `round(p/100*(n-1))`; `inTarget = value > t` | Same |
| Inhibit AND-gate on relative β/δ from live bands | Same; relative bands come from corpus columns |
| Guard `percentileWarn`: band → `delta > t \|\| delta > 0.25`; AI → `score > t \|\| delta > 0.25` | Same (`guardrailDeltaCeiling = 0.25`) |
| Dynamic EMA adapt / dirty pads / chime cooldown | **Not simulated** (offline fixed threshold) |
| AI pack forward (CBraMod/REVE) | Uses **precomputed** fixture columns when present |
| Crown `device.*` | Corpus N/A — scored as unavailable |

Default catalog percentiles used when a protocol does not override: reward
**p40** (`defaultBaselinePercentile`), guard warn **p75**
(`defaultWarningThresholdPercentile`).
