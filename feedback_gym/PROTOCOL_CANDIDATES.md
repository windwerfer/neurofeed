# PROTOCOL_CANDIDATES

Evidence-backed protocol catalog draft for neurofeed.
**Recipes only** — user-facing copy comes later.
Generated for curation (2026-10-05). Do not ship unbacked placeholders.

Sources pooled:

| Source | What it backs |
|--------|----------------|
| `feedback_gym` Sleep-EDF run (`PROTOCOL_STATS.md`, ~61k windows) | AI sleep tripwire (`ai.a_vig` / wake_light); band ATR/α/BTR; TAR weak; `band.delta` weak as sole guard |
| pear band_math compare (`a_vig`, MW attention, med-rest, med-depth, `a_eng`) | BTR/ATR for attention; AI >> band for sleep; engagement thin; no stress→calm yet |
| diggus findings-only corpus survey (2026-10-05) | Future: alkabbany / UNIVERSE → stress; ATTLAPSE/ROAMM → MW; Lee 2026 → EO/EC + artifacts. Lab-only (BY-NC/gated) stays out of product claims |

**Rule:** nothing that only sounds good. Product claims need sep on OK-findings (CC0/CC-BY/ODC) corpora, re-validated if lab-only sets informed thresholds.

---

## Proposed catalog

### User programs (evidence now)

| # | id | User job | Reward | Inhibit | Guard | Calibration | Evidence | Action vs today |
|---|----|----------|--------|---------|-------|-------------|----------|-----------------|
| 1 | `sleepGuard` | Pure fall-asleep tripwire (personal / Yoga-Nidra edge) | — | — | `ai.a_vig` (~p75–p95 of rest baseline); optional δ rail secondary only | `eyes-closed-01` **staged** (artifacts → EO clear → EC rest) | Sleep-EDF: `ai.a_vig` score ~0.79, sep ~0.85; δ-as-guard ~0.43 | **ADD** (replaces δ-default `guardrailOnly` as the real tripwire) |
| 2 | `restAwake` | Calm rest without dozing | `band.atr` | — | `ai.a_vig` | `eyes-closed-01` staged when AI guard on | ATR reward OK; AI guard >> δ | **REPLACE** `drowsiness` (swap guard default off δ) |
| 3 | `openMonitor` | Soft awareness / mindfulness | `band.alpha` | — | `ai.a_vig` (light) | `eyes-closed-01` | α best reward score on Sleep-EDF board | **REPLACE** `mindfulness` |
| 4 | `alertOpen` | Eyes-open alertness | `band.btr` | — | — | `eyes-open-01` single | Strongest gym composite; MW attention favors BTR | **KEEP** `alertnessOpen` |
| 5 | `alertClosed` | Eyes-closed stay-sharp | `band.btr` | — | `ai.a_vig` | `eyes-closed-01` | BTR + real sleep tripwire | **KEEP** shape of `alertnessClosed`; fix guard |
| 6 | `concentrate` | Steady attention, less grinding | `band.alpha` | `betaCeiling` (~0.25) | `ai.a_vig` optional | `eyes-closed-01` | Inhibit path real; “focus” claim modest until ATTLAPSE/ROAMM gym | **KEEP** `concentration`; drop δ default |

### Utility (keep — not training programs)

| # | id | User job | Reward / Guard | Calibration | Notes | Action |
|---|----|----------|----------------|-------------|-------|--------|
| 7 | `calibrateRecord` | **Calibration + record** — staged baseline then quiet recording; doubles as **AI labeling baseline** until a better capture flow exists | — / — | **`staged` required** (not skippable): artifacts → eyes-open clear/active → eyes-closed rest (`eyes-closed-01.staged`) | **Not** the same as `recordOnly`. Always runs full staged cal so sessions carry clear/rest anchors for later head / threshold work | **RE-ADD / promote** as first-class (distinct from optional-cal record) |
| 8 | `recordOnly` | Quiet record, no feedback | — / — | `eyes-closed-01` single; **skippable** | Optional metadata baseline only; no AI-anchor stages | **KEEP** (data dump / unstructured) |

### Reserved (add only after findings)

| # | id | User job | Blocker | Diggus priority ingest |
|---|----|----------|---------|------------------------|
| 9 | `stressDownshift` | Stressed → downshift / relax | No clean stress label in current gym | alkabbany Muse-S (CC-BY), then UNIVERSE |
| — | med-depth / absorption / FA–OM twins | Meditation-type depth claims | Lab-only (L-FAME BY-NC, gated EEGMeditation) or weak med-depth AI | Lab findings OK; product only after permissive re-val |

### Drop / merge / hide

| id (today) | Decision | Why |
|------------|----------|-----|
| `twilight` | **DROP** (lab-only until labeled) | TAR reward ~0.18 on Sleep-EDF; no trusted twilight label |
| `relaxedConcentration` | **MERGE away** into `restAwake` + `concentrate` | Weaker composite; overlaps both |
| `drowsiness` | **Absorb** into `restAwake` | Name/recipe replaced; δ guard wrong default |
| `mindfulness` | **Absorb** into `openMonitor` | Same |
| `guardrailOnly` | **Absorb** into `sleepGuard` | Same job; must use AI not δ-only |
| `recordOnly` as “calibration substitute” | **No** — use `calibrateRecord` for staged AI baselines | Different product job |

Optional second rest depth (`deepRest`): **do not add** unless we want two rest faces; prefer one `restAwake`.

---

## Shape (ASCII)

```
User-facing training (6):
  sleepGuard | restAwake | openMonitor | alertOpen | alertClosed | concentrate

Utility (2):
  calibrateRecord   ← staged cal + record (AI labeling baseline)
  recordOnly        ← optional/skip cal, quiet dump

Reserved (1):
  stressDownshift   ← after alkabbany/UNIVERSE findings

Dropped from face:
  twilight | relaxedConcentration | drowsiness | mindfulness | guardrailOnly-as-δ
```

Default AI guard engine for ship: Spur A `ai.a_vig` (REVE subsample = directional lab only).
Percentiles: start from gym best_p / pear sweeps (often ~p50 reward, ~p75–p95 guard); lock after AI-guard protocol variants in the gym matrix.

---

## Next gym levers (not blocking this doc)

1. Score catalog variants with **guard = `ai.a_vig`** as first-class.
2. Presets for pear attention + med-rest corpora (same harness as Sleep-EDF).
3. Findings-only ingest: alkabbany → stress candidate; ATTLAPSE/ROAMM → concentrate keep/kill.
4. Wire `calibrateRecord` session tagging so exports are labeled for AI baseline pipelines.

Copy / `protocols.json` rewrite: **after** this candidate list is approved.
