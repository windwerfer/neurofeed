#!/usr/bin/env python3
"""CBraMod AI-head columns (ai_a_vig, ai_wake_light) for the Lee 2026 Muse 2
gym corpora, row-aligned with lee2026_eo_ec.npz / lee2026_artifacts.npz.

The Lee builder (neurofeed-gym-corpora/builders/build_lee2026.py) emits band
columns only. This script replays its segmentation (2 s windows, 1 s hop per
segment, same segment order) and scores every window like the app does:

  raw µV @ 256 Hz -> app-style conditioning on the whole recording
  (2nd-order Butterworth high-pass 0.5 Hz + Q=10 notches at 50/60/100/120 Hz,
  i.e. the undecided-mains state of rust/src/analysis/eeg_filter.rs)
  -> AF7, AF8, TP9, TP10 window (4, 512) -> frozen CBraMod (linear resample to
  200 Hz, 2 patches) -> mean-pool 200-d -> shipped linear heads -> P(class 1).

Two stages (separate interpreters, because mne and torch live in different
environments here):

  uv run --with numpy --with mne --with scipy python \
      feedback_gym/runners/lee_ai_columns.py windows --out /tmp/lee_windows.npz
  /path/to/python-with-torch feedback_gym/runners/lee_ai_columns.py score \
      --windows /tmp/lee_windows.npz

`score` writes sidecars next to the corpora (`lee2026_eo_ec_ai.npz`,
`lee2026_artifacts_ai.npz`; gitignored like every external NPZ) holding
`ai_a_vig`, `ai_wake_light`, `recording_id`, `segment`, `labels`, row-aligned
with the base NPZ (checked by recording/segment/label equality).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
EXTERNAL = REPO_ROOT / "feedback_gym" / "corpora" / "external"
GYM_CORPORA = Path("/workspace/neurofeed-gym-corpora")
MUSE_EEG_HEADS = Path("/workspace/muse-eeg-heads")
PACK = REPO_ROOT / "assets" / "packs" / "cbramod-a-vig-full" / "heads"
HEAD_A = PACK / "head_a_vig_linear.f32bin"
HEAD_C = PACK / "head_c_wake_light_linear.f32bin"
SR = 256.0
WIN = 512
HOP = 256


def condition(x: np.ndarray) -> np.ndarray:
    """App-style streaming conditioning (causal), per channel."""
    from scipy import signal

    sos = signal.butter(2, 0.5, btype="highpass", fs=SR, output="sos")
    y = np.empty_like(x, dtype=np.float64)
    for c in range(x.shape[0]):
        row = x[c].astype(np.float64)
        zi = signal.sosfilt_zi(sos) * row[: int(SR // 2)].mean()
        v, _ = signal.sosfilt(sos, row, zi=zi)
        for f0 in (50.0, 60.0, 100.0, 120.0):
            b, a = signal.iirnotch(f0, 10.0, fs=SR)
            v = signal.lfilter(b, a, v)
        y[c] = v
    return y


def windows_of(x: np.ndarray) -> np.ndarray:
    t = x.shape[1]
    if t < WIN:
        return np.zeros((0, x.shape[0], WIN), dtype=np.float32)
    starts = np.arange(0, t - WIN + 1, HOP)
    return np.stack([x[:, s : s + WIN] for s in starts]).astype(np.float32)


def stage_windows(raw_dir: Path, out: Path) -> None:
    sys.path.insert(0, str(GYM_CORPORA / "builders"))
    import build_lee2026 as lee  # noqa: PLC0415

    subs = sorted(p.name for p in (raw_dir / "sourcedata").iterdir() if p.is_dir())
    acc = {k: {"X": [], "rid": [], "seg": [], "lab": []} for k in ("eo_ec", "artifacts")}

    def add(kind: str, rid: str, lab: int, xw: np.ndarray, seg: str) -> None:
        a = acc[kind]
        a["X"].append(xw)
        a["rid"].append(np.full(len(xw), rid, dtype=object))
        a["seg"].append(np.full(len(xw), seg, dtype=object))
        a["lab"].append(np.full(len(xw), lab, dtype=np.int32))

    for sub in subs:
        recs = {}
        for task in lee.TASKS:
            r, _why = lee.load_recording(raw_dir, sub, task)
            if r is not None:
                x, ph = r
                recs[task] = (condition(x), ph)
        if "MVO" in recs and "MVC" in recs:
            rid = f"lee2026/{sub}"
            for task, lab in (("MVO", 0), ("MVC", 1)):
                x, ph = recs[task]
                for phase in ("pre_rest", "post_rest"):
                    a, b = ph[phase]
                    add("eo_ec", rid, lab, windows_of(x[:, a:b]), f"{task}/{phase}")
        for task, (x, ph) in recs.items():
            rid = f"lee2026/{sub}/{task}"
            for phase, lab in (("pre_rest", 0), ("task", 1), ("post_rest", 0)):
                a, b = ph[phase]
                seg = f"{task}/{phase}/{lee.ARTIFACT[task] if lab else 'eyes_' + lee.EYES_REST[task]}"
                add("artifacts", rid, lab, windows_of(x[:, a:b]), seg)
        print(f"{sub}: {sorted(recs)}", flush=True)

    arrays = {}
    for kind, a in acc.items():
        arrays[f"{kind}_X"] = np.concatenate(a["X"])
        arrays[f"{kind}_rid"] = np.concatenate(a["rid"]).astype(str)
        arrays[f"{kind}_seg"] = np.concatenate(a["seg"]).astype(str)
        arrays[f"{kind}_lab"] = np.concatenate(a["lab"])
    np.savez(out, **arrays)
    print({k: v.shape for k, v in arrays.items()})


def load_linear_head(path: Path) -> tuple[np.ndarray, np.ndarray]:
    f = np.fromfile(path, dtype="<f4")
    d = (f.size - 2) // 2
    return f[: 2 * d].reshape(2, d).astype(np.float64), f[2 * d :].astype(np.float64)


def p_class1(emb: np.ndarray, W: np.ndarray, b: np.ndarray) -> np.ndarray:
    z = emb @ W.T + b
    z -= z.max(axis=1, keepdims=True)
    e = np.exp(z)
    return e[:, 1] / e.sum(axis=1)


def encoder(weights: Path):
    sys.path.insert(0, str(MUSE_EEG_HEADS))
    from src.cbramod_encoder import FrozenCBraModEncoder  # noqa: PLC0415

    return FrozenCBraModEncoder(weights, source_sr=SR, pool="mean")


def embed(enc, X: np.ndarray, batch: int = 64) -> np.ndarray:
    import torch  # noqa: PLC0415

    torch.set_num_threads(4)
    out = []
    for i in range(0, len(X), batch):
        out.append(enc(torch.from_numpy(X[i : i + batch])).numpy().astype(np.float64))
        if (i // batch) % 40 == 0:
            print(f"  {i}/{len(X)}", flush=True)
    return np.concatenate(out)


def stage_score(windows: Path, weights: Path) -> None:
    W_a, b_a = load_linear_head(HEAD_A)
    W_c, b_c = load_linear_head(HEAD_C)
    enc = encoder(weights)
    w = np.load(windows, allow_pickle=False)
    for kind, base in (("eo_ec", "lee2026_eo_ec"), ("artifacts", "lee2026_artifacts")):
        ref = np.load(EXTERNAL / f"{base}.npz", allow_pickle=True)
        rid, seg, lab = w[f"{kind}_rid"], w[f"{kind}_seg"], w[f"{kind}_lab"]
        if not (
            len(rid) == len(ref["labels"])
            and np.array_equal(rid, ref["recording_id"].astype(str))
            and np.array_equal(seg, ref["segment"].astype(str))
            and np.array_equal(lab, ref["labels"])
        ):
            raise SystemExit(f"{kind}: windows not row-aligned with {base}.npz ({len(rid)} vs {len(ref['labels'])})")
        emb = embed(enc, w[f"{kind}_X"])
        out = EXTERNAL / f"{base}_ai.npz"
        np.savez_compressed(
            out,
            ai_a_vig=p_class1(emb, W_a, b_a),
            ai_wake_light=p_class1(emb, W_c, b_c),
            recording_id=rid.astype(object),
            segment=seg.astype(object),
            labels=lab,
            conditioning=np.array("app-style: HP 0.5 Hz (2nd-order Butterworth) + notch Q10 50/60/100/120 Hz, causal"),
        )
        print(f"wrote {out} n={len(rid)}")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = p.add_subparsers(dest="cmd", required=True)
    pw = sp.add_parser("windows")
    pw.add_argument("--raw-dir", type=Path, default=GYM_CORPORA / "raw" / "lee2026")
    pw.add_argument("--out", type=Path, required=True)
    ps = sp.add_parser("score")
    ps.add_argument("--windows", type=Path, required=True)
    ps.add_argument(
        "--weights",
        type=Path,
        default=MUSE_EEG_HEADS / "kaggle_datasets/muse-eeg-heads-cache/models/CBraMod/pretrained_weights.pth",
    )
    a = p.parse_args(argv)
    if a.cmd == "windows":
        stage_windows(a.raw_dir, a.out)
    else:
        stage_score(a.windows, a.weights)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
