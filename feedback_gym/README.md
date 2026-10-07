# feedback_gym

Offline quality harness for neurofeed catalog **protocols** (compositions) and
**features** (including orphans / AI / Crown device.*).

Does **not** retrain heads. Does **not** touch the Flutter ship path.
Does **not** run the CBraMod encoder (uses `emb_cache` + linear `.f32bin` heads).

## One command

```bash
cd feedback_gym && python3 runners/run_gym.py
```

Default corpus: synthetic demo. Regenerates:

| Artifact | Path |
|----------|------|
| Living stats | `PROTOCOL_STATS.md` |
| UI data | `ui/data/latest.json` |
| Run folder | `results/<run_id>/` |

## Sleep-EDF (real corpus)

Requires sibling [`muse-eeg-heads`](../muse-eeg-heads) on the worker (windows +
`emb_cache` + `band_math`). Built NPZ is **gitignored**.

```bash
cd feedback_gym

# Build only (full test split; optional cap for speed)
python3 runners/build_corpus_sleep_edf.py
python3 runners/build_corpus_sleep_edf.py --max-windows-per-rec 500

# Build if missing, then run
python3 runners/run_gym.py --preset sleep-edf-test
python3 runners/run_gym.py --preset sleep-edf-test --max-windows-per-rec 500

# Or point at an existing NPZ
python3 runners/run_gym.py --corpus corpora/external/sleep_edf_test.npz
```

AI columns: `emb @ W.T + b` → softmax → `ai_a_vig` / `ai_drowsiness` =
P(hypnagogic), `ai_wake_light` = P(light). Head layout W(2,200) in the pack
`.f32bin` files. REVE columns absent → treated as unavailable.

Calibration (default since the fair round): **per recording**, each
recording's leading wake run, ≤90 rows (45 s at the 0.5 s window hop), written
as `cal_starts`/`cal_lens`. Recordings that start in N1 have no baseline and are
not scored. `--cal-mode global` rebuilds the old corpus, where the first
`cal_n=90` rows of the whole stream (one recording) were the baseline for all
20. `--from-npz <old.npz>` adds per-recording cal to an existing NPZ.

## Fair band-math round

```bash
python3 runners/fair_round.py [--catalog ../assets/protocols.json]
```

Scores every band feature as a sleep / drowsiness guard in **both** directions,
with per-recording baselines, next to `ai.*` on the same rows, plus Lee / UNIVERSE.
Results and the audit: [`FAIR_BANDMATH.md`](FAIR_BANDMATH.md).

## Pad-mixing round (Muse artifact robustness)

```bash
python3 runners/pad_mix_round.py        # needs Lee / UNIVERSE built with neurofeed-gym-corpora --pad-mix
uv run --with numpy --with scipy --with mne --with pyyaml python runners/sleep_edf_heog.py   # HEOG positive control
```

Scores δ / θ / rel θ / TAR / (θ+α)/β from 16 pad combinations (TP-only, 4-pad
mean / median / weighted / quality-gated, bipolar AF7−AF8 and TP9−TP10, EOG
regression) and slow-eye-movement features against blinks, jaw clench, head
turns, eye closure and test-retest stability. Artifact robustness only: no
Muse sleep labels exist. See `FAIR_BANDMATH.md`, "Pad mixing".

If Sleep-EDF paths are missing, `--preset sleep-edf-test` falls back to the
synthetic demo with a warning.

## Sibling corpora (findings-only)

Extra labeled EEG with relaxed licenses (CC-BY / CC0 / ODC-By) lives in the
private sibling repo
[`windwerfer/neurofeed-gym-corpora`](https://github.com/windwerfer/neurofeed-gym-corpora):
manifests, license notes, and builders that emit the gym NPZ schema. **The gym
here is still the only scorer.** Builder and band-math code stay in that repo
and in `muse-eeg-heads`, and are never copied into neurofeed.

```bash
cd feedback_gym

# corpus root defaults to $NEUROFEED_GYM_CORPORA or ../neurofeed-gym-corpora (next to neurofeed)
python3 runners/run_gym.py --preset lee2026-eo-ec --corpus-root ../../neurofeed-gym-corpora

# several corpora -> results/<ts>_<preset>/ each + results/<ts>_multi/multi_board.json
# + MULTI_CORPUS_STATS.md (side-by-side scores; N/A where a corpus lacks a feature, e.g. ai.*)
python3 runners/run_gym.py --presets sleep-edf-test,lee2026-eo-ec,lee2026-artifacts
```

| preset | NPZ (gitignored) | builder in corpora repo |
|--------|------------------|-------------------------|
| `lee2026-eo-ec` | `corpora/external/lee2026_eo_ec.npz` | `builders/build_lee2026.py --out-eo-ec` |
| `lee2026-artifacts` | `corpora/external/lee2026_artifacts.npz` | `builders/build_lee2026.py --out-artifacts` |
| `universe-stress` | `corpora/external/universe_stress.npz` | `builders/build_universe.py` |

If the NPZ is missing, the run stops (exit 2) and prints the exact command,
e.g. `uv run --with numpy --with mne python <corpus-root>/builders/build_lee2026.py --out-eo-ec .../lee2026_eo_ec.npz` (Lee needs `mne`; UNIVERSE runs with plain `python3`)
(the flag comes from `out_flag` in the manifest entry, default `--out`).
It never falls back to synthetic data. `--presets` checks every corpus before
it scores anything, and leaves `PROTOCOL_STATS.md` / `ui/data/latest.json`
untouched. Corpora that ship `cal_starts`/`cal_lens` are scored with
per-recording calibration (see [`metrics.md`](metrics.md)).

**Rule:** only aggregates (scores, sep, percentile bands, keep/merge/kill
evidence) land in neurofeed. Raw EEG, windows, embeddings, built NPZs, and
anything NC-licensed, gated, or with an unclear license **never** do.
Lab-only corpora cannot back a product-facing protocol until the result is
re-validated on a permissive corpus. Registered in `corpora/manifest.json`
→ `external[]` with license + `findings-only`.

## Open the UI

Open `feedback_gym/ui/index.html` in a browser (static; no Flutter).

If `file://` blocks fetch of `data/latest.json`, serve locally:

```bash
cd feedback_gym/ui && python3 -m http.server 8765
# then http://127.0.0.1:8765/
```

### Compare runs

1. Run the gym at least twice (any corpus/preset) so `results/` has ≥2 folders.
2. Each run writes `results/<id>/summary.json` and refreshes `ui/data/runs_index.json`.
3. Open the **Compare** tab → pick Run A / Run B → protocol final Δ and feature
   score/sep/best_p Δ tables. Serve `ui/` over HTTP so `../results/` fetches work.

## Tests

```bash
cd /path/to/neurofeed && python3 -m pytest feedback_gym/tests -q
```

## Metrics

See [`metrics.md`](metrics.md) before interpreting scores.

## Corpus schema

See `corpora/manifest.json`. Synthetic demo ships under `corpora/synthetic/`.

## Layout

```
feedback_gym/
  metrics.md
  PROTOCOL_STATS.md
  MULTI_CORPUS_STATS.md        # written by --presets (side-by-side board)
  runners/run_gym.py
  runners/build_corpus_sleep_edf.py
  sweeps/grids.yaml
  corpora/
  results/
  ui/
  tests/
```
