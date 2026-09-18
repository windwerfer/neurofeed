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

Calibration: first `cal_n=90` samples of the concatenated test stream
(sessions typically start wake / low-y).

If Sleep-EDF paths are missing, `--preset sleep-edf-test` falls back to the
synthetic demo with a warning.

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
  runners/run_gym.py
  runners/build_corpus_sleep_edf.py
  sweeps/grids.yaml
  corpora/
  results/
  ui/
  tests/
```
