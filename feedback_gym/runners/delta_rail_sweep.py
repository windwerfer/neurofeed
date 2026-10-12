#!/usr/bin/env python3
"""Relative-delta rail ceiling sweep (2026-10).

The app delta rail compared absolute frontal delta (µV²) to 0.25 and fired on
~100 % of rows everywhere. This sweeps a *relative* delta ceiling
(delta ÷ total band power) for the rail, warn while rel_delta > ceiling:

  Sleep-EDF (fair, per-recording cal; cal rows not scored): `app_delta_rel`
    (app band math, Fpz-Cz: not Muse, no pad gate). W vs N1: per-recording
    balanced accuracy (median), warn rate on W and N1.
  Lee 2026 Muse 2 (awake only): AF7/AF8 relative delta behind the app pad
    quality gate (pads with quality >= 80, as live; `pad_mix_round.af_gate`).
    Every warning here is a false alarm: eyes-open rest, eyes-closed rest,
    clean rest, cued artifact task. Coverage = rows with a usable AF pad.

Run: python feedback_gym/runners/delta_rail_sweep.py [--md out.md]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

GYM = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(GYM))

from runners.helpers import build_cal_plan, load_corpus  # noqa: E402
from runners.pad_mix_round import Q_USABLE, _bands, _pool, _rel  # noqa: E402

EXTERNAL = GYM / "corpora" / "external"
CEILINGS = [round(0.30 + 0.05 * i, 2) for i in range(13)]  # 0.30 … 0.90


def af_gate_rel_delta(c: dict) -> np.ndarray:
    P = np.stack([_bands(c, f"ch_{p}") for p in ("af7", "af8")])
    w = np.stack([(np.asarray(c[f"ch_{p}_q"], dtype=float) >= Q_USABLE).astype(float) for p in ("af7", "af8")])
    return _pool(_rel(P), "weighted", w)[:, 0]


def play_mask(c: dict) -> np.ndarray:
    plan = build_cal_plan(c)
    m = np.zeros(len(c["labels"]), dtype=bool)
    m[plan.play_idx] = True
    return m


def ba(warn: np.ndarray, y: np.ndarray) -> float | None:
    if not (y == 0).any() or not (y == 1).any():
        return None
    return 0.5 * (float(warn[y == 1].mean()) + float(1 - warn[y == 0].mean()))


def sleep_edf(ceil: float, c: dict, x: np.ndarray, play: np.ndarray) -> dict:
    y = np.asarray(c["labels"])
    rid = np.asarray(c["recording_id"]).astype(str)
    ok = play & np.isfinite(x)
    warn = x > ceil
    bas = [b for r in np.unique(rid[ok]) if (b := ba(warn[ok & (rid == r)], y[ok & (rid == r)])) is not None]
    return {
        "ba_med": float(np.median(bas)),
        "warn_w": float(warn[ok & (y == 0)].mean()),
        "warn_n1": float(warn[ok & (y == 1)].mean()),
    }


def lee(ceil: float, c: dict, x: np.ndarray, play: np.ndarray) -> tuple[float, float]:
    y = np.asarray(c["labels"])
    ok = play & np.isfinite(x)
    warn = x > ceil
    return float(warn[ok & (y == 0)].mean()), float(warn[ok & (y == 1)].mean())


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--md", type=Path)
    a = ap.parse_args(argv)
    se = load_corpus(EXTERNAL / "sleep_edf_test.npz")
    se_x, se_play = np.asarray(se["app_delta_rel"], dtype=float), play_mask(se)
    eo = load_corpus(EXTERNAL / "lee2026_eo_ec.npz")
    art = load_corpus(EXTERNAL / "lee2026_artifacts.npz")
    eo_x, eo_play = af_gate_rel_delta(eo), play_mask(eo)
    art_x, art_play = af_gate_rel_delta(art), play_mask(art)
    cov = [float(np.isfinite(v[p]).mean()) for v, p in ((eo_x, eo_play), (art_x, art_play))]
    absr = np.asarray(se["delta_abs"], dtype=float)
    lines = [
        f"Lee AF gate coverage: EO/EC {cov[0]:.2f}, artifacts {cov[1]:.2f}. "
        f"Old absolute rail (delta_abs > 0.25) on Sleep-EDF play rows: "
        f"{float((absr[se_play] > 0.25).mean()):.2f}.",
        "",
        "| ceiling (rel δ) | Sleep-EDF BA W/N1 per-rec median | warn W | warn N1 | Lee EO rest | Lee EC rest | Lee clean rest | Lee artifact task |",
        "|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for ceil in CEILINGS:
        m = sleep_edf(ceil, se, se_x, se_play)
        l_eo, l_ec = lee(ceil, eo, eo_x, eo_play)
        l_clean, l_art = lee(ceil, art, art_x, art_play)
        lines.append(
            f"| {ceil:.2f} | {m['ba_med']:.3f} | {m['warn_w']:.2f} | {m['warn_n1']:.2f} | "
            f"{l_eo:.2f} | {l_ec:.2f} | {l_clean:.2f} | {l_art:.2f} |"
        )
    md = "\n".join(lines)
    print(md)
    if a.md:
        a.md.write_text(md + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
