#!/usr/bin/env python3
"""Band-stability test (STABILITY.md).

Hypothesis: moment-to-moment band variability (not band level) tracks attention.
For every probe epoch (the pre-probe rows of one thought probe, gated like the
app), per feature: SD over rows and MASD (mean |successive difference|),
z-scored within recording. Reported:
  1. per-recording AUC P(variability | mind-wandering > on-task) (label 1 vs 0),
  2. same for drowsy (self-rating) vs not,
  3. expert/meditator vs novice: per-recording median epoch variability, MWU AUC.
Writes results/<ts>_stability/stability.json + stability_tables.md.
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from math import comb

GYM_ROOT = Path(__file__).resolve().parent.parent
if str(GYM_ROOT) not in sys.path:
    sys.path.insert(0, str(GYM_ROOT))
from runners.helpers import load_corpus  # noqa: E402

EXT = GYM_ROOT / "corpora" / "external"
CORPORA = {"ds001787-mw-muse": EXT / "ds001787_mw_muse.npz", "ds001787-mw-crown": EXT / "ds001787_mw_crown.npz",
           "rl2021-mw-muse": EXT / "rl2021_mw_muse.npz"}
FEATS = ("alpha_rel", "theta_rel", "delta_rel", "beta_rel", "band_atr", "band_tar", "band_btr")
MIN_ROWS = 5


def epochs(c):
    rid = np.asarray(c["recording_id"]).astype(str)
    pid = np.asarray(c["probe_id"]).astype(int)
    ok = (np.asarray(c["label_valid"]).astype(bool) if "label_valid" in c else np.ones(len(pid), bool)) & (pid >= 0)
    y = np.asarray(c["labels"]).astype(int)
    dr = np.asarray(c["drowsy"]).astype(float) if "drowsy" in c else np.full(len(y), np.nan)
    grp = np.asarray(c["group"]).astype(str)
    keys = {}
    for i in np.flatnonzero(ok):
        keys.setdefault((rid[i], pid[i]), []).append(i)
    out = []
    for (r, p), idx in keys.items():
        idx = np.array(idx)
        if idx.size < MIN_ROWS:
            continue
        e = {"rid": r, "y": int(np.bincount(y[idx]).argmax()), "drowsy": float(np.nanmax(dr[idx])) if np.isfinite(dr[idx]).any() else np.nan,
             "group": grp[idx[0]]}
        for f in FEATS:
            if f not in c:
                continue
            v = np.asarray(c[f], float)[idx]
            v = v[np.isfinite(v)]
            if v.size < MIN_ROWS:
                continue
            e[f"sd:{f}"] = float(v.std())
            e[f"masd:{f}"] = float(np.abs(np.diff(v)).mean())
            e[f"mean:{f}"] = float(v.mean())
        out.append(e)
    return out


def auc(a, b):
    a, b = np.asarray(a), np.asarray(b)
    if a.size == 0 or b.size == 0:
        return None
    return float(((a[:, None] > b[None, :]).sum() + 0.5 * (a[:, None] == b[None, :]).sum()) / (a.size * b.size))


def sign_p(x):
    """Two-sided sign test of x vs 0 (ties dropped)."""
    x = np.asarray(x)
    x = x[x != 0]
    n, k = x.size, int((x > 0).sum())
    if n == 0:
        return None
    t = min(k, n - k)
    return float(min(1.0, 2 * sum(comb(n, i) for i in range(t + 1)) / 2**n))


def perm_p(a, b, n=2000, seed=0):
    a, b = np.asarray(a, float), np.asarray(b, float)
    if a.size == 0 or b.size == 0:
        return None
    rng = np.random.default_rng(seed)
    z = np.r_[a, b]
    obs = abs(auc(a, b) - 0.5)
    hits = 0
    for _ in range(n):
        rng.shuffle(z)
        hits += abs(auc(z[: a.size], z[a.size :]) - 0.5) >= obs - 1e-12
    return (hits + 1) / (n + 1)


def per_rec(eps, key, split):
    aucs = []
    for r in sorted({e["rid"] for e in eps}):
        es = [e for e in eps if e["rid"] == r and key in e]
        a = [e[key] for e in es if split(e) is True]
        b = [e[key] for e in es if split(e) is False]
        if len(a) >= 2 and len(b) >= 2:
            aucs.append(auc(a, b))
    if not aucs:
        return None
    aucs = np.array(aucs)
    p = sign_p(aucs - 0.5) if aucs.size >= 5 else None
    return {"n": int(aucs.size), "median": float(np.median(aucs)), "iqr": [float(np.percentile(aucs, 25)), float(np.percentile(aucs, 75))],
            "frac_gt": float((aucs > 0.5).mean()), "p": p}


def main() -> int:
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = GYM_ROOT / "results" / f"{ts}_stability"
    out_dir.mkdir(parents=True, exist_ok=True)
    board, md = {}, ["# band-stability round\n\nPer-recording AUC, cond 1 > cond 0; p = sign test of per-rec AUC vs 0.5; group p = permutation. Gated (app-matching).\n"]
    for name, p in CORPORA.items():
        if not p.exists():
            continue
        c = load_corpus(p)
        eps = epochs(c)
        groups = sorted({str(e["group"]) for e in eps})
        res = {"epochs": len(eps), "groups": groups, "mw": {}, "drowsy": {}, "group": {}}
        md.append(f"\n## {name} ({len(eps)} probe epochs, groups {groups})\n\n| metric | MW > on-task: median [IQR] (n, p) | drowsy > alert | {groups[-1]} vs {groups[0]} (rec medians, AUC, p) |\n|---|---|---|---|\n")
        for m in ("sd", "masd", "mean"):
            for f in FEATS:
                k = f"{m}:{f}"
                if not any(k in e for e in eps):
                    continue
                r1 = per_rec(eps, k, lambda e: e["y"] == 1)
                r2 = per_rec(eps, k, lambda e: None if not np.isfinite(e["drowsy"]) else bool(e["drowsy"] >= 1))
                med = {}
                for e in eps:
                    if k in e:
                        med.setdefault(e["rid"], (e["group"], []))[1].append(e[k])
                ga = [np.median(v) for g, v in med.values() if g == groups[-1]]
                gb = [np.median(v) for g, v in med.values() if g == groups[0]]
                gr = {"auc": auc(ga, gb), "p": perm_p(ga, gb) if ga and gb else None, "n": [len(ga), len(gb)]}
                res["mw"][k], res["drowsy"][k], res["group"][k] = r1, r2, gr
                fmt = lambda r: "—" if r is None else f"{r['median']:.2f} [{r['iqr'][0]:.2f}–{r['iqr'][1]:.2f}] (n={r['n']}, p={r['p']:.3g})" if r["p"] is not None else f"{r['median']:.2f} (n={r['n']})"
                gs = "—" if gr["auc"] is None else f"{gr['auc']:.2f} (n={gr['n'][0]}/{gr['n'][1]}, p={gr['p']:.3g})"
                md.append(f"| {k} | {fmt(r1)} | {fmt(r2)} | {gs} |\n")
        board[name] = res
    (out_dir / "stability.json").write_text(json.dumps(board, indent=1))
    (out_dir / "stability_tables.md").write_text("".join(md))
    print(out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
