# FAIR_BANDMATH

_Generated 2026-10-07 by `runners/fair_round.py` (branch `feat/gym-fair-bandmath`). Aggregates only; no data, windows or per-recording rows._

> Short answer to "were all our gym tests done with fair band math?": **no.** Sleep-EDF, the corpus behind every sleep claim, scored all 20 recordings against one 45 s baseline from the first recording (SC4001). Every feature was swept in one direction only. The board's `sep` folded the direction away, and the "reward" numbers measured playability, not validity. Earlier fixes covered only the sleep guard and delta: the guard default moved from `band.delta` to `ai.a_vig`, and `deltaRail` was turned off in the catalog. They did nothing for ATR / TAR / BTR / alpha. This round re-scores **all 8 band features on all 4 corpora** with per-recording baselines and both directions. **Pad mixing** (section below): no Muse pad combination gives an artifact-robust δ/θ that beats the app's existing quality-gated AF7/AF8. On a Muse, blinks reach TP9/TP10 through the Fpz reference.

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

## Pad mixing (2026-10-07): can other Muse pads give a cleaner delta / theta?

_Generated by `runners/pad_mix_round.py` and `runners/sleep_edf_heog.py`. Corpora rebuilt with neurofeed-gym-corpora `a4a0d2a` `--pad-mix`. Aggregates only._

**What this tests, and what it does not.** It tests **artifact robustness and signal retention on awake Muse data** (Lee 2026 Muse 2: 102 recordings for artifacts and 25 subjects for EO/EC; UNIVERSE Muse S: 46 sessions). It does **not** test sleep-onset sensitivity. There is no labeled Muse sleep or drowsiness data on the box (checked 2026-10-07: only Sleep-EDF, HMC "Crown" PSG proxies and attention corpora; nothing was downloaded). **Sleep-EDF cannot test pad mixing.** It has Fpz-Cz and Pz-Oz only, and the gym copies them into AF7=AF8 and TP9=TP10, so every mix there would either do nothing or be faked. One separate positive control further down uses Sleep-EDF's real horizontal EOG channel for the eye-movement idea. It is labeled as such and is not a pad-mixing result.

**Data.** `lee2026_eo_ec`, `lee2026_artifacts` and `universe_stress` were rebuilt with per-channel band powers plus the variant columns, so each variant is computed from the same 2 s windows. The existing columns are bit-identical to before, and the AF7/AF8 mean of the per-channel columns reproduces `band_delta` / `band_tar` exactly (tested). Band powers come from the same flutter_bands math as every other gym column. The app's newer Hamming math moved AUCs by ≤ 0.02 in the fair round.

**Rules** (fair round):
- Per-recording baseline; calibration rows are never scored.
- Per-recording directional AUC (label 1 higher = the feature rises), median over recordings.
- p90-of-baseline guard. A window a gated variant skips **never warns**, as in the app.
- Every feature here has sleep direction **up**: abs δ, abs θ, rel θ, TAR, (θ+α)/β. So an artifact AUC near 1 means a sleep guard fires on the artifact (**lower is better**).

**Columns.**
- **Blink.** Lee's EB rests are eyes **closed** and its task is eyes **open**, so the within-recording blink contrast also contains eye opening. Blinks are therefore also scored **EO-matched**: EB task rows vs the same subject's MVO eyes-open rest, with the threshold taken from the MVO baseline.
- **Jaw** = BT clench, eyes closed. **Movement** = head turns that alternate left/right every 3 s, eyes open (MVO) and eyes closed (MVC).
- **EO/EC** = AUC on the EO/EC corpus, with eyes closed as label 1.
- **Stability** = Spearman ρ over recordings of median(pre-rest) vs median(post-rest) on clean rows. This is a test-retest check: a flat or noise-only variant scores low.
- **Coverage** = share of clean rows on which the variant is defined.

**Variants** (pooling follows the app: absolute δ / θ = pooled absolute power; shares and ratios come from pooled per-pad relative bands):
- **`af`**: AF7/AF8 mean, ungated. This is today's app math.
- **`af_gate`**: AF7/AF8, keeping only pads with app quality ≥ 80. This approximates the app's live gate; the score is recomputed from std + mains ratio on the high-passed signal.
- **`tp`**: TP9/TP10 mean.
- **`all4`**: 4-pad mean.
- **`split`**: δ/θ from TP, α/β from all 4 pads (variant 1).
- **`med4`**: 4-pad median.
- **Weighted 4-pad means:**
  - `w4_var`: weights 1/variance.
  - `w4_hf`: weights 1/γ power (an EMG proxy).
  - `w4_q`: weights = app quality score. Muse HSI is not in these recordings, so the app score stands in for it.
- **`gate4`**: 4-pad mean over usable pads only.
- **`bip`**: AF7−AF8 bipolar (variant 2).
- **`tpbip`**: TP9−TP10 bipolar. Added after finding 1 below.
- **`car_tp`**: TP after re-referencing to the 4-pad common average.
- **`tphp`**: TP after a causal 0.5 Hz high-pass. This is the control for the EOG variants.
- **`eogcal` / `eogrun`**: TP with the high-passed AF7 / AF8 regressed out (variant 3).
  - Regressing on AF7 / AF8 spans the same space as regressing on (AF7−AF8, (AF7+AF8)/2), so the fit is identical either way.
  - **Both fits were run.** `eogcal` is least squares fitted **once per recording on its calibration block** (the samples under its 30 baseline rows, ≈ 31 s), then applied sample by sample. `eogrun` is a **causal running** least-squares fit over the trailing ≤ 30 s, refitted every second. Both could run live.

### Main table: absolute δ / absolute θ

| variant | blink AUC δ / θ (EB rest) | blink AUC δ / θ (EO-matched) | jaw AUC δ / θ | movement AUC δ / θ (EO; EC) | EO/EC AUC δ / θ | stability ρ δ / θ | coverage | live-capable |
|---|---|---|---|---|---|---|---:|---|
| af (AF7/AF8 mean (app today, ungated)) | 0.92 / 0.91 | 0.84 / 0.65 | 0.72 / 0.70 | 0.95 / 0.89; 0.91 / 0.82 | 0.34 / 0.31 | 0.73 / 0.79 | 1.00 | yes: current |
| af_gate (AF7/AF8, quality-gated (app live)) | 0.90 / 0.86 | 0.76 / 0.64 | 0.61 / 0.59 | 0.90 / 0.85; 0.90 / 0.78 | 0.37 / 0.32 | 0.78 / 0.82 | 0.96 | yes: current |
| tp (TP9/TP10 mean) | 0.96 / 0.91 | 0.78 / 0.64 | 0.76 / 0.73 | 0.79 / 0.68; 0.89 / 0.80 | 0.22 / 0.28 | 0.66 / 0.86 | 1.00 | yes: free (per-pad FFTs exist) |
| all4 (4-pad mean) | 0.95 / 0.93 | 0.81 / 0.67 | 0.79 / 0.74 | 0.84 / 0.70; 0.93 / 0.81 | 0.28 / 0.30 | 0.72 / 0.81 | 1.00 | yes: free |
| split (δ/θ from TP, α/β from 4 pads) | 0.96 / 0.91 | 0.78 / 0.64 | 0.76 / 0.73 | 0.79 / 0.68; 0.89 / 0.80 | 0.22 / 0.28 | 0.66 / 0.86 | 1.00 | yes: free |
| med4 (4-pad median) | 0.97 / 0.96 | 0.81 / 0.65 | 0.76 / 0.74 | 0.81 / 0.70; 0.92 / 0.82 | 0.26 / 0.28 | 0.72 / 0.84 | 1.00 | yes: free |
| w4_var (4-pad, 1/variance weights) | 0.97 / 0.94 | 0.81 / 0.61 | 0.74 / 0.67 | 0.89 / 0.83; 0.93 / 0.80 | 0.24 / 0.28 | 0.75 / 0.83 | 1.00 | yes: free (std ring exists) |
| w4_hf (4-pad, 1/gamma-power weights) | 0.96 / 0.94 | 0.80 / 0.68 | 0.73 / 0.55 | 0.83 / 0.71; 0.93 / 0.74 | 0.24 / 0.27 | 0.70 / 0.84 | 1.00 | yes: free |
| w4_q (4-pad, app-quality weights) | 0.96 / 0.95 | 0.76 / 0.60 | 0.77 / 0.71 | 0.84 / 0.70; 0.93 / 0.81 | 0.24 / 0.27 | 0.70 / 0.83 | 1.00 | yes: free |
| gate4 (4-pad, quality-gated mean) | 0.90 / 0.84 | 0.74 / 0.61 | 0.62 / 0.55 | 0.83 / 0.79; 0.88 / 0.68 | 0.35 / 0.43 | 0.78 / 0.83 | 0.97 | yes: free |
| bip (bipolar AF7−AF8) | 0.82 / 0.79 | 0.80 / 0.71 | 0.66 / 0.63 | 0.97 / 0.95; 0.92 / 0.81 | 0.50 / 0.47 | 0.71 / 0.79 | 1.00 | yes: +1 FFT/s |
| tpbip (bipolar TP9−TP10) | 0.50 / 0.35 | 0.63 / 0.54 | 0.74 / 0.60 | 0.99 / 0.98; 0.96 / 0.85 | 0.57 / 0.58 | 0.70 / 0.82 | 1.00 | yes: +1 FFT/s |
| car_tp (TP, common-average reference) | 0.95 / 0.94 | 0.82 / 0.69 | 0.79 / 0.70 | 0.78 / 0.68; 0.93 / 0.84 | 0.25 / 0.29 | 0.67 / 0.83 | 1.00 | yes: 2 FFT/s |
| tphp (TP + 0.5 Hz HP (control)) | 0.99 / 0.90 | 0.80 / 0.65 | 0.78 / 0.73 | 0.77 / 0.65; 0.88 / 0.80 | 0.21 / 0.27 | 0.67 / 0.86 | 1.00 | yes: app already high-passes |
| eogcal (TP − EOG regression (cal-fit)) | 0.98 / 0.92 | 0.91 / 0.75 | 0.80 / 0.73 | 0.86 / 0.82; 0.91 / 0.80 | 0.26 / 0.37 | 0.69 / 0.83 | 1.00 | yes: 2×2 LS once, 4 MAC/sample |
| eogrun (TP − EOG regression (running 30 s)) | 0.96 / 0.92 | 0.75 / 0.72 | 0.80 / 0.75 | 0.86 / 0.71; 0.87 / 0.83 | 0.11 / 0.18 | 0.68 / 0.83 | 1.00 | yes: running sums + 2×2 solve/s |

Per-recording AUC with label 1 = artifact (or eyes closed); median over recordings; lower = more robust. UNIVERSE (relax vs stress): every variant is at chance for δ and θ (per-rec AUC 0.47–0.51).

### Relative θ and TAR, same columns

| variant | rel θ: blink (EB rest / EO-matched) · jaw · turn EO / EC · EO/EC · ρ | TAR: blink (EB rest / EO-matched) · jaw · turn EO / EC · EO/EC · ρ |
|---|---|---|
| af | 0.40 / 0.35 · 0.29 · 0.38 / 0.46 · 0.46 · 0.82 | 0.88 / 0.64 · 0.51 · 0.69 / 0.71 · 0.33 · 0.76 |
| af_gate | 0.44 / 0.34 · 0.30 · 0.47 / 0.39 · 0.48 · 0.83 | 0.80 / 0.61 · 0.48 · 0.69 / 0.63 · 0.35 · 0.77 |
| tp | 0.37 / 0.26 · 0.19 · 0.19 / 0.13 · 0.48 · 0.81 | 0.97 / 0.63 · 0.56 · 0.38 / 0.43 · 0.09 · 0.88 |
| all4 | 0.31 / 0.29 · 0.16 · 0.25 / 0.24 · 0.42 · 0.74 | 0.97 / 0.62 · 0.61 · 0.54 / 0.62 · 0.14 · 0.86 |
| split | 0.37 / 0.26 · 0.19 · 0.19 / 0.13 · 0.48 · 0.81 | 0.94 / 0.59 · 0.49 · 0.45 / 0.45 · 0.13 · 0.86 |
| med4 | 0.33 / 0.28 · 0.17 · 0.26 / 0.21 · 0.43 · 0.77 | 0.97 / 0.63 · 0.59 · 0.53 / 0.61 · 0.13 · 0.85 |
| w4_var | 0.36 / 0.30 · 0.20 · 0.32 / 0.31 · 0.42 · 0.78 | 0.94 / 0.63 · 0.56 · 0.62 / 0.63 · 0.19 · 0.82 |
| w4_hf | 0.35 / 0.31 · 0.21 · 0.33 / 0.31 · 0.41 · 0.76 | 0.97 / 0.63 · 0.64 · 0.59 / 0.82 · 0.15 · 0.86 |
| w4_q | 0.34 / 0.29 · 0.17 · 0.29 / 0.27 · 0.42 · 0.79 | 0.96 / 0.61 · 0.61 · 0.57 / 0.60 · 0.16 · 0.86 |
| gate4 | 0.40 / 0.33 · 0.25 · 0.43 / 0.37 · 0.52 · 0.79 | 0.90 / 0.60 · 0.60 · 0.70 / 0.76 · 0.23 · 0.84 |
| bip | 0.50 / 0.45 · 0.28 · 0.43 / 0.44 · 0.46 · 0.75 | 0.74 / 0.68 · 0.50 · 0.83 / 0.73 · 0.44 · 0.61 |
| tpbip | 0.34 / 0.53 · 0.19 · 0.11 / 0.07 · 0.62 · 0.77 | 0.57 / 0.60 · 0.53 · 0.56 / 0.30 · 0.46 · 0.68 |
| car_tp | 0.30 / 0.31 · 0.17 · 0.18 / 0.12 · 0.46 · 0.77 | 0.97 / 0.64 · 0.62 · 0.36 / 0.40 · 0.14 · 0.85 |
| tphp | 0.38 / 0.25 · 0.18 · 0.21 / 0.14 · 0.49 · 0.82 | 0.97 / 0.63 · 0.56 · 0.38 / 0.42 · 0.09 · 0.88 |
| eogcal | 0.34 / 0.30 · 0.15 · 0.23 / 0.13 · 0.42 · 0.77 | 0.97 / 0.80 · 0.59 · 0.63 / 0.41 · 0.18 · 0.88 |
| eogrun | 0.47 / 0.47 · 0.17 · 0.22 / 0.14 · 0.54 · 0.81 | 0.95 / 0.67 · 0.60 · 0.42 / 0.43 · 0.12 · 0.87 |

### False warnings: p90 sleep guard on abs δ (abs θ in the last column)

| variant (abs δ guard, p90) | clean → blink, EO-matched | clean → jaw | clean → head turn EO | clean → head turn EC | UNIVERSE relax / stress | abs θ: EO-matched blink · jaw · turn EO |
|---|---|---|---|---|---|---|
| af | 0.15 → 0.53 | 0.09 → 0.31 | 0.15 → 0.75 | 0.13 → 0.64 | 0.11 / 0.11 | 0.39 · 0.28 · 0.63 |
| af_gate | 0.14 → 0.25 | 0.11 → 0.17 | 0.14 → 0.25 | 0.15 → 0.55 | 0.08 / 0.07 | 0.17 · 0.15 · 0.20 |
| tp | 0.14 → 0.43 | 0.13 → 0.43 | 0.13 → 0.46 | 0.16 → 0.63 | 0.16 / 0.15 | 0.27 · 0.34 · 0.35 |
| all4 | 0.14 → 0.49 | 0.11 → 0.40 | 0.13 → 0.54 | 0.16 → 0.68 | 0.16 / 0.15 | 0.35 · 0.35 · 0.39 |
| split | 0.14 → 0.43 | 0.13 → 0.43 | 0.13 → 0.46 | 0.16 → 0.63 | 0.16 / 0.15 | 0.27 · 0.34 · 0.35 |
| med4 | 0.12 → 0.47 | 0.10 → 0.40 | 0.12 → 0.45 | 0.14 → 0.68 | 0.17 / 0.16 | 0.28 · 0.33 · 0.27 |
| w4_var | 0.15 → 0.47 | 0.10 → 0.35 | 0.14 → 0.63 | 0.16 → 0.71 | 0.14 / 0.14 | 0.32 · 0.32 · 0.48 |
| w4_hf | 0.14 → 0.50 | 0.11 → 0.32 | 0.13 → 0.47 | 0.14 → 0.68 | 0.20 / 0.21 | 0.31 · 0.26 · 0.32 |
| w4_q | 0.14 → 0.43 | 0.10 → 0.36 | 0.14 → 0.53 | 0.14 → 0.68 | 0.18 / 0.18 | 0.26 · 0.33 · 0.34 |
| gate4 | 0.13 → 0.21 | 0.11 → 0.18 | 0.13 → 0.20 | 0.14 → 0.53 | 0.12 / 0.11 | 0.15 · 0.17 · 0.16 |
| bip | 0.14 → 0.49 | 0.10 → 0.26 | 0.14 → 0.88 | 0.13 → 0.62 | 0.10 / 0.09 | 0.39 · 0.22 · 0.80 |
| tpbip | 0.19 → 0.40 | 0.15 → 0.44 | 0.19 → 0.96 | 0.14 → 0.80 | 0.09 / 0.08 | 0.30 · 0.29 · 0.93 |
| car_tp | 0.14 → 0.48 | 0.11 → 0.39 | 0.14 → 0.48 | 0.17 → 0.64 | 0.15 / 0.14 | 0.33 · 0.34 · 0.37 |
| tphp | 0.13 → 0.46 | 0.12 → 0.43 | 0.13 → 0.45 | 0.15 → 0.61 | 0.16 / 0.15 | 0.27 · 0.34 · 0.34 |
| eogcal | 0.20 → 0.81 | 0.12 → 0.44 | 0.20 → 0.77 | 0.17 → 0.65 | 0.17 / 0.17 | 0.63 · 0.36 · 0.62 |
| eogrun | 0.21 → 0.48 | 0.12 → 0.43 | 0.20 → 0.65 | 0.18 → 0.62 | 0.15 / 0.14 | 0.43 · 0.39 · 0.48 |

### Findings

1. **On a Muse, the TP pads see blinks through the reference, so δ/θ from TP is not blink-proof.** Muse records every pad against Fpz on the forehead, so a blink appears, inverted, on all four channels.
   - During the EB task, < 4 Hz amplitude (SD) was AF7 20, AF8 13, TP9 33 and TP10 32 µV (median of 26 subjects; about 5 µV on every pad at rest). TP exceeded AF in 19 / 26 subjects.
   - So `tp` / `split` / `car_tp` / `tphp` are **not** cleaner than `af` on blinks. Within-recording blink AUC for δ is 0.95–0.99 vs 0.92; EO-matched it is 0.78–0.82 vs 0.84, and the warn rate on blink rows 0.43–0.48 vs 0.53.
   - They are worse on jaw clench (0.76–0.79 vs 0.72; warn 0.39–0.43 vs 0.31) and better only for eyes-open head turns (0.77–0.79 vs 0.95).
   - By the app's own pad-quality score, TP9 / TP10 count as usable in only 23 % / 45 % of Lee windows and 14 % / 18 % of UNIVERSE windows (AF7 / AF8: 73–82 %). **Live, a TP-based feature would be gated out most of the time.**
2. **EOG regression does not fix it** (variant 3).
   - `eogcal` is **worse**: EO-matched blink δ 0.91, warn 0.81. Its baseline is a quiet rest with almost no eye activity (median R² of the cal fit 0.07 on Lee artifacts, 0.20 on EO rest), so the coefficients do not fit blinks.
   - `eogrun` ≈ the high-pass control (0.75 vs 0.80 EO-matched; 0.96 vs 0.99 within-recording).
   - Even an in-sample fit on the blink task itself explains only ~80 % of TP < 4 Hz variance (median R² 0.80 / 0.83). That leaves about 3× the resting level, which still trips a p90 guard.
3. **AF7−AF8 bipolar** (variant 2a).
   - **Blinks are reduced, not removed.** Within-recording δ AUC 0.92 → 0.82 (warn 0.68 → 0.48) and θ 0.91 → 0.79. EO-matched: δ 0.84 → 0.80, θ 0.65 → 0.71, so no gain.
   - Cancellation is incomplete because the blink is not the same size on AF7 and AF8: per subject, < 4 Hz SD differs by up to ~10× between the two pads, probably contact.
   - Horizontal activity survives, as designed: eyes-open head turns δ 0.97, warn 0.88.
   - EO/EC becomes neutral (0.50), i.e. it loses the eyes-closed δ drop.
4. **Robust pooling** (variant 4).
   - Median and weights barely help δ (EO-matched blink 0.76–0.81 vs 0.84) and cost jaw and eyes-closed head turns. Every pad carries the reference blink, so choosing among pads cannot remove it.
   - **What helps is the quality gate.** `af_gate`, roughly what the app already does, cuts δ false warnings on EO-matched blinks 0.53 → 0.25, jaw 0.31 → 0.17 and eyes-open head turns 0.75 → 0.25 at 96 % coverage. `gate4` is similar (0.21 / 0.18 / 0.20) at 97 %. Eyes-closed head turns stay high (0.55 / 0.53).
   - The earlier awake-corpus table (above) scored **ungated** features, so it overstates the app's artifact false-warning rate for δ / θ.
5. **TP9−TP10 bipolar** cancels the reference blink (within-recording δ AUC 0.50, warn 0.21; EO-matched 0.63). But head movement dominates it (eyes-open turns 0.99, warn 0.96; eyes closed 0.96 / 0.80), consistent with neck / mastoid EMG and electrode motion being different on the two sides. It also flips the eyes-closed direction (0.57).
6. **Relative θ is already artifact-robust in every variant.** Artifact AUCs are 0.07–0.53, and the warn rate on artifact rows stays ≤ 0.24 in every variant (abs δ ungated: up to 0.88), because artifacts mostly add δ, which inflates the denominator. TP-based rel θ, however, false-warns more on clean awake data (0.20 on Lee clean rows, 0.28 on UNIVERSE relax) than AF (0.11 / 0.14).
7. **Signal retained:** no variant is flat. Retest ρ is 0.61–0.88 everywhere (lowest: bipolar AF TAR 0.61) (δ: TP lowest at 0.66, gated AF / 4-pad highest at 0.78). Monopolar δ / θ fall with eyes closed (EO/EC 0.11–0.43); bipolar variants are neutral.
8. **Live cost:** every variant could run causally in the app at 256 Hz × 4 channels.
   - The pooled variants are free: per-pad FFTs, the 1 s std ring and the quality score already exist.
   - The two bipolars add one 256-point FFT per second; `car_tp` adds two.
   - `eogcal` is a 2×2 solve once plus 4 multiply-adds per sample. `eogrun` uses running cross-product sums plus a 2×2 solve per second.
   - The `*_8s` eye features need an 8 s ring and one 2048-point FFT per second.

### Slow eye movements (variant 2b)

Lee has **no labeled horizontal eye movements or gaze shifts**. Its movement task is alternating left/right **head** turns (paper: 20 turns cued every 3 s), which mixes head motion with horizontal EOG (gaze shifts and counter-rotating eyes). Head turns are the closest proxy, so detection AUCs below are for head turns, not clean eye movements.

**Band choice.**
- A 2 s window has 0.5 Hz bins, so `sem_2s` (0.5–2 Hz) mainly catches saccades and blink residue.
- `sem_8s` uses a trailing (causal) 8 s window with 0.125 Hz bins and reaches 0.25 Hz.
- Getting to 0.1 Hz needs ≥ 20 s windows, where Muse electrode drift dominates.
- `sem_fast_8s` (1–5 Hz) is the saccade / fast eye-movement band, and the slowness ratio is `sem_8s / sem_fast_8s`.

| eye feature (sleep dir) | blink AUC (EB rest / EO-matched) | jaw AUC | movement AUC (EO / EC) | EO/EC AUC | stability ρ | UNIVERSE warn relax | live-capable |
|---|---|---:|---|---:|---:|---:|---|
| sem_2s (↑) SEM power 0.5–2 Hz, 2 s (AF7−AF8) | 0.65 / 0.66 | 0.63 | 0.96 / 0.88 | 0.56 | 0.70 | 0.09 | yes: +1 FFT/s |
| sem_8s (↑) SEM power 0.25–1 Hz, 8 s (AF7−AF8) | 0.72 / 0.90 | 0.65 | 1.00 / 0.99 | 0.72 | 0.64 | 0.10 | yes: 8 s ring + FFT/s |
| sem_fast_8s (↓) fast eye-movement power 1–5 Hz, 8 s (AF7−AF8), falls | 0.02 / 0.12 | 0.29 | 0.00 / 0.04 | 0.58 | 0.71 | 0.22 | yes: 8 s ring + FFT/s |
| sem_ratio_8s (↑) slowness ratio sem_8s / sem_fast_8s | 0.17 / 0.71 | 0.58 | 0.93 / 0.74 | 0.89 | 0.70 | 0.11 | yes: 8 s ring + FFT/s |
| veog_2s (↑) vertical (AF7+AF8)/2 0.5–2 Hz, 2 s (blink comparator) | 0.89 / 0.70 | 0.66 | 0.76 / 0.83 | 0.38 | 0.77 | 0.14 | yes: +1 FFT/s |
| veog_8s (↑) vertical 0.25–1 Hz, 8 s (blink comparator) | 0.99 / 0.98 | 0.66 | 0.96 / 0.92 | 0.41 | 0.70 | 0.14 | yes: 8 s ring + FFT/s |

- **As an eye-movement detector, `sem_8s` works.** Head turns: AUC 1.00 eyes open and 0.99 eyes closed (warn 0.82 / 0.64). It is **not specific**: EO-matched blinks 0.90 and jaw 0.65. `veog_8s` is a near-perfect blink / vertical detector (0.98–0.99).
- **Positive control on real horizontal EOG** (Sleep-EDF `EOG horizontal`, the gym's 20 test recordings, 17 scored, same rows and baselines as the fair round). This is **not Muse and not pad mixing**:

  | feature (sleep dir) | per-rec AUC W→N1, median [IQR] | recs > 0.5 | BA p90 | warn p90 W / N1 |
  |---|---|---:|---:|---|
  | HEOG 0.5–2 Hz, 2 s ↑ | 0.367 [0.253–0.468] | 2/17 | 0.459 | 0.17 / 0.09 |
  | HEOG 0.25–1 Hz, 8 s ↑ | 0.448 [0.276–0.612] | 7/17 | 0.463 | 0.17 / 0.10 |
  | HEOG 1–5 Hz, 8 s ↓ (saccades fade) | **0.870** [0.690–0.901] | 16/17 | 0.545 | 0.38 / 0.47 |
  | HEOG slowness ratio (0.25–1) / (1–5 Hz) ↑ | **0.816** [0.690–0.838] | 17/17 | 0.673 | 0.38 / 0.73 |
  | ai.a_vig ↑ (reference) | 0.911 [0.842–0.936] | 17/17 | 0.681 | 0.53 / 0.89 |
  | frontal abs δ ↑ (reference) | 0.328 [0.259–0.542] | 5/17 | 0.499 | 0.12 / 0.12 |

  **Slow power alone does not mark sleep onset** (wake has big saccades). **Saccades fading, and the slow-to-fast ratio rising, do**, and they come within ≈ 0.04–0.10 of the AI. That is the best case, with a real outer-canthus EOG.
- **On a Muse, the same ratio is confounded:**
  - It rises with eye closure: EO/EC 0.89.
  - It rises with head turns (0.93 eyes open). Fast-band power drops by itself during quiet rest: 23–37 % warn on clean rows in its sleep direction, 22 % on UNIVERSE.
  - How much of a slow eye movement AF7−AF8 actually picks up is untested.
  - Usable, if at all, only in eyes-open protocols and with artifact gating, and only after Muse sleep data shows it works.

### Recommendation

1. **Port none of the δ/θ pad-mixing variants as app features.**
   - None beats the app's existing quality-gated AF7/AF8 for artifact robustness.
   - The TP-based ones are hurt by the Fpz reference and are rarely "usable" by the app's own score.
   - EOG regression with Muse's own frontal pads cannot remove the reference blink.
   - The two bipolars swap blink sensitivity for head-movement sensitivity.
2. **Keep the quality gate on band guards, and simulate it in the gym.** That is a gym change, not an app change. It is the largest single reduction in artifact false warnings measured here, and the earlier fair-round awake tables overstate the app's false-warning rate because they were ungated. A 4-pad gated mean (`gate4`) is marginally better than `af_gate` (blink / head-turn warn 0.21 / 0.20 vs 0.25 / 0.25). It is worth adding only as part of a broader δ redesign.
3. **For a frontal band sleep guard, relative θ on AF (quality-gated) remains the candidate.** It was best on Sleep-EDF (per-rec AUC 0.75) and it does not rise on artifacts in any variant.
4. **Eye movements are the promising direction.** Fast-eye-movement loss and the slowness ratio reach 0.82–0.87 on real EOG. Treat `sem_fast_8s` / `sem_ratio_8s` (AF7−AF8) as **research candidates, not app features**: first validate on labeled Muse drowsiness / nap data, eyes-open protocols only, with gating. `veog_8s` could serve as a blink / vertical-artifact veto for δ guards. But blink changes are themselves drowsiness signs, so decide that with data too.

### Caveats

- **Artifact robustness only; no Muse sleep labels.** None of this says whether any variant tracks sleep onset on a Muse.
- **Labels are cued periods, not events.** Lee labels the whole 60 s task period; not every 2 s window contains the event. The EB contrast includes eye opening, and the EO-matched check compares two different recordings (EB vs MVO) of the same subject.
- **Head turns are not pure horizontal eye movements.** They also move the electrodes and the neck.
- **The app pad-quality score is an approximation.** It is recomputed offline (0.5 Hz high-pass, no notch), not taken from the app.
- **Gym math, not app math.** Band powers use the gym's flutter_bands math, not the app's Hamming math; the effect measured earlier was ≤ 0.02.
- **Short recordings.** Lee recordings are about 3 minutes with a 30-row baseline, so stability numbers are short-range test-retest.
- **The HEOG control is the best case.** It uses a real EOG with no Muse, and the 17 recordings are the AI heads' held-out test split.

## Reproduce

```bash
cd feedback_gym
python3 runners/build_corpus_sleep_edf.py            # per-recording cal + app_* / post_* columns (needs ../muse-eeg-heads)
python3 runners/build_corpus_sleep_edf.py --cal-mode global --no-extra-columns \
    --out corpora/external/sleep_edf_test_global_old.npz   # the old corpus, for the old-vs-fair columns
python3 runners/fair_round.py --catalog <protocols.json>   # -> results/<ts>_fair/{fair_board.json,fair_tables.md}

# pad mixing (needs ../neurofeed-gym-corpora >= a4a0d2a and its raw/ downloads)
(cd ../../neurofeed-gym-corpora && \
  uv run --with numpy --with mne python builders/build_lee2026.py --pad-mix \
    --out-eo-ec ../neurofeed/feedback_gym/corpora/external/lee2026_eo_ec.npz \
    --out-artifacts ../neurofeed/feedback_gym/corpora/external/lee2026_artifacts.npz && \
  uv run --with numpy --with pandas --with scipy python builders/build_universe.py --pad-mix)
python3 runners/pad_mix_round.py                           # -> results/<ts>_padmix/{padmix_board.json,padmix_tables.md}
uv run --with numpy --with scipy --with mne --with pyyaml \
    python runners/sleep_edf_heog.py                       # HEOG positive control (adds heog_* columns to sleep_edf_test.npz)
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

## Appendix: full pad-mixing tables (generated)

_Lee 2026 Muse 2 (artifacts: 102 recordings, EB / BT / MVO / MVC; EO/EC: 25 subjects), per-recording baselines, cal rows not scored, per-recording AUC with label 1 = artifact / eyes closed (higher = feature rises), median over recordings. Guard = warn when the feature rises above p90 of the recording's own baseline. Corpora: lee-artifacts N=18054, lee-eo-ec N=5900, universe N=48790_

#### abs delta

| variant · feature | blink AUC (EB rest / EO-matched) | jaw AUC | movement AUC (EO / EC) | EO/EC AUC | stability (retest ρ) | coverage | live-capable |
|---|---:|---:|---:|---:|---:|---:|---|
| af · abs delta | 0.92 / 0.84 | 0.72 | 0.95 / 0.91 | 0.34 EC↓ | 0.73 | 1.00 | yes: current |
| af_gate · abs delta | 0.90 / 0.76 | 0.61 | 0.90 / 0.90 | 0.37 EC↓ | 0.78 | 0.96 | yes: current |
| tp · abs delta | 0.96 / 0.78 | 0.76 | 0.79 / 0.89 | 0.22 EC↓ | 0.66 | 1.00 | yes: free (per-pad FFTs exist) |
| all4 · abs delta | 0.95 / 0.81 | 0.79 | 0.84 / 0.93 | 0.28 EC↓ | 0.72 | 1.00 | yes: free |
| split · abs delta | 0.96 / 0.78 | 0.76 | 0.79 / 0.89 | 0.22 EC↓ | 0.66 | 1.00 | yes: free |
| med4 · abs delta | 0.97 / 0.81 | 0.76 | 0.81 / 0.92 | 0.26 EC↓ | 0.72 | 1.00 | yes: free |
| w4_var · abs delta | 0.97 / 0.81 | 0.74 | 0.89 / 0.93 | 0.24 EC↓ | 0.75 | 1.00 | yes: free (std ring exists) |
| w4_hf · abs delta | 0.96 / 0.80 | 0.73 | 0.83 / 0.93 | 0.24 EC↓ | 0.70 | 1.00 | yes: free |
| w4_q · abs delta | 0.96 / 0.76 | 0.77 | 0.84 / 0.93 | 0.24 EC↓ | 0.70 | 1.00 | yes: free |
| gate4 · abs delta | 0.90 / 0.74 | 0.62 | 0.83 / 0.88 | 0.35 EC↓ | 0.78 | 0.97 | yes: free |
| bip · abs delta | 0.82 / 0.80 | 0.66 | 0.97 / 0.92 | 0.50 EC↓ | 0.71 | 1.00 | yes: +1 FFT/s |
| tpbip · abs delta | 0.50 / 0.63 | 0.74 | 0.99 / 0.96 | 0.57 EC↑ | 0.70 | 1.00 | yes: +1 FFT/s |
| car_tp · abs delta | 0.95 / 0.82 | 0.79 | 0.78 / 0.93 | 0.25 EC↓ | 0.67 | 1.00 | yes: 2 FFT/s |
| tphp · abs delta | 0.99 / 0.80 | 0.78 | 0.77 / 0.88 | 0.21 EC↓ | 0.67 | 1.00 | yes: app already high-passes |
| eogcal · abs delta | 0.98 / 0.91 | 0.80 | 0.86 / 0.91 | 0.26 EC↓ | 0.69 | 1.00 | yes: 2×2 LS once, 4 MAC/sample |
| eogrun · abs delta | 0.96 / 0.75 | 0.80 | 0.86 / 0.87 | 0.11 EC↓ | 0.68 | 1.00 | yes: running sums + 2×2 solve/s |

#### abs theta

| variant · feature | blink AUC (EB rest / EO-matched) | jaw AUC | movement AUC (EO / EC) | EO/EC AUC | stability (retest ρ) | coverage | live-capable |
|---|---:|---:|---:|---:|---:|---:|---|
| af · abs theta | 0.91 / 0.65 | 0.70 | 0.89 / 0.82 | 0.31 EC↓ | 0.79 | 1.00 | yes: current |
| af_gate · abs theta | 0.86 / 0.64 | 0.59 | 0.85 / 0.78 | 0.32 EC↓ | 0.82 | 0.96 | yes: current |
| tp · abs theta | 0.91 / 0.64 | 0.73 | 0.68 / 0.80 | 0.28 EC↓ | 0.86 | 1.00 | yes: free (per-pad FFTs exist) |
| all4 · abs theta | 0.93 / 0.67 | 0.74 | 0.70 / 0.81 | 0.30 EC↓ | 0.81 | 1.00 | yes: free |
| split · abs theta | 0.91 / 0.64 | 0.73 | 0.68 / 0.80 | 0.28 EC↓ | 0.86 | 1.00 | yes: free |
| med4 · abs theta | 0.96 / 0.65 | 0.74 | 0.70 / 0.82 | 0.28 EC↓ | 0.84 | 1.00 | yes: free |
| w4_var · abs theta | 0.94 / 0.61 | 0.67 | 0.83 / 0.80 | 0.28 EC↓ | 0.83 | 1.00 | yes: free (std ring exists) |
| w4_hf · abs theta | 0.94 / 0.68 | 0.55 | 0.71 / 0.74 | 0.27 EC↓ | 0.84 | 1.00 | yes: free |
| w4_q · abs theta | 0.95 / 0.60 | 0.71 | 0.70 / 0.81 | 0.27 EC↓ | 0.83 | 1.00 | yes: free |
| gate4 · abs theta | 0.84 / 0.61 | 0.55 | 0.79 / 0.68 | 0.43 EC↓ | 0.83 | 0.97 | yes: free |
| bip · abs theta | 0.79 / 0.71 | 0.63 | 0.95 / 0.81 | 0.47 EC↓ | 0.79 | 1.00 | yes: +1 FFT/s |
| tpbip · abs theta | 0.35 / 0.54 | 0.60 | 0.98 / 0.85 | 0.58 EC↑ | 0.82 | 1.00 | yes: +1 FFT/s |
| car_tp · abs theta | 0.94 / 0.69 | 0.70 | 0.68 / 0.84 | 0.29 EC↓ | 0.83 | 1.00 | yes: 2 FFT/s |
| tphp · abs theta | 0.90 / 0.65 | 0.73 | 0.65 / 0.80 | 0.27 EC↓ | 0.86 | 1.00 | yes: app already high-passes |
| eogcal · abs theta | 0.92 / 0.75 | 0.73 | 0.82 / 0.80 | 0.37 EC↓ | 0.83 | 1.00 | yes: 2×2 LS once, 4 MAC/sample |
| eogrun · abs theta | 0.92 / 0.72 | 0.75 | 0.71 / 0.83 | 0.18 EC↓ | 0.83 | 1.00 | yes: running sums + 2×2 solve/s |

#### rel theta

| variant · feature | blink AUC (EB rest / EO-matched) | jaw AUC | movement AUC (EO / EC) | EO/EC AUC | stability (retest ρ) | coverage | live-capable |
|---|---:|---:|---:|---:|---:|---:|---|
| af · rel theta | 0.40 / 0.35 | 0.29 | 0.38 / 0.46 | 0.46 EC↓ | 0.82 | 1.00 | yes: current |
| af_gate · rel theta | 0.44 / 0.34 | 0.30 | 0.47 / 0.39 | 0.48 EC↓ | 0.83 | 0.96 | yes: current |
| tp · rel theta | 0.37 / 0.26 | 0.19 | 0.19 / 0.13 | 0.48 EC↓ | 0.81 | 1.00 | yes: free (per-pad FFTs exist) |
| all4 · rel theta | 0.31 / 0.29 | 0.16 | 0.25 / 0.24 | 0.42 EC↓ | 0.74 | 1.00 | yes: free |
| split · rel theta | 0.37 / 0.26 | 0.19 | 0.19 / 0.13 | 0.48 EC↓ | 0.81 | 1.00 | yes: free |
| med4 · rel theta | 0.33 / 0.28 | 0.17 | 0.26 / 0.21 | 0.43 EC↓ | 0.77 | 1.00 | yes: free |
| w4_var · rel theta | 0.36 / 0.30 | 0.20 | 0.32 / 0.31 | 0.42 EC↓ | 0.78 | 1.00 | yes: free (std ring exists) |
| w4_hf · rel theta | 0.35 / 0.31 | 0.21 | 0.33 / 0.31 | 0.41 EC↓ | 0.76 | 1.00 | yes: free |
| w4_q · rel theta | 0.34 / 0.29 | 0.17 | 0.29 / 0.27 | 0.42 EC↓ | 0.79 | 1.00 | yes: free |
| gate4 · rel theta | 0.40 / 0.33 | 0.25 | 0.43 / 0.37 | 0.52 EC↑ | 0.79 | 0.97 | yes: free |
| bip · rel theta | 0.50 / 0.45 | 0.28 | 0.43 / 0.44 | 0.46 EC↓ | 0.75 | 1.00 | yes: +1 FFT/s |
| tpbip · rel theta | 0.34 / 0.53 | 0.19 | 0.11 / 0.07 | 0.62 EC↑ | 0.77 | 1.00 | yes: +1 FFT/s |
| car_tp · rel theta | 0.30 / 0.31 | 0.17 | 0.18 / 0.12 | 0.46 EC↓ | 0.77 | 1.00 | yes: 2 FFT/s |
| tphp · rel theta | 0.38 / 0.25 | 0.18 | 0.21 / 0.14 | 0.49 EC↓ | 0.82 | 1.00 | yes: app already high-passes |
| eogcal · rel theta | 0.34 / 0.30 | 0.15 | 0.23 / 0.13 | 0.42 EC↓ | 0.77 | 1.00 | yes: 2×2 LS once, 4 MAC/sample |
| eogrun · rel theta | 0.47 / 0.47 | 0.17 | 0.22 / 0.14 | 0.54 EC↑ | 0.81 | 1.00 | yes: running sums + 2×2 solve/s |

#### TAR

| variant · feature | blink AUC (EB rest / EO-matched) | jaw AUC | movement AUC (EO / EC) | EO/EC AUC | stability (retest ρ) | coverage | live-capable |
|---|---:|---:|---:|---:|---:|---:|---|
| af · TAR | 0.88 / 0.64 | 0.51 | 0.69 / 0.71 | 0.33 EC↓ | 0.76 | 1.00 | yes: current |
| af_gate · TAR | 0.80 / 0.61 | 0.48 | 0.69 / 0.63 | 0.35 EC↓ | 0.77 | 0.96 | yes: current |
| tp · TAR | 0.97 / 0.63 | 0.56 | 0.38 / 0.43 | 0.09 EC↓ | 0.88 | 1.00 | yes: free (per-pad FFTs exist) |
| all4 · TAR | 0.97 / 0.62 | 0.61 | 0.54 / 0.62 | 0.14 EC↓ | 0.86 | 1.00 | yes: free |
| split · TAR | 0.94 / 0.59 | 0.49 | 0.45 / 0.45 | 0.13 EC↓ | 0.86 | 1.00 | yes: free |
| med4 · TAR | 0.97 / 0.63 | 0.59 | 0.53 / 0.61 | 0.13 EC↓ | 0.85 | 1.00 | yes: free |
| w4_var · TAR | 0.94 / 0.63 | 0.56 | 0.62 / 0.63 | 0.19 EC↓ | 0.82 | 1.00 | yes: free (std ring exists) |
| w4_hf · TAR | 0.97 / 0.63 | 0.64 | 0.59 / 0.82 | 0.15 EC↓ | 0.86 | 1.00 | yes: free |
| w4_q · TAR | 0.97 / 0.61 | 0.61 | 0.57 / 0.60 | 0.16 EC↓ | 0.86 | 1.00 | yes: free |
| gate4 · TAR | 0.90 / 0.60 | 0.60 | 0.70 / 0.75 | 0.23 EC↓ | 0.84 | 0.97 | yes: free |
| bip · TAR | 0.74 / 0.68 | 0.50 | 0.83 / 0.73 | 0.44 EC↓ | 0.61 | 1.00 | yes: +1 FFT/s |
| tpbip · TAR | 0.57 / 0.60 | 0.53 | 0.56 / 0.30 | 0.46 EC↓ | 0.68 | 1.00 | yes: +1 FFT/s |
| car_tp · TAR | 0.97 / 0.64 | 0.62 | 0.36 / 0.40 | 0.14 EC↓ | 0.85 | 1.00 | yes: 2 FFT/s |
| tphp · TAR | 0.97 / 0.63 | 0.56 | 0.38 / 0.42 | 0.09 EC↓ | 0.88 | 1.00 | yes: app already high-passes |
| eogcal · TAR | 0.97 / 0.80 | 0.59 | 0.63 / 0.41 | 0.18 EC↓ | 0.88 | 1.00 | yes: 2×2 LS once, 4 MAC/sample |
| eogrun · TAR | 0.95 / 0.67 | 0.60 | 0.42 / 0.43 | 0.12 EC↓ | 0.87 | 1.00 | yes: running sums + 2×2 solve/s |

#### (θ+α)/β

| variant · feature | blink AUC (EB rest / EO-matched) | jaw AUC | movement AUC (EO / EC) | EO/EC AUC | stability (retest ρ) | coverage | live-capable |
|---|---:|---:|---:|---:|---:|---:|---|
| af · (θ+α)/β | 0.85 / 0.61 | 0.33 | 0.74 / 0.77 | 0.44 EC↓ | 0.85 | 1.00 | yes: current |
| af_gate · (θ+α)/β | 0.70 / 0.57 | 0.30 | 0.72 / 0.73 | 0.54 EC↑ | 0.81 | 0.96 | yes: current |
| tp · (θ+α)/β | 0.79 / 0.58 | 0.14 | 0.23 / 0.16 | 0.35 EC↓ | 0.85 | 1.00 | yes: free (per-pad FFTs exist) |
| all4 · (θ+α)/β | 0.72 / 0.63 | 0.19 | 0.50 / 0.48 | 0.47 EC↓ | 0.82 | 1.00 | yes: free |
| split · (θ+α)/β | 0.68 / 0.55 | 0.19 | 0.46 / 0.34 | 0.45 EC↓ | 0.80 | 1.00 | yes: free |
| med4 · (θ+α)/β | 0.77 / 0.62 | 0.20 | 0.49 / 0.43 | 0.44 EC↓ | 0.83 | 1.00 | yes: free |
| w4_var · (θ+α)/β | 0.72 / 0.60 | 0.19 | 0.63 / 0.58 | 0.50 EC↓ | 0.83 | 1.00 | yes: free (std ring exists) |
| w4_hf · (θ+α)/β | 0.75 / 0.58 | 0.16 | 0.58 / 0.52 | 0.45 EC↓ | 0.83 | 1.00 | yes: free |
| w4_q · (θ+α)/β | 0.71 / 0.56 | 0.19 | 0.57 / 0.50 | 0.46 EC↓ | 0.84 | 1.00 | yes: free |
| gate4 · (θ+α)/β | 0.66 / 0.60 | 0.19 | 0.64 / 0.59 | 0.58 EC↑ | 0.85 | 0.97 | yes: free |
| bip · (θ+α)/β | 0.68 / 0.62 | 0.29 | 0.90 / 0.81 | 0.51 EC↑ | 0.81 | 1.00 | yes: +1 FFT/s |
| tpbip · (θ+α)/β | 0.25 / 0.48 | 0.18 | 0.43 / 0.14 | 0.75 EC↑ | 0.82 | 1.00 | yes: +1 FFT/s |
| car_tp · (θ+α)/β | 0.77 / 0.59 | 0.15 | 0.23 / 0.24 | 0.29 EC↓ | 0.81 | 1.00 | yes: 2 FFT/s |
| tphp · (θ+α)/β | 0.78 / 0.59 | 0.15 | 0.23 / 0.16 | 0.34 EC↓ | 0.85 | 1.00 | yes: app already high-passes |
| eogcal · (θ+α)/β | 0.78 / 0.81 | 0.14 | 0.43 / 0.17 | 0.53 EC↑ | 0.83 | 1.00 | yes: 2×2 LS once, 4 MAC/sample |
| eogrun · (θ+α)/β | 0.40 / 0.58 | 0.10 | 0.39 / 0.18 | 0.72 EC↑ | 0.84 | 1.00 | yes: running sums + 2×2 solve/s |

#### eye-movement features (↑ / ↓ = sleep direction; AUCs and warnings are in that direction)

| variant · feature | blink AUC (EB rest / EO-matched) | jaw AUC | movement AUC (EO / EC) | EO/EC AUC | stability (retest ρ) | coverage | live-capable |
|---|---:|---:|---:|---:|---:|---:|---|
| sem_2s (↑) | 0.65 / 0.66 | 0.63 | 0.96 / 0.88 | 0.56 EC↑ | 0.70 | 1.00 | yes: +1 FFT/s |
| sem_8s (↑) | 0.72 / 0.90 | 0.65 | 1.00 / 0.99 | 0.72 EC↑ | 0.64 | 0.93 | yes: 8 s ring + 1 FFT/s |
| sem_fast_8s (↓) | 0.02 / 0.12 | 0.29 | 0.00 / 0.04 | 0.58 EC↑ | 0.71 | 0.93 | yes: 8 s ring + 1 FFT/s |
| sem_ratio_8s (↑) | 0.17 / 0.71 | 0.58 | 0.93 / 0.74 | 0.89 EC↑ | 0.70 | 0.93 | yes: 8 s ring + 1 FFT/s |
| veog_2s (↑) | 0.89 / 0.70 | 0.66 | 0.76 / 0.83 | 0.38 EC↓ | 0.77 | 1.00 | yes: +1 FFT/s |
| veog_8s (↑) | 0.99 / 0.98 | 0.66 | 0.96 / 0.92 | 0.41 EC↓ | 0.70 | 0.93 | yes: 8 s ring + 1 FFT/s |

#### false warnings (p90 guard) and within-recording spread

abs delta

| variant · feature | p90 warn clean → blink | clean → jaw | clean → head turn EO | clean → head turn EC | EO rest → blink (EO-matched) | UNIVERSE warn relax / stress | within-rec CV (clean) |
|---|---|---|---|---|---|---|---:|
| af · abs delta | 0.13 → 0.68 | 0.09 → 0.31 | 0.15 → 0.75 | 0.13 → 0.64 | 0.15 → 0.53 | 0.11 / 0.11 | 0.61 |
| af_gate · abs delta | 0.13 → 0.44 | 0.11 → 0.17 | 0.14 → 0.25 | 0.15 → 0.55 | 0.14 → 0.25 | 0.08 / 0.07 | 0.61 |
| tp · abs delta | 0.14 → 0.81 | 0.13 → 0.43 | 0.13 → 0.46 | 0.16 → 0.63 | 0.14 → 0.43 | 0.16 / 0.15 | 0.64 |
| all4 · abs delta | 0.12 → 0.78 | 0.11 → 0.40 | 0.13 → 0.54 | 0.16 → 0.68 | 0.14 → 0.49 | 0.16 / 0.15 | 0.57 |
| split · abs delta | 0.14 → 0.81 | 0.13 → 0.43 | 0.13 → 0.46 | 0.16 → 0.63 | 0.14 → 0.43 | 0.16 / 0.15 | 0.64 |
| med4 · abs delta | 0.12 → 0.87 | 0.10 → 0.40 | 0.12 → 0.45 | 0.14 → 0.68 | 0.12 → 0.47 | 0.17 / 0.16 | 0.52 |
| w4_var · abs delta | 0.14 → 0.86 | 0.10 → 0.35 | 0.14 → 0.63 | 0.16 → 0.71 | 0.15 → 0.47 | 0.14 / 0.14 | 0.56 |
| w4_hf · abs delta | 0.13 → 0.85 | 0.11 → 0.32 | 0.13 → 0.47 | 0.14 → 0.68 | 0.14 → 0.50 | 0.20 / 0.21 | 0.56 |
| w4_q · abs delta | 0.14 → 0.85 | 0.10 → 0.36 | 0.14 → 0.53 | 0.14 → 0.68 | 0.14 → 0.43 | 0.18 / 0.18 | 0.58 |
| gate4 · abs delta | 0.13 → 0.48 | 0.11 → 0.18 | 0.13 → 0.20 | 0.14 → 0.53 | 0.13 → 0.21 | 0.12 / 0.11 | 0.57 |
| bip · abs delta | 0.12 → 0.48 | 0.10 → 0.26 | 0.14 → 0.88 | 0.13 → 0.62 | 0.14 → 0.49 | 0.10 / 0.09 | 0.74 |
| tpbip · abs delta | 0.12 → 0.21 | 0.15 → 0.44 | 0.19 → 0.96 | 0.14 → 0.80 | 0.19 → 0.40 | 0.09 / 0.08 | 0.44 |
| car_tp · abs delta | 0.11 → 0.79 | 0.11 → 0.39 | 0.14 → 0.48 | 0.17 → 0.64 | 0.14 → 0.48 | 0.15 / 0.14 | 0.65 |
| tphp · abs delta | 0.13 → 0.86 | 0.12 → 0.43 | 0.13 → 0.45 | 0.15 → 0.61 | 0.13 → 0.46 | 0.16 / 0.15 | 0.62 |
| eogcal · abs delta | 0.13 → 0.88 | 0.12 → 0.44 | 0.20 → 0.77 | 0.17 → 0.65 | 0.20 → 0.81 | 0.17 / 0.17 | 0.60 |
| eogrun · abs delta | 0.13 → 0.79 | 0.12 → 0.43 | 0.20 → 0.65 | 0.18 → 0.62 | 0.21 → 0.48 | 0.15 / 0.14 | 0.61 |

abs theta

| variant · feature | p90 warn clean → blink | clean → jaw | clean → head turn EO | clean → head turn EC | EO rest → blink (EO-matched) | UNIVERSE warn relax / stress | within-rec CV (clean) |
|---|---|---|---|---|---|---|---:|
| af · abs theta | 0.11 → 0.71 | 0.08 → 0.28 | 0.14 → 0.63 | 0.14 → 0.52 | 0.15 → 0.39 | 0.12 / 0.11 | 0.40 |
| af_gate · abs theta | 0.12 → 0.44 | 0.08 → 0.15 | 0.12 → 0.20 | 0.14 → 0.39 | 0.12 → 0.17 | 0.08 / 0.08 | 0.41 |
| tp · abs theta | 0.15 → 0.77 | 0.13 → 0.34 | 0.15 → 0.35 | 0.12 → 0.39 | 0.15 → 0.27 | 0.16 / 0.16 | 0.44 |
| all4 · abs theta | 0.13 → 0.78 | 0.11 → 0.35 | 0.14 → 0.39 | 0.12 → 0.50 | 0.14 → 0.35 | 0.16 / 0.16 | 0.40 |
| split · abs theta | 0.15 → 0.77 | 0.13 → 0.34 | 0.15 → 0.35 | 0.12 → 0.39 | 0.15 → 0.27 | 0.16 / 0.16 | 0.44 |
| med4 · abs theta | 0.11 → 0.86 | 0.09 → 0.33 | 0.13 → 0.27 | 0.11 → 0.46 | 0.13 → 0.28 | 0.16 / 0.17 | 0.39 |
| w4_var · abs theta | 0.14 → 0.84 | 0.10 → 0.32 | 0.15 → 0.48 | 0.13 → 0.46 | 0.15 → 0.32 | 0.15 / 0.16 | 0.37 |
| w4_hf · abs theta | 0.14 → 0.85 | 0.12 → 0.26 | 0.13 → 0.32 | 0.11 → 0.38 | 0.13 → 0.31 | 0.22 / 0.25 | 0.39 |
| w4_q · abs theta | 0.14 → 0.85 | 0.12 → 0.33 | 0.13 → 0.34 | 0.11 → 0.46 | 0.13 → 0.26 | 0.19 / 0.20 | 0.40 |
| gate4 · abs theta | 0.12 → 0.43 | 0.11 → 0.17 | 0.13 → 0.16 | 0.14 → 0.30 | 0.13 → 0.15 | 0.12 / 0.13 | 0.39 |
| bip · abs theta | 0.10 → 0.49 | 0.08 → 0.22 | 0.15 → 0.80 | 0.16 → 0.51 | 0.15 → 0.39 | 0.10 / 0.08 | 0.52 |
| tpbip · abs theta | 0.20 → 0.12 | 0.13 → 0.29 | 0.26 → 0.93 | 0.14 → 0.61 | 0.27 → 0.30 | 0.10 / 0.09 | 0.40 |
| car_tp · abs theta | 0.14 → 0.78 | 0.12 → 0.34 | 0.16 → 0.37 | 0.11 → 0.46 | 0.16 → 0.33 | 0.16 / 0.15 | 0.43 |
| tphp · abs theta | 0.14 → 0.78 | 0.12 → 0.34 | 0.14 → 0.34 | 0.12 → 0.39 | 0.15 → 0.27 | 0.16 / 0.16 | 0.43 |
| eogcal · abs theta | 0.15 → 0.80 | 0.13 → 0.36 | 0.19 → 0.62 | 0.12 → 0.41 | 0.20 → 0.63 | 0.18 / 0.18 | 0.43 |
| eogrun · abs theta | 0.16 → 0.77 | 0.13 → 0.39 | 0.19 → 0.48 | 0.12 → 0.42 | 0.20 → 0.43 | 0.15 / 0.15 | 0.44 |

rel theta

| variant · feature | p90 warn clean → blink | clean → jaw | clean → head turn EO | clean → head turn EC | EO rest → blink (EO-matched) | UNIVERSE warn relax / stress | within-rec CV (clean) |
|---|---|---|---|---|---|---|---:|
| af · rel theta | 0.11 → 0.16 | 0.11 → 0.06 | 0.15 → 0.12 | 0.17 → 0.18 | 0.16 → 0.10 | 0.14 / 0.13 | 0.28 |
| af_gate · rel theta | 0.11 → 0.11 | 0.11 → 0.06 | 0.12 → 0.06 | 0.18 → 0.16 | 0.12 → 0.07 | 0.12 / 0.11 | 0.29 |
| tp · rel theta | 0.20 → 0.14 | 0.19 → 0.07 | 0.17 → 0.05 | 0.16 → 0.02 | 0.17 → 0.05 | 0.28 / 0.28 | 0.29 |
| all4 · rel theta | 0.17 → 0.14 | 0.17 → 0.05 | 0.16 → 0.05 | 0.15 → 0.07 | 0.16 → 0.05 | 0.22 / 0.22 | 0.23 |
| split · rel theta | 0.20 → 0.14 | 0.19 → 0.07 | 0.17 → 0.05 | 0.16 → 0.02 | 0.17 → 0.05 | 0.28 / 0.28 | 0.29 |
| med4 · rel theta | 0.15 → 0.14 | 0.17 → 0.05 | 0.16 → 0.05 | 0.14 → 0.07 | 0.16 → 0.05 | 0.21 / 0.22 | 0.25 |
| w4_var · rel theta | 0.15 → 0.15 | 0.13 → 0.06 | 0.15 → 0.07 | 0.19 → 0.13 | 0.16 → 0.09 | 0.15 / 0.14 | 0.23 |
| w4_hf · rel theta | 0.17 → 0.12 | 0.16 → 0.06 | 0.16 → 0.07 | 0.20 → 0.15 | 0.16 → 0.05 | 0.16 / 0.16 | 0.24 |
| w4_q · rel theta | 0.17 → 0.15 | 0.16 → 0.06 | 0.16 → 0.06 | 0.17 → 0.09 | 0.17 → 0.06 | 0.18 / 0.19 | 0.23 |
| gate4 · rel theta | 0.15 → 0.12 | 0.16 → 0.06 | 0.11 → 0.05 | 0.18 → 0.14 | 0.12 → 0.05 | 0.13 / 0.13 | 0.24 |
| bip · rel theta | 0.13 → 0.21 | 0.15 → 0.07 | 0.15 → 0.18 | 0.19 → 0.18 | 0.15 → 0.15 | 0.12 / 0.12 | 0.36 |
| tpbip · rel theta | 0.26 → 0.14 | 0.17 → 0.05 | 0.19 → 0.07 | 0.12 → 0.02 | 0.20 → 0.21 | 0.31 / 0.32 | 0.31 |
| car_tp · rel theta | 0.21 → 0.18 | 0.16 → 0.04 | 0.16 → 0.05 | 0.12 → 0.02 | 0.17 → 0.09 | 0.26 / 0.26 | 0.27 |
| tphp · rel theta | 0.20 → 0.14 | 0.20 → 0.06 | 0.18 → 0.05 | 0.17 → 0.02 | 0.18 → 0.06 | 0.28 / 0.29 | 0.29 |
| eogcal · rel theta | 0.19 → 0.14 | 0.18 → 0.05 | 0.16 → 0.04 | 0.16 → 0.02 | 0.16 → 0.10 | 0.26 / 0.27 | 0.29 |
| eogrun · rel theta | 0.18 → 0.24 | 0.18 → 0.05 | 0.15 → 0.05 | 0.16 → 0.02 | 0.15 → 0.17 | 0.28 / 0.30 | 0.29 |

TAR

| variant · feature | p90 warn clean → blink | clean → jaw | clean → head turn EO | clean → head turn EC | EO rest → blink (EO-matched) | UNIVERSE warn relax / stress | within-rec CV (clean) |
|---|---|---|---|---|---|---|---:|
| af · TAR | 0.12 → 0.67 | 0.13 → 0.17 | 0.12 → 0.33 | 0.12 → 0.40 | 0.12 → 0.29 | 0.13 / 0.12 | 0.36 |
| af_gate · TAR | 0.12 → 0.38 | 0.15 → 0.12 | 0.11 → 0.12 | 0.13 → 0.29 | 0.11 → 0.15 | 0.11 / 0.10 | 0.37 |
| tp · TAR | 0.24 → 0.93 | 0.18 → 0.28 | 0.11 → 0.04 | 0.24 → 0.20 | 0.12 → 0.18 | 0.22 / 0.21 | 0.47 |
| all4 · TAR | 0.23 → 0.91 | 0.17 → 0.30 | 0.11 → 0.15 | 0.21 → 0.34 | 0.11 → 0.23 | 0.17 / 0.16 | 0.36 |
| split · TAR | 0.25 → 0.87 | 0.19 → 0.21 | 0.13 → 0.13 | 0.21 → 0.19 | 0.13 → 0.20 | 0.21 / 0.21 | 0.41 |
| med4 · TAR | 0.18 → 0.90 | 0.18 → 0.28 | 0.12 → 0.13 | 0.21 → 0.37 | 0.12 → 0.22 | 0.17 / 0.17 | 0.37 |
| w4_var · TAR | 0.15 → 0.81 | 0.15 → 0.25 | 0.13 → 0.26 | 0.19 → 0.39 | 0.13 → 0.27 | 0.13 / 0.12 | 0.33 |
| w4_hf · TAR | 0.20 → 0.88 | 0.14 → 0.31 | 0.11 → 0.22 | 0.20 → 0.58 | 0.12 → 0.23 | 0.14 / 0.14 | 0.35 |
| w4_q · TAR | 0.19 → 0.88 | 0.17 → 0.29 | 0.13 → 0.21 | 0.20 → 0.34 | 0.13 → 0.24 | 0.15 / 0.14 | 0.35 |
| gate4 · TAR | 0.12 → 0.48 | 0.15 → 0.21 | 0.13 → 0.12 | 0.18 → 0.40 | 0.13 → 0.16 | 0.12 / 0.11 | 0.37 |
| bip · TAR | 0.12 → 0.45 | 0.12 → 0.17 | 0.15 → 0.56 | 0.12 → 0.41 | 0.16 → 0.36 | 0.13 / 0.13 | 0.48 |
| tpbip · TAR | 0.19 → 0.30 | 0.16 → 0.18 | 0.13 → 0.24 | 0.15 → 0.16 | 0.13 → 0.23 | 0.12 / 0.11 | 0.44 |
| car_tp · TAR | 0.19 → 0.88 | 0.14 → 0.24 | 0.11 → 0.08 | 0.20 → 0.18 | 0.11 → 0.22 | 0.21 / 0.21 | 0.44 |
| tphp · TAR | 0.24 → 0.93 | 0.18 → 0.28 | 0.11 → 0.06 | 0.23 → 0.19 | 0.11 → 0.18 | 0.21 / 0.21 | 0.44 |
| eogcal · TAR | 0.24 → 0.93 | 0.19 → 0.30 | 0.12 → 0.20 | 0.24 → 0.22 | 0.13 → 0.58 | 0.21 / 0.21 | 0.44 |
| eogrun · TAR | 0.23 → 0.84 | 0.19 → 0.29 | 0.13 → 0.13 | 0.24 → 0.22 | 0.13 → 0.24 | 0.20 / 0.19 | 0.43 |

(θ+α)/β

| variant · feature | p90 warn clean → blink | clean → jaw | clean → head turn EO | clean → head turn EC | EO rest → blink (EO-matched) | UNIVERSE warn relax / stress | within-rec CV (clean) |
|---|---|---|---|---|---|---|---:|
| af · (θ+α)/β | 0.11 → 0.58 | 0.09 → 0.09 | 0.18 → 0.49 | 0.18 → 0.52 | 0.18 → 0.36 | 0.11 / 0.10 | 0.32 |
| af_gate · (θ+α)/β | 0.11 → 0.29 | 0.09 → 0.06 | 0.14 → 0.17 | 0.18 → 0.40 | 0.15 → 0.16 | 0.09 / 0.07 | 0.33 |
| tp · (θ+α)/β | 0.18 → 0.67 | 0.14 → 0.03 | 0.12 → 0.01 | 0.15 → 0.05 | 0.12 → 0.17 | 0.27 / 0.27 | 0.38 |
| all4 · (θ+α)/β | 0.14 → 0.57 | 0.11 → 0.05 | 0.15 → 0.16 | 0.13 → 0.15 | 0.15 → 0.32 | 0.14 / 0.14 | 0.27 |
| split · (θ+α)/β | 0.16 → 0.54 | 0.12 → 0.05 | 0.16 → 0.14 | 0.13 → 0.12 | 0.16 → 0.28 | 0.16 / 0.17 | 0.28 |
| med4 · (θ+α)/β | 0.13 → 0.62 | 0.10 → 0.04 | 0.13 → 0.12 | 0.13 → 0.15 | 0.14 → 0.26 | 0.15 / 0.15 | 0.31 |
| w4_var · (θ+α)/β | 0.14 → 0.53 | 0.09 → 0.04 | 0.15 → 0.31 | 0.14 → 0.25 | 0.16 → 0.30 | 0.10 / 0.09 | 0.28 |
| w4_hf · (θ+α)/β | 0.14 → 0.57 | 0.10 → 0.05 | 0.14 → 0.26 | 0.15 → 0.28 | 0.14 → 0.27 | 0.12 / 0.12 | 0.28 |
| w4_q · (θ+α)/β | 0.15 → 0.55 | 0.12 → 0.05 | 0.15 → 0.23 | 0.13 → 0.18 | 0.16 → 0.27 | 0.14 / 0.14 | 0.28 |
| gate4 · (θ+α)/β | 0.13 → 0.27 | 0.13 → 0.04 | 0.13 → 0.15 | 0.15 → 0.24 | 0.13 → 0.16 | 0.10 / 0.09 | 0.30 |
| bip · (θ+α)/β | 0.12 → 0.39 | 0.12 → 0.15 | 0.16 → 0.71 | 0.19 → 0.55 | 0.16 → 0.36 | 0.11 / 0.11 | 0.43 |
| tpbip · (θ+α)/β | 0.25 → 0.08 | 0.19 → 0.05 | 0.18 → 0.26 | 0.13 → 0.08 | 0.18 → 0.21 | 0.24 / 0.19 | 0.37 |
| car_tp · (θ+α)/β | 0.22 → 0.72 | 0.13 → 0.03 | 0.13 → 0.04 | 0.08 → 0.06 | 0.14 → 0.23 | 0.24 / 0.24 | 0.36 |
| tphp · (θ+α)/β | 0.17 → 0.67 | 0.14 → 0.03 | 0.11 → 0.01 | 0.14 → 0.05 | 0.12 → 0.16 | 0.27 / 0.27 | 0.39 |
| eogcal · (θ+α)/β | 0.18 → 0.68 | 0.15 → 0.03 | 0.15 → 0.15 | 0.12 → 0.04 | 0.15 → 0.63 | 0.23 / 0.23 | 0.37 |
| eogrun · (θ+α)/β | 0.16 → 0.22 | 0.16 → 0.02 | 0.14 → 0.11 | 0.13 → 0.04 | 0.14 → 0.27 | 0.22 / 0.23 | 0.37 |

eye-movement features

| variant · feature | p90 warn clean → blink | clean → jaw | clean → head turn EO | clean → head turn EC | EO rest → blink (EO-matched) | UNIVERSE warn relax / stress | within-rec CV (clean) |
|---|---|---|---|---|---|---|---:|
| sem_2s (↑) | 0.14 → 0.37 | 0.10 → 0.25 | 0.14 → 0.82 | 0.11 → 0.55 | 0.14 → 0.44 | 0.09 / 0.08 | 1.04 |
| sem_8s (↑) | 0.18 → 0.37 | 0.13 → 0.27 | 0.17 → 0.82 | 0.16 → 0.64 | 0.17 → 0.55 | 0.10 / 0.09 | 0.87 |
| sem_fast_8s (↓) | 0.31 → 0.07 | 0.37 → 0.19 | 0.30 → 0.00 | 0.23 → 0.05 | 0.28 → 0.10 | 0.22 / 0.24 | 0.53 |
| sem_ratio_8s (↑) | 0.21 → 0.08 | 0.20 → 0.21 | 0.17 → 0.48 | 0.20 → 0.41 | 0.16 → 0.34 | 0.11 / 0.11 | 0.70 |
| veog_2s (↑) | 0.13 → 0.65 | 0.11 → 0.32 | 0.14 → 0.40 | 0.13 → 0.50 | 0.14 → 0.46 | 0.14 / 0.12 | 0.96 |
| veog_8s (↑) | 0.12 → 0.63 | 0.15 → 0.36 | 0.16 → 0.59 | 0.18 → 0.62 | 0.16 → 0.58 | 0.14 / 0.14 | 0.82 |
