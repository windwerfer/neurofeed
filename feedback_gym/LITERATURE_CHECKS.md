# Literature checks (gym, gated by default)

Runner: `runners/literature_checks.py` (salvaged). Each check = one graded literature claim turned into a within-recording contrast with the direction fixed before scoring. Last run 2026-10-12 15:36 ICT, `results/20261012T083611Z_litcheck`: 61 confirmed, 6 contradicted, 71 null, 49 weak, 14 effect (no prior), 62 untestable (ds003969 not built; UNIVERSE HRV columns absent).

## Headlines
- **Sleep-EDF stages (101 nights)**: posterior Pz-Oz confirms the textbook picture (alpha drop, theta rise AUC 0.83, entropy/SEF95/aperiodic slope fall, sigma in N2 via local/log sigma, delta highest in N3). On the frontal **Fpz-Cz (Muse-like) site, the alpha-share drop at sleep onset is contradicted** (AUC 0.69 the wrong way; low-EOG subset too), and only log-alpha power drops (0.21). Theta rise (0.73), slopes, SEF95 (N2) and TAB hold frontally. This is why alpha-based band guards misbehave on Muse.
- **Lee 2026 EO/EC**: eyes-closed alpha / ATR rise confirmed at AF and TP, gated and ungated (AF 0.75-0.78, TP 0.91-0.95).
- **Lee 2026 artifacts**: blinks and head turns inflate delta (AUC 0.90-0.96), jaw raises gamma: confirmed; delta-based rails will fire on artifacts.
- **ds001787 (mind wandering)**: "delta/theta rise during mind wandering" **contradicted** at AF7 and F5/F6 (0.47-0.48); novices' alpha drop in MW weakly confirmed (0.45); self-rated tiredness (Q3 ≥2) separates (0.63).
- **UNIVERSE stress**: all band claims null/weak.

Full table: results dir above (`litcheck_tables.md`).
