# FAIR_BANDMATH

_Generated 2026-10-07 by `runners/fair_round.py` (branch `feat/gym-fair-bandmath`). Aggregates only; no data, windows or per-recording rows._

> Short answer to "were all our gym tests done with fair band math?": **no.** Sleep-EDF, the corpus behind every sleep claim, scored all 20 recordings against one 45 s baseline from the first recording (SC4001). Every feature was swept in one direction only. The board's `sep` folded the direction away, and the "reward" numbers measured playability, not validity. Earlier fixes covered only the sleep guard and delta: the guard default moved from `band.delta` to `ai.a_vig`, and `deltaRail` was turned off in the catalog. They did nothing for ATR / TAR / BTR / alpha. This round re-scores **all 8 band features on all 4 corpora** with per-recording baselines and both directions.

## How to read the numbers

| number | what it is | validity or playability |
|---|---|---|
| per-rec AUC (sleep dir) | per recording: P(feature of an N1 row is further in the sleep direction than a W row); median over recordings. 0.5 = chance, < 0.5 = moves the other way | **validity** |
| pooled AUC raw / baseline-norm | same over all play rows pooled; baseline-norm first rescales each recording by its own cal block (median / IQR) | validity (pooled AUC mixes between-subject offsets; baseline-norm is unstable when a cal block is nearly constant, e.g. AI P≈0) |
| BA p90 up / down | app-style `percentileWarn` against each recording's own baseline: warn when value > p90 (up) or < p10 (down); balanced accuracy vs labels | **validity** of the guard as the app would run it |
| warn p90 on 0 / 1 | warn rate on label-0 / label-1 rows | false-alarm load / hit rate |
| old `sep` | pooled AUC folded to max(auc, 1-auc), so the direction is gone | validity without a direction |
| reward `hit`, `rew` (= 0.7·hit + 0.3·stability), protocol `final` | how often the reward fires and how steady it is | **playability only**. Says nothing about whether the feature tracks the claimed state |

Sleep direction is the physiological prior, fixed **before** scoring (sleep onset W→N1: alpha drops out, theta rises, beta falls, slow activity rises): up = TAR, (θ+α)/β, rel θ, rel δ, abs δ, AI; down = alpha share, ATR, BTR. "data" shows which way the per-recording median actually went. Both directions are always reported: per-rec AUC(down) = 1 − AUC(up).

Gym-only features, derived from the corpus relative bands (no app change): `gym.tab` = (θ+α)/β, `gym.theta_rel`, `gym.delta_rel`. `band.delta` is absolute δ (µV²), as in the app.

## Audit

| # | issue | affected features / corpora | fixed before? | fixed now? |
|---|---|---|---|---|
| 1 | **Global baseline on Sleep-EDF.** `sleep_edf_test.npz` had no `cal_starts`/`cal_lens`, so every row of 20 recordings was thresholded against the first 90 rows (45 s of SC4001). Lee and UNIVERSE already used per-recording cal. | every feature and protocol part on `sleep-edf-test`. Example: TAR "reward 0.18" vs ATR 0.82 was hit rate against SC4001's baseline (fair: 0.36 vs 0.65). TAR = 1/ATR, so their hit rates are near-complements and their AUCs are identical | **No.** The gym could do per-recording cal (multi-corpus branch), but the Sleep-EDF builder never emitted it | **Yes.** The builder now defaults to `--cal-mode per-recording`: each recording's leading wake run, ≤90 rows (45 s at the 0.5 s hop, the app's single-baseline length), cal rows never scored. 17/20 recordings scored. ST7161 / ST7201 / ST7241 start in N1 and have no wake baseline, so they are not scored. `--cal-mode global` reproduces the old corpus, and `--from-npz` post-processes an old NPZ. The rebuild reproduces every old column bit-for-bit |
| 2 | **Direction.** Reward sweeps assume higher = better (`percentileUptrain`) and guard sweeps assume higher = warn. `sep` is folded, so the board never shows which way a feature moves. | all band features, all corpora. ATR / BTR / alpha can only be sleep guards in the **down** direction. Frontal rel δ / abs δ move the *opposite* way to the prior on Sleep-EDF | No | **In the fair round, yes:** both directions, directional AUC. The standard board now also reports `auc_up` next to `sep`. **Not in the app:** `percentileWarn` can only warn upward, so a "warn when ATR / BTR / alpha drops" guard needs a new policy (open decision) |
| 3 | **Reward score ≠ validity.** Protocol `final` = 0.5·(0.7·hit + 0.3·stability) + 0.3·guard label-align + 0.2·inhibit health. Claims like "α best reward score" or "alertOpen strongest composite" rest on hit rate | every protocol with a reward lane | No (the docs said "score", which read as evidence) | **Documented here;** validity is reported separately (per-rec AUC, BA). `PROTOCOL_STATS.md` still shows only the composite (open) |
| 4 | **Absolute vs relative.** `band.delta` and the δ rail use absolute power in µV². The 0.25 ceiling sits orders of magnitude below real values (median 7–20 µV², gym math; larger with app math): the rail fires on **100 %** of rows in all 4 corpora. The gym band-guard path also rails `feat > 0.25` on the feature itself. Relative ceilings (`betaCeiling 0.25` on relative β) have sane units, but their block rate depends on band edges and data: relative β > 0.25 on 20 % (gym math) / 24 % (app math) of Sleep-EDF rows and 35–43 % of Muse rows | `band.delta` guard, δ rail (every protocol with `deltaRail` true), `concentrate` inhibit | Partly: the protocols-evidence catalog sets `guard.deltaRail: false` on every catalog guard. The app comment admits the unit mismatch. The rail still defaults to **true** for user protocols, and main's catalog still rails | **No code change** (app). Quantified here. Units are the open decision |
| 5 | **No artifact gating** in the gym (the app gates dirty samples). **Electrode mismatch:** Sleep-EDF Fpz-Cz / Pz-Oz are copied into AF7=AF8 / TP9=TP10. Band features read only AF7/AF8 (= Fpz-Cz, bipolar), while the AI sees both. Sleep-EDF EEG is sampled at 100 Hz, so nothing above 50 Hz (gamma, and therefore relative shares) is Muse-like | all band features on Sleep-EDF; all sleep-direction guards on Muse data | No | **Quantified, not fixable with this data.** Lee artifacts: 7 of 8 band sleep guards fire 3–5× more often on artifact rows (p90: 0.39–0.60 vs 0.12–0.15 clean); relative θ is the exception. Frontal abs δ is mostly an ocular / artifact detector (AUC 0.91 on artifacts, 0.33 on sleep onset). The posterior proxy (Pz-Oz) lifts band sleep AUCs by +0.04…+0.37 (variant table). Muse TP9/TP10 are not Pz-Oz, so this is an upper bound |
| 6 | **Leakage / home field.** | `ai.*` on Sleep-EDF | n/a | **No leakage:** the 20 gym recordings are the heads' subject-held-out **test** split (0 recordings / 0 subjects shared with train or val; `muse-eeg-heads` `vigilance_sleep_edf/splits`, `head_*_full_corpus/metrics_summary.json`). Checkpoints were picked on val. **Home field: yes.** The heads were trained on the same dataset, the same W-vs-N1 labels, the same proxy montage and the same 2 s windows, and their test F1 was used for the ship decision. Band math is untuned. Expect the AI to lose some of its margin on real Muse data |
| 7a | **Stale band math.** Every corpus (this builder and the Lee / UNIVERSE builders) uses `muse-eeg-heads/band_math/features/flutter_bands.py`: rectangular window, inclusive bins (4/8/13/30 Hz counted twice), gamma 30–50. The app since 2026-09-28: Hamming, PSD, `[lo,hi)`, gamma 30–45 | all band features, all corpora | No | Ported the app math gym-only (`runners/app_bands.py`) and added it as Sleep-EDF `app_*` columns. Per-rec AUCs move ≤ 0.02, so **conclusions unchanged.** The shared builder is not updated (lives in muse-eeg-heads) |
| 7b | **Label naming.** Sleep-EDF `drowsy` / `hypnagogic` are literally R&K stage **W vs N1** (30 s epochs) in a slice from 20 min before to 40 min after the first N1, with N2+ dropped. "drowsy" is all wake, including alert wake | Sleep-EDF claims | No | Documented |
| 7c | **Row rate.** Sleep-EDF windows hop 0.5 s (2 rows/s), while metrics.md says 1 Hz. Lee / UNIVERSE hop 1 s, so stability / flip metrics are not comparable across corpora | stability, cal length | No | Documented. Cal = 90 rows = 45 s |
| 7d | **In-sample percentile choice.** `best_p` / best BA are picked on the scored rows | all features equally (optimistic) | No | Fixed p90 reported next to best |
| 7e | **AI guard policy.** With a 45 s early-wake baseline, AI P(N1) can sit near 0 (one recording's cal median is 0.000), so the p90 percentile fires on **53 %** of later wake rows. BA 0.68, against per-rec AUC 0.91. A fixed P > 0.5 gives BA 0.79 (warn 25 % W / 82 % N1) | `sleepGuard` and every `ai.a_vig` guard | No | Reported; open decision |
| 7f | **REVE columns** are a class-balanced subsample (3 179 of 61 736 rows) | `ai.*_reve` | flagged before | Excluded from the fair tables |
| 7g | **Merge conflict:** `feat/gym-multi-corpus` and `feat/protocols-evidence` both edit `feedback_gym/runners/simulate_protocol.py` | gym | — | Not touched here; resolve when merging |

## Fair round: sleep onset (Sleep-EDF, W vs N1, per-recording wake baseline, 17 recordings)

| feature | sleep dir prior / data | per-rec AUC sleep dir, median [IQR] | recs > 0.5 | BA p90 up / down | Δ vs ai.a_vig (median, recs ≥ AI) | posterior-proxy per-rec AUC |
|---|---|---|---:|---|---|---:|
| TAR θ/α | up / up | 0.603 [0.485–0.691] | 12/17 | 0.536 / 0.441 | −0.324, 0/17 | 0.825 |
| (θ+α)/β | up / up | 0.601 [0.489–0.643] | 12/17 | 0.539 / 0.457 | −0.304, 0/17 | 0.643 |
| alpha share | down / **up** | 0.447 [0.331–0.578] | 6/17 | 0.550 / 0.501 | −0.455, 0/17 | 0.728 |
| ATR α/θ | down / down | 0.603 [0.485–0.691] | 12/17 | 0.441 / 0.536 | −0.324, 0/17 | 0.825 |
| BTR β/θ | down / down | 0.636 [0.479–0.675] | 12/17 | 0.451 / 0.541 | −0.305, 0/17 | 0.828 |
| relative θ | up / up | **0.748** [0.657–0.795] | 16/17 | **0.632** / 0.462 | −0.152, 0/17 | 0.803 |
| relative δ | up / **down** | 0.391 [0.299–0.619] | 6/17 | 0.492 / 0.546 | −0.518, 0/17 | 0.764 |
| absolute δ (µV²) | up / **down** | 0.328 [0.259–0.542] | 5/17 | 0.499 / 0.516 | −0.564, 0/17 | 0.654 |
| **ai.a_vig** | up / up | **0.911** [0.842–0.936] | 17/17 | 0.681 / 0.433 | — | — |
| ai.wake_light | up / up | 0.913 [0.852–0.937] | 17/17 | 0.694 / 0.434 | +0.004, 15/17 | — |

**Does band math get close to the AI for sleep onset? No.** On the Muse-like frontal derivation, the best band feature is relative θ (per-rec AUC 0.75, BA 0.63). It is 0.15 behind `ai.a_vig` and beats the AI in 0/17 recordings. TAR, ATR, BTR and (θ+α)/β sit near 0.60. Frontal alpha share, rel δ and abs δ are at or below chance in the sleep direction: on Fpz-Cz, wake carries blinks and eye movements, so slow power is *higher* in W. The app's own band math changes nothing (≤ 0.02). Only the posterior derivation (Pz-Oz, which a Muse does not have) brings TAR / ATR / BTR to ~0.83, still 0.08 behind the AI per recording (≥ AI in 3–5/17). Caveat: home field (audit 6).

## Same treatment on awake-only corpora (would a sleep guard fire with no sleep?)

Sleep-direction guard, p90 of each recording's own baseline: warn rate on label 0 / label 1.

| feature | Lee EO→EC (EO base, 25 subj): per-rec AUC up · warn EO / EC | Lee artifacts (102 rec): per-rec AUC up · warn clean / artifact | UNIVERSE relax→stress (46 sessions): per-rec AUC up · warn relax / stress |
|---|---|---|---|
| TAR | 0.327 · 0.12 / 0.05 | 0.687 · 0.12 / 0.39 | 0.484 · 0.13 / 0.12 |
| (θ+α)/β | 0.426 · 0.18 / 0.18 | 0.743 · 0.14 / 0.44 | 0.487 · 0.13 / 0.12 |
| alpha share | 0.785 · 0.16 / 0.06 | 0.195 · 0.15 / 0.55 | 0.507 · 0.17 / 0.16 |
| ATR | 0.673 · 0.12 / 0.05 | 0.313 · 0.12 / 0.39 | 0.516 · 0.13 / 0.12 |
| BTR | 0.579 · 0.17 / 0.15 | 0.294 · 0.14 / 0.43 | 0.523 · 0.12 / 0.11 |
| relative θ | 0.370 · 0.16 / 0.11 | 0.379 · 0.14 / 0.14 | 0.496 · 0.15 / 0.14 |
| relative δ | 0.368 · 0.17 / 0.17 | 0.846 · 0.14 / 0.52 | 0.479 · 0.12 / 0.11 |
| absolute δ | 0.340 · 0.15 / 0.15 | 0.909 · 0.13 / 0.60 | 0.483 · 0.11 / 0.11 |

(AUC "up" = feature higher for label 1. Lee and UNIVERSE have no AI columns.)

- Eye closure does **not** trip band sleep guards: in their sleep direction, TAR / ATR / alpha move the "awake" way when the eyes close.
- Artifacts **do** trip them: 3–5× for every feature except relative θ, and the gym has no gating. In the app the dirty-sample gate should absorb part of this; it is not simulated.
- Stress / load: every band feature is at chance (as before), and the guards stay near the nominal 10–15 %.

## Protocol evidence under fair scoring

The catalog is `feat/protocols-evidence` after Part 1 (recordOnly removed). Playability = gym `simulate_protocol` (reward hit · composite), old global baseline → per-recording. Validity = per-rec AUC of the reward feature in the protocol's claimed direction.

| protocol | recipe | playability old → fair (Sleep-EDF) | validity (fair) | what changed |
|---|---|---|---|---|
| sleepGuard | guard `ai.a_vig` | guard LA p75 0.634 → 0.652 | a_vig per-rec AUC **0.91** (17/17); band best 0.75 | **Stronger** for AI over band. The old "δ-as-guard 0.43" undersold the problem: frontal δ points the *wrong way* and is an artifact detector. New caveat: a percentile-of-45-s-baseline guard over-fires on later wake (p90: 53 % of W rows); a fixed P > 0.5 does better (BA 0.79) |
| restAwake | reward ATR + guard a_vig (muffle) | hit 0.855 → 0.702 · final 0.823 → 0.767 | ATR higher in W than N1: 0.603 (12/17); higher EC than EO 0.673; falls with artifacts 0.687 | **Weaker than written:** "ATR reward OK" was playability. Validity is modest; the AI guard does the sleep work |
| openMonitor | reward alpha share + guard | hit 0.879 → 0.743 · final 0.836 → 0.791 | frontal alpha share does **not** fall toward N1 (0.447, 6/17); tracks EC (0.785); falls with artifacts (0.805) | **Changed:** "α best reward score" was hit rate. Frontal alpha share is not a sleep-onset or vigilance marker; it is an eyes-closed / relaxation marker |
| alertOpen | reward BTR, no guard | hit 0.800 → 0.708 · final 0.880 → 0.829 | BTR higher in W than N1: 0.636 (12/17); UNIVERSE load 0.523 (chance); EC vs EO 0.579 (higher with eyes closed) | **Changed:** "strongest gym composite" was playability. Alertness validity is modest, and nothing here shows BTR tracks eyes-open task alertness |
| alertClosed | reward BTR + guard a_vig | hit 0.800 → 0.708 · final 0.806 → 0.776 | as alertOpen (BTR); guard as sleepGuard | same as alertOpen; the guard carries the sleep claim |
| concentrate | reward alpha + `betaCeiling 0.25` (+ optional guard) | hit 0.675 → 0.585 · inhibit 0.963 → 0.926; Muse corpora inhibit 0.53–0.63 | alpha as above; no attention corpus scored | Inhibit health drops on real Muse data: relative β > 0.25 on 35–43 % of rows, so the ceiling blocks far more than the 25 % target. "Focus" is still unbacked |
| calibrateRecord | no lanes | N/A | N/A | none |
| (dropped `twilight`, TAR reward) | — | TAR hit 0.18 → 0.36 | TAR as a sleep **guard** (up) 0.60 frontal / 0.83 posterior | The 0.18 was the SC4001 baseline. TAR is a weak frontal sleep guard, not a reward. The drop still stands |

## Open decisions

1. **Guard direction in the app:** add a downward `percentileWarn` (warn when ATR / BTR / alpha falls), or keep band guards upward-only (TAR, rel θ)? Relative θ is the only frontal band feature with usable sleep validity (0.75).
2. **δ units:** the 0.25 µV² rail fires on 100 % of rows. Either drop the rail, re-express it as relative δ, or re-derive an absolute ceiling per device. Frontal δ mostly tracks blinks and eye movement, so as a sleep rail it is the wrong signal on Muse.
3. **AI guard threshold:** keep percentile-of-baseline (over-fires when the baseline is very awake), use a fixed probability (0.5–0.6), or take the baseline later / longer.
4. **Shared band math:** update `muse-eeg-heads/band_math/features/flutter_bands.py` to the app math (Hamming, `[lo,hi)`, gamma 30–45) and rebuild Lee / UNIVERSE. The effect here was ≤ 0.02, so this is low priority.
5. **Board layout:** show validity (AUC / BA) next to the playability composite in `PROTOCOL_STATS.md`, and stop reading the composite as evidence.
6. **Muse sleep data:** every sleep number here is a Sleep-EDF proxy, home-field for the AI. A labeled Muse nap / drowsiness set is the only way to settle band vs AI on the real device.
7. **Merge order:** `feat/gym-multi-corpus` (merged into this branch) conflicts with `feat/protocols-evidence` in `simulate_protocol.py`.

## Reproduce

```bash
cd feedback_gym
python3 runners/build_corpus_sleep_edf.py            # per-recording cal + app_* / post_* columns (needs ../muse-eeg-heads)
python3 runners/build_corpus_sleep_edf.py --cal-mode global --no-extra-columns \
    --out corpora/external/sleep_edf_test_global_old.npz   # the old corpus, for the old-vs-fair columns
python3 runners/fair_round.py --catalog <protocols.json>   # -> results/<ts>_fair/{fair_board.json,fair_tables.md}
```

---

## Appendix: full fair-round tables (generated)

### sleep-edf
_label 0 = W, 1 = N1 (30 s scoring); per-recording wake baseline; calibration {'mode': 'per_recording', 'n_recordings': 17, 'cal_rows': 1530, 'n_play': 56444, 'skipped': ['ST7161:no_cal_block', 'ST7201:no_cal_block', 'ST7241:no_cal_block']}_

| feature | kind | sleep dir (prior / data) | per-rec AUC, sleep dir: median [IQR] | recs > 0.5 | pooled AUC raw | pooled AUC baseline-norm | BA p90 up | BA p90 down | best BA (p) | warn p90 on 0 / 1 |
|---|---|---|---|---|---:|---:|---:|---:|---:|---|
| TAR theta/alpha | ratio | up / up | 0.603 [0.485–0.691] | 12/17 | 0.580 | 0.562 | 0.536 | 0.441 | 0.536 (p90) | 0.11 / 0.19 |
| (theta+alpha)/beta | ratio | up / up | 0.601 [0.489–0.643] | 12/17 | 0.588 | 0.579 | 0.539 | 0.457 | 0.550 (p50) | 0.13 / 0.20 |
| alpha share | relative | down / up | 0.447 [0.331–0.578] | 6/17 | 0.479 | 0.446 | 0.550 | 0.501 | 0.501 (p90) | 0.12 / 0.13 |
| ATR alpha/theta | ratio | down / down | 0.603 [0.485–0.691] | 12/17 | 0.580 | 0.559 | 0.441 | 0.536 | 0.536 (p90) | 0.11 / 0.19 |
| BTR beta/theta | ratio | down / down | 0.636 [0.479–0.675] | 12/17 | 0.606 | 0.577 | 0.451 | 0.541 | 0.554 (p50) | 0.12 / 0.20 |
| relative theta | relative | up / up | 0.748 [0.657–0.795] | 16/17 | 0.688 | 0.682 | 0.632 | 0.462 | 0.654 (p70) | 0.25 / 0.52 |
| relative delta | relative | up / down | 0.391 [0.299–0.619] | 6/17 | 0.497 | 0.453 | 0.492 | 0.546 | 0.492 (p90) | 0.13 / 0.11 |
| absolute delta (uV^2) | absolute | up / down | 0.328 [0.259–0.542] | 5/17 | 0.421 | 0.532 | 0.499 | 0.516 | 0.499 (p90) | 0.12 / 0.12 |
| AI a_vig P(N1) | ai | up / up | 0.911 [0.842–0.936] | 17/17 | 0.860 | 0.657 | 0.681 | 0.433 | 0.690 (p95) | 0.53 / 0.89 |
| AI wake_light P(light) | ai | up / up | 0.913 [0.852–0.937] | 17/17 | 0.872 | 0.660 | 0.694 | 0.434 | 0.716 (p95) | 0.52 / 0.91 |

Per-recording AUC (sleep dir) minus ai.a_vig, same recordings:

| feature | n | median diff | recs where feature >= AI |
|---|---:|---:|---:|
| TAR theta/alpha | 17 | -0.324 | 0/17 |
| (theta+alpha)/beta | 17 | -0.304 | 0/17 |
| alpha share | 17 | -0.455 | 0/17 |
| ATR alpha/theta | 17 | -0.324 | 0/17 |
| BTR beta/theta | 17 | -0.305 | 0/17 |
| relative theta | 17 | -0.152 | 0/17 |
| relative delta | 17 | -0.518 | 0/17 |
| absolute delta (uV^2) | 17 | -0.564 | 0/17 |
| AI wake_light P(light) | 17 | 0.004 | 15/17 |

Variant: app band math (Hamming, [lo,hi), gamma 30-45)

_app band math (Hamming, [lo,hi), gamma 30-45); same rows / baselines_

| feature | kind | sleep dir (prior / data) | per-rec AUC, sleep dir: median [IQR] | recs > 0.5 | pooled AUC raw | pooled AUC baseline-norm | BA p90 up | BA p90 down | best BA (p) | warn p90 on 0 / 1 |
|---|---|---|---|---|---:|---:|---:|---:|---:|---|
| TAR theta/alpha | ratio | up / up | 0.603 [0.502–0.689] | 14/17 | 0.587 | 0.565 | 0.542 | 0.442 | 0.562 (p80) | 0.14 / 0.23 |
| (theta+alpha)/beta | ratio | up / up | 0.593 [0.492–0.637] | 12/17 | 0.587 | 0.589 | 0.576 | 0.461 | 0.576 (p90) | 0.14 / 0.29 |
| alpha share | relative | down / up | 0.462 [0.337–0.577] | 6/17 | 0.480 | 0.449 | 0.545 | 0.495 | 0.496 (p85) | 0.11 / 0.10 |
| ATR alpha/theta | ratio | down / down | 0.603 [0.502–0.689] | 14/17 | 0.587 | 0.580 | 0.442 | 0.542 | 0.562 (p80) | 0.14 / 0.23 |
| BTR beta/theta | ratio | down / down | 0.639 [0.515–0.677] | 13/17 | 0.611 | 0.603 | 0.455 | 0.585 | 0.587 (p85) | 0.13 / 0.30 |
| relative theta | relative | up / up | 0.733 [0.658–0.780] | 16/17 | 0.686 | 0.691 | 0.640 | 0.458 | 0.657 (p75) | 0.23 / 0.51 |
| relative delta | relative | up / down | 0.381 [0.292–0.606] | 6/17 | 0.486 | 0.429 | 0.493 | 0.559 | 0.493 (p90) | 0.12 / 0.10 |
| absolute delta (uV^2) | absolute | up / down | 0.317 [0.276–0.543] | 5/17 | 0.417 | 0.518 | 0.497 | 0.529 | 0.497 (p90) | 0.12 / 0.11 |

| feature (variant) | median diff vs ai.a_vig | recs >= AI |
|---|---:|---:|
| TAR theta/alpha | -0.306 | 0/17 |
| (theta+alpha)/beta | -0.298 | 0/17 |
| alpha share | -0.452 | 0/17 |
| ATR alpha/theta | -0.306 | 0/17 |
| BTR beta/theta | -0.299 | 0/17 |
| relative theta | -0.163 | 0/17 |
| relative delta | -0.525 | 0/17 |
| absolute delta (uV^2) | -0.564 | 0/17 |

Variant: posterior proxy Pz-Oz (flutter_bands math)

_posterior proxy Pz-Oz (flutter_bands math); same rows / baselines_

| feature | kind | sleep dir (prior / data) | per-rec AUC, sleep dir: median [IQR] | recs > 0.5 | pooled AUC raw | pooled AUC baseline-norm | BA p90 up | BA p90 down | best BA (p) | warn p90 on 0 / 1 |
|---|---|---|---|---|---:|---:|---:|---:|---:|---|
| TAR theta/alpha | ratio | up / up | 0.825 [0.778–0.896] | 16/17 | 0.806 | 0.694 | 0.621 | 0.399 | 0.644 (p75) | 0.10 / 0.34 |
| (theta+alpha)/beta | ratio | up / up | 0.643 [0.531–0.777] | 14/17 | 0.662 | 0.629 | 0.567 | 0.436 | 0.603 (p50) | 0.26 / 0.39 |
| alpha share | relative | down / down | 0.728 [0.558–0.793] | 14/17 | 0.707 | 0.529 | 0.496 | 0.566 | 0.566 (p90) | 0.11 / 0.25 |
| ATR alpha/theta | ratio | down / down | 0.825 [0.778–0.896] | 16/17 | 0.806 | 0.690 | 0.399 | 0.621 | 0.644 (p75) | 0.10 / 0.34 |
| BTR beta/theta | ratio | down / down | 0.828 [0.778–0.849] | 16/17 | 0.787 | 0.709 | 0.429 | 0.642 | 0.656 (p80) | 0.16 / 0.44 |
| relative theta | relative | up / up | 0.803 [0.780–0.828] | 17/17 | 0.788 | 0.740 | 0.685 | 0.460 | 0.699 (p80) | 0.32 / 0.69 |
| relative delta | relative | up / up | 0.764 [0.690–0.820] | 16/17 | 0.750 | 0.567 | 0.585 | 0.459 | 0.588 (p95) | 0.11 / 0.28 |
| absolute delta (uV^2) | absolute | up / up | 0.654 [0.526–0.728] | 15/17 | 0.621 | 0.555 | 0.542 | 0.511 | 0.542 (p90) | 0.13 / 0.21 |

| feature (variant) | median diff vs ai.a_vig | recs >= AI |
|---|---:|---:|
| TAR theta/alpha | -0.081 | 5/17 |
| (theta+alpha)/beta | -0.182 | 0/17 |
| alpha share | -0.198 | 3/17 |
| ATR alpha/theta | -0.081 | 5/17 |
| BTR beta/theta | -0.077 | 3/17 |
| relative theta | -0.097 | 1/17 |
| relative delta | -0.155 | 2/17 |
| absolute delta (uV^2) | -0.240 | 0/17 |

### lee-eo-ec
_label 0 = eyes-open rest, 1 = eyes-closed rest (both awake); EO baseline; calibration {'mode': 'per_recording', 'n_recordings': 25, 'cal_rows': 750, 'n_play': 5150, 'skipped': []}_

| feature | kind | sleep dir (prior / data) | per-rec AUC, sleep dir: median [IQR] | recs > 0.5 | pooled AUC raw | pooled AUC baseline-norm | BA p90 up | BA p90 down | best BA (p) | warn p90 on 0 / 1 |
|---|---|---|---|---|---:|---:|---:|---:|---:|---|
| TAR theta/alpha | ratio | up / down | 0.327 [0.189–0.378] | 4/25 | 0.307 | 0.322 | 0.465 | 0.594 | 0.473 (p95) | 0.12 / 0.05 |
| (theta+alpha)/beta | ratio | up / down | 0.426 [0.223–0.584] | 9/25 | 0.428 | 0.423 | 0.499 | 0.556 | 0.503 (p85) | 0.18 / 0.18 |
| alpha share | relative | down / up | 0.215 [0.128–0.341] | 3/25 | 0.289 | 0.286 | 0.631 | 0.452 | 0.469 (p95) | 0.16 / 0.06 |
| ATR alpha/theta | ratio | down / up | 0.327 [0.189–0.378] | 4/25 | 0.307 | 0.321 | 0.594 | 0.465 | 0.473 (p95) | 0.12 / 0.05 |
| BTR beta/theta | ratio | down / up | 0.421 [0.208–0.555] | 11/25 | 0.418 | 0.414 | 0.552 | 0.487 | 0.487 (p85) | 0.17 / 0.15 |
| relative theta | relative | up / down | 0.370 [0.289–0.541] | 9/25 | 0.446 | 0.448 | 0.478 | 0.531 | 0.484 (p95) | 0.16 / 0.11 |
| relative delta | relative | up / down | 0.368 [0.287–0.623] | 9/25 | 0.431 | 0.435 | 0.500 | 0.537 | 0.507 (p95) | 0.17 / 0.17 |
| absolute delta (uV^2) | absolute | up / down | 0.340 [0.236–0.493] | 6/25 | 0.382 | 0.382 | 0.502 | 0.552 | 0.502 (p90) | 0.15 / 0.15 |

### lee-artifacts
_label 0 = clean rest, 1 = cued artifact task (both awake); clean-rest baseline; calibration {'mode': 'per_recording', 'n_recordings': 102, 'cal_rows': 3060, 'n_play': 14994, 'skipped': []}_

| feature | kind | sleep dir (prior / data) | per-rec AUC, sleep dir: median [IQR] | recs > 0.5 | pooled AUC raw | pooled AUC baseline-norm | BA p90 up | BA p90 down | best BA (p) | warn p90 on 0 / 1 |
|---|---|---|---|---|---:|---:|---:|---:|---:|---|
| TAR theta/alpha | ratio | up / up | 0.687 [0.536–0.852] | 86/102 | 0.684 | 0.681 | 0.636 | 0.456 | 0.643 (p80) | 0.12 / 0.39 |
| (theta+alpha)/beta | ratio | up / up | 0.743 [0.503–0.899] | 77/102 | 0.655 | 0.667 | 0.652 | 0.465 | 0.652 (p85) | 0.14 / 0.44 |
| alpha share | relative | down / down | 0.805 [0.690–0.911] | 98/102 | 0.751 | 0.759 | 0.434 | 0.697 | 0.702 (p85) | 0.15 / 0.55 |
| ATR alpha/theta | ratio | down / down | 0.687 [0.536–0.852] | 86/102 | 0.684 | 0.678 | 0.456 | 0.636 | 0.643 (p80) | 0.12 / 0.39 |
| BTR beta/theta | ratio | down / down | 0.706 [0.465–0.892] | 75/102 | 0.649 | 0.654 | 0.469 | 0.646 | 0.650 (p85) | 0.14 / 0.43 |
| relative theta | relative | up / down | 0.379 [0.276–0.550] | 30/102 | 0.423 | 0.417 | 0.502 | 0.574 | 0.509 (p95) | 0.14 / 0.14 |
| relative delta | relative | up / up | 0.846 [0.686–0.958] | 90/102 | 0.747 | 0.742 | 0.689 | 0.427 | 0.701 (p70) | 0.14 / 0.52 |
| absolute delta (uV^2) | absolute | up / up | 0.909 [0.756–0.969] | 98/102 | 0.794 | 0.810 | 0.734 | 0.403 | 0.741 (p75) | 0.13 / 0.60 |

### universe
_label 0 = relax / low load, 1 = stress / high load (both awake); relax baseline; calibration {'mode': 'per_recording', 'n_recordings': 46, 'cal_rows': 2760, 'n_play': 46030, 'skipped': []}_

| feature | kind | sleep dir (prior / data) | per-rec AUC, sleep dir: median [IQR] | recs > 0.5 | pooled AUC raw | pooled AUC baseline-norm | BA p90 up | BA p90 down | best BA (p) | warn p90 on 0 / 1 |
|---|---|---|---|---|---:|---:|---:|---:|---:|---|
| TAR theta/alpha | ratio | up / down | 0.484 [0.439–0.521] | 19/46 | 0.484 | 0.484 | 0.496 | 0.511 | 0.500 (p95) | 0.13 / 0.12 |
| (theta+alpha)/beta | ratio | up / down | 0.487 [0.396–0.572] | 21/46 | 0.487 | 0.486 | 0.497 | 0.515 | 0.499 (p95) | 0.13 / 0.12 |
| alpha share | relative | down / up | 0.493 [0.435–0.551] | 22/46 | 0.498 | 0.507 | 0.502 | 0.499 | 0.508 (p50) | 0.17 / 0.16 |
| ATR alpha/theta | ratio | down / up | 0.484 [0.439–0.521] | 19/46 | 0.484 | 0.484 | 0.511 | 0.496 | 0.500 (p95) | 0.13 / 0.12 |
| BTR beta/theta | ratio | down / up | 0.477 [0.402–0.559] | 20/46 | 0.483 | 0.479 | 0.519 | 0.496 | 0.500 (p95) | 0.12 / 0.11 |
| relative theta | relative | up / down | 0.496 [0.422–0.552] | 23/46 | 0.490 | 0.483 | 0.497 | 0.512 | 0.498 (p95) | 0.15 / 0.14 |
| relative delta | relative | up / down | 0.479 [0.423–0.552] | 19/46 | 0.480 | 0.480 | 0.497 | 0.517 | 0.501 (p95) | 0.12 / 0.11 |
| absolute delta (uV^2) | absolute | up / down | 0.483 [0.421–0.538] | 17/46 | 0.479 | 0.482 | 0.497 | 0.515 | 0.502 (p95) | 0.11 / 0.11 |

### sleep-edf: old global baseline vs per-recording baseline

| feature | old sep (direction-free, pooled) | old BA p90 sleep dir | fair BA p90 sleep dir | fair per-rec AUC sleep dir |
|---|---:|---:|---:|---:|
| TAR theta/alpha | 0.574 | 0.488 | 0.536 | 0.603 |
| (theta+alpha)/beta | 0.571 | 0.504 | 0.539 | 0.601 |
| alpha share | 0.523 | 0.463 | 0.501 | 0.447 |
| ATR alpha/theta | 0.574 | 0.488 | 0.536 | 0.603 |
| BTR beta/theta | 0.591 | 0.495 | 0.541 | 0.636 |
| relative theta | 0.679 | 0.584 | 0.632 | 0.748 |
| relative delta | 0.508 | 0.476 | 0.492 | 0.391 |
| absolute delta (uV^2) | 0.584 | 0.444 | 0.499 | 0.328 |
| AI a_vig P(N1) | 0.849 | 0.663 | 0.681 | 0.911 |
| AI wake_light P(light) | 0.861 | 0.669 | 0.694 | 0.913 |

### protocols (gym simulate_protocol; playability parts, not validity)

| id | sleep-edf (old global) | sleep-edf | lee-eo-ec | lee-artifacts | universe |
|---|---|---|---|---|---|
| sleepGuard | final 0.634 · hit — · rew — · inh — · guard LA 0.634 | final 0.652 · hit — · rew — · inh — · guard LA 0.652 | final — · hit — · rew — · inh — · guard LA — | final — · hit — · rew — · inh — · guard LA — | final — · hit — · rew — · inh — · guard LA — |
| restAwake | final 0.823 · hit 0.855 · rew 0.866 · inh 1.000 · guard LA 0.634 | final 0.767 · hit 0.702 · rew 0.744 · inh 1.000 · guard LA 0.652 | final 0.832 · hit 0.743 · rew 0.765 · inh 1.000 · guard LA — | final 0.706 · hit 0.523 · rew 0.588 · inh 1.000 · guard LA — | final 0.762 · hit 0.626 · rew 0.667 · inh 1.000 · guard LA — |
| openMonitor | final 0.836 · hit 0.879 · rew 0.892 · inh 1.000 · guard LA 0.634 | final 0.791 · hit 0.743 · rew 0.791 · inh 1.000 · guard LA 0.652 | final 0.829 · hit 0.726 · rew 0.760 · inh 1.000 · guard LA — | final 0.668 · hit 0.442 · rew 0.535 · inh 1.000 · guard LA — | final 0.721 · hit 0.539 · rew 0.609 · inh 1.000 · guard LA — |
| alertOpen | final 0.880 · hit 0.800 · rew 0.831 · inh 1.000 · guard LA — | final 0.829 · hit 0.708 · rew 0.760 · inh 1.000 · guard LA — | final 0.794 · hit 0.660 · rew 0.712 · inh 1.000 · guard LA — | final 0.733 · hit 0.559 · rew 0.627 · inh 1.000 · guard LA — | final 0.820 · hit 0.708 · rew 0.748 · inh 1.000 · guard LA — |
| alertClosed | final 0.806 · hit 0.800 · rew 0.831 · inh 1.000 · guard LA 0.634 | final 0.776 · hit 0.708 · rew 0.760 · inh 1.000 · guard LA 0.652 | final 0.794 · hit 0.660 · rew 0.712 · inh 1.000 · guard LA — | final 0.733 · hit 0.559 · rew 0.627 · inh 1.000 · guard LA — | final 0.820 · hit 0.708 · rew 0.748 · inh 1.000 · guard LA — |
| concentrate | final 0.748 · hit 0.675 · rew 0.731 · inh 0.963 · guard LA 0.634 | final 0.717 · hit 0.585 · rew 0.672 · inh 0.926 · guard LA 0.652 | final 0.556 · hit 0.410 · rew 0.526 · inh 0.629 · guard LA — | final 0.466 · hit 0.244 · rew 0.410 · inh 0.604 · guard LA — | final 0.463 · hit 0.278 · rew 0.436 · inh 0.530 · guard LA — |
| calibrateRecord | N/A | N/A | N/A | N/A | N/A |
