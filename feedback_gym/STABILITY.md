# Band stability (phase 4, 2026-10-12)

Runner: `runners/stability_round.py` → `results/20261012T084433Z_stability`. Gated (app-matching). Per thought-probe epoch (pre-probe rows) we take each band feature's SD and MASD (mean |successive diff|) and level (mean), then per-recording AUC MW vs on-task (sign test across recordings), drowsy vs alert, and novice vs expert/meditator (recording medians, permutation p). Corpora: ds001787 (Muse-proxy AF7/AF8/TP9/TP10 and Crown-site variants, 24 subjects, expert vs novice meditators), Rodriguez-Larios 2021 (OSF 3uszv, Muse-proxy, 58 recordings, meditator vs novice).

## Results
- **Variability does not track mind wandering.** No SD/MASD measure clears 0.5 consistently: on RL2021 (n=56 recordings) every variability AUC is in 0.47-0.54, p≥0.14. On ds001787 the only significant one is theta MASD going the *wrong* way (lower in MW, 0.39-0.40, p=0.006 Muse / 0.03 Crown), and it does not replicate on RL2021 (0.50).
- **Band level does slightly better on ds001787 only**: MW has lower relative alpha (0.36, p=0.02) and theta (0.36-0.38, p≈0.01) and lower beta (Crown 0.41). It does not replicate on RL2021 (0.46-0.53).
- **Drowsiness self-rating**: only RL2021 mean relative theta (0.67, p=0.03, n=21) and ds001787 TAR MASD (0.61, p=0.04, n=10); small n, treat as hints.
- **Expert vs novice (ds001787)**: novices show more beta and BTR variability (beta MASD AUC 0.77, p=0.003; SD 0.73, p=0.01) and higher beta level (0.80) / lower delta (0.19), which looks like muscle tension/EMG rather than an attention marker. Not seen in RL2021 meditators vs novices (all ≈0.5).

## Verdict
Band stability is **not** a usable attention / mind-wandering signal on a Muse-like montage; don't build a reward lane on it. The only reproducible group effect (novice beta variability) is most likely EMG. Untested: the movement gate's effect (no IMU in any corpus).

## App protocol `bandStability` (2026-10-12, experimental self-test)

Despite the verdict above, the app ships an **experimental** `bandStability` protocol at the user's request, framed as a self-test with no evidence (catalog copy says so). Note that the analysis above tested within-epoch variability against mind-wandering; the app's lane instead rewards CV *below one's own calibration baseline*, which was not tested here either way. Gym mirror: `simulate_protocol(..., "bandStability", stability_band=, stability_window=, stability_difficulty=)` (grids.yaml defaults `stability_window_seconds` 10, `stability_difficulty` 0.10; helpers `rolling_cvs` / `stability_ratio_rows`). Gym uses a fixed threshold (no adaptive steps) and no guard hold-back. Tests: `tests/test_band_stability.py`.
