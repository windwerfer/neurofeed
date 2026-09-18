# feedback_gym

Offline quality harness for neurofeed catalog **protocols** (compositions) and
**features** (including orphans / AI / Crown device.*).

Does **not** retrain heads. Does **not** touch the Flutter ship path.

## One command

```bash
cd feedback_gym && python3 runners/run_gym.py
```

Regenerates:

| Artifact | Path |
|----------|------|
| Living stats | `PROTOCOL_STATS.md` |
| UI data | `ui/data/latest.json` |
| Run folder | `results/<run_id>/` |

## Open the UI

Open `feedback_gym/ui/index.html` in a browser (static; no Flutter).

If `file://` blocks fetch of `data/latest.json`, serve locally:

```bash
cd feedback_gym/ui && python3 -m http.server 8765
# then http://127.0.0.1:8765/
```

## Tests

```bash
cd /path/to/neurofeed && python3 -m pytest feedback_gym/tests -q
```

## Metrics

See [`metrics.md`](metrics.md) before interpreting scores.

## Corpus

Default: synthetic demo NPZ (`corpora/synthetic/`). To use a real export:

```bash
python3 runners/run_gym.py --corpus /path/to/session.npz
```

Schema: `corpora/manifest.json`. Sibling pear corpora live under
`muse-eeg-heads/band_math/` when present on the worker.

## Layout

```
feedback_gym/
  metrics.md
  PROTOCOL_STATS.md
  runners/run_gym.py
  sweeps/grids.yaml
  corpora/
  results/
  ui/
  tests/
```
