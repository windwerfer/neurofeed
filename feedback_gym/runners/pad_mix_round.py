#!/usr/bin/env python3
"""Pad-mixing round: which Muse pad combinations keep delta / theta sleep features
from firing on eye and muscle artifacts? (FAIR_BANDMATH.md, "Pad mixing")

Needs corpora built with ``neurofeed-gym-corpora`` ``--pad-mix`` (per-channel
band powers + bipolar / EOG-regressed / slow-eye-movement columns, see that
repo's ``builders/pad_mix.py``). Gym-only; nothing here ships in the app.

This tests ARTIFACT ROBUSTNESS and signal retention on awake Muse data
(Lee 2026 Muse 2, UNIVERSE Muse S). It does NOT test sleep-onset sensitivity:
there is no labeled Muse sleep / drowsiness data, and Sleep-EDF has the wrong
montage for pad mixing (Fpz-Cz / Pz-Oz only).

Variants (pooling over per-pad band powers, the app's aggregation: absolute
delta / theta = pooled absolute power; relative bands = pooled per-pad
relative bands, then ratios):

  af        AF7/AF8 mean                     (today's app band math, no gating)
  af_gate   AF7/AF8, pads with app quality >= 80 (what the app does live)
  tp        TP9/TP10 mean
  all4      4-pad mean
  split     delta/theta from TP9/TP10, alpha/beta from all 4 pads
  med4      4-pad median
  w4_var    4 pads weighted by 1 / variance (latest 1 s, high-passed)
  w4_hf     4 pads weighted by 1 / gamma (30-50 Hz) power (EMG proxy)
  w4_q      4 pads weighted by the app pad-quality score (Muse HSI stand-in)
  gate4     4-pad mean over pads with app quality >= 80
  bip       bipolar AF7 - AF8
  tpbip     bipolar TP9 - TP10 (cancels the Fpz reference; added after the
            first run showed blinks reach TP9/TP10 through the reference)
  car_tp    TP9/TP10 re-referenced to the 4-pad common average
  tphp      TP9/TP10 after the 0.5 Hz causal high-pass (control for eog*)
  eogcal    TP9/TP10 with AF7/AF8 regressed out, LS fit once on the cal block
  eogrun    TP9/TP10 with AF7/AF8 regressed out, causal running LS (trailing 30 s)

Features per variant: absolute delta, absolute theta, relative theta, TAR
(theta/alpha), (theta+alpha)/beta. All have sleep direction UP (warn when the
value rises above the p90 of the recording's own baseline).

Eye-movement features (no pooling): sem_2s / sem_8s (bipolar AF7 - AF8 low-
frequency power), veog_2s / veog_8s (vertical (AF7+AF8)/2, comparator).

Metrics (fair-round rules: per-recording baselines, cal rows never scored,
directional per-recording AUC, median over recordings):

  artifact AUC per Lee task (EB blink, BT jaw clench, MVO head turns eyes
      open, MVC head turns eyes closed): task rows vs the same recording's
      clean rest; LOWER = more robust (a sleep feature should not rise).
      EB is confounded (rests eyes closed, task eyes open), so blinks are
      also scored EO-matched: EB task rows vs the same subject's MVO
      eyes-open rest, threshold from the MVO baseline
  coverage: share of clean rows where the variant is defined (quality-gated
      variants skip windows with no usable pad; a skipped window never warns)
  false warnings: p90 guard warn rate on artifact rows vs clean rows
  EO/EC: per-subject AUC (eyes closed higher), direction reported
  stability: Spearman rho over recordings of median(pre-rest) vs
      median(post-rest) on clean rows (test-retest; a flat / noisy variant
      scores low), plus within-recording robust CV
  UNIVERSE: p90 warn rate on relax / low-load rows (awake false alarms)

Usage::

    cd feedback_gym && python3 runners/pad_mix_round.py [--out-dir DIR]
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

import numpy as np

GYM_ROOT = Path(__file__).resolve().parent.parent
if str(GYM_ROOT) not in sys.path:
    sys.path.insert(0, str(GYM_ROOT))

from runners.helpers import build_cal_plan, load_corpus, roc_auc_up, threshold_at_percentile  # noqa: E402

CH = ("af7", "af8", "tp9", "tp10")
BANDS = ("delta", "theta", "alpha", "beta", "gamma")
FIXED_P = 90
MIN_CLASS_ROWS = 10
Q_USABLE = 80.0  # features.rs SIGNAL_GOOD_THRESHOLD
LEE_TASKS = {"EB": "blink", "BT": "jaw", "MVO": "head turn EO", "MVC": "head turn EC"}
FEATURES = ("delta", "theta", "rel_theta", "tar", "tab")
FEATURE_LABEL = {
    "delta": "abs delta",
    "theta": "abs theta",
    "rel_theta": "rel theta",
    "tar": "TAR",
    "tab": "(θ+α)/β",
}
# (column or derived id, label, sleep direction: +1 warn when it rises, -1 when it falls)
EYE_FEATURES: tuple[tuple[str, str, int], ...] = (
    ("sem_2s", "SEM power 0.5–2 Hz, 2 s (AF7−AF8)", +1),
    ("sem_8s", "SEM power 0.25–1 Hz, 8 s (AF7−AF8)", +1),
    ("sem_fast_8s", "fast eye-movement power 1–5 Hz, 8 s (AF7−AF8), falls", -1),
    ("sem_ratio_8s", "slowness ratio sem_8s / sem_fast_8s", +1),
    ("veog_2s", "vertical (AF7+AF8)/2 0.5–2 Hz, 2 s (blink comparator)", +1),
    ("veog_8s", "vertical 0.25–1 Hz, 8 s (blink comparator)", +1),
)


def eye_series(corpus: dict[str, Any], key: str) -> np.ndarray | None:
    if key == "sem_ratio_8s":
        if "sem_8s" not in corpus or "sem_fast_8s" not in corpus:
            return None
        a, b = (np.asarray(corpus[k], dtype=float) for k in ("sem_8s", "sem_fast_8s"))
        with np.errstate(divide="ignore", invalid="ignore"):
            return np.where(b > 0, a / b, np.nan)
    return np.asarray(corpus[key], dtype=float) if key in corpus else None


@dataclass(frozen=True)
class Variant:
    key: str
    label: str
    live: str  # live-cost note for the app (256 Hz, 4 ch)


VARIANTS: tuple[Variant, ...] = (
    Variant("af", "AF7/AF8 mean (app today, ungated)", "yes: current"),
    Variant("af_gate", "AF7/AF8, quality-gated (app live)", "yes: current"),
    Variant("tp", "TP9/TP10 mean", "yes: free (per-pad FFTs exist)"),
    Variant("all4", "4-pad mean", "yes: free"),
    Variant("split", "δ/θ from TP, α/β from 4 pads", "yes: free"),
    Variant("med4", "4-pad median", "yes: free"),
    Variant("w4_var", "4-pad, 1/variance weights", "yes: free (std ring exists)"),
    Variant("w4_hf", "4-pad, 1/gamma-power weights", "yes: free"),
    Variant("w4_q", "4-pad, app-quality weights", "yes: free"),
    Variant("gate4", "4-pad, quality-gated mean", "yes: free"),
    Variant("bip", "bipolar AF7−AF8", "yes: +1 FFT/s"),
    Variant("tpbip", "bipolar TP9−TP10", "yes: +1 FFT/s"),
    Variant("car_tp", "TP, common-average reference", "yes: 2 FFT/s"),
    Variant("tphp", "TP + 0.5 Hz HP (control)", "yes: app already high-passes"),
    Variant("eogcal", "TP − EOG regression (cal-fit)", "yes: 2×2 LS once, 4 MAC/sample"),
    Variant("eogrun", "TP − EOG regression (running 30 s)", "yes: running sums + 2×2 solve/s"),
)
VARIANT_BY_KEY = {v.key: v for v in VARIANTS}


def has_pad_mix(corpus: dict[str, Any]) -> bool:
    return all(f"ch_{c}_delta" in corpus for c in CH)


# --- pooling ---------------------------------------------------------------------


def _bands(corpus: dict[str, Any], prefix: str) -> np.ndarray:
    """(N, 5) absolute bands for one signal column prefix (e.g. ``ch_af7`` / ``bip``)."""
    return np.stack([np.asarray(corpus[f"{prefix}_{b}"], dtype=float) for b in BANDS], axis=-1)


def _rel(b: np.ndarray) -> np.ndarray:
    tot = b.sum(axis=-1, keepdims=True)
    with np.errstate(divide="ignore", invalid="ignore"):
        return np.where(tot > 0, b / tot, np.nan)


def _pool(x: np.ndarray, how: str, w: np.ndarray | None = None) -> np.ndarray:
    """Pool ``(P, N, ...)`` over pads. ``w`` ``(P, N)``: weights (NaN / 0 = pad unusable)."""
    if how == "mean":
        return np.nanmean(x, axis=0)
    if how == "median":
        return np.nanmedian(x, axis=0)
    if how == "weighted":
        assert w is not None
        w = np.where(np.isfinite(w) & (w > 0), w, 0.0)
        ww = w.reshape(w.shape + (1,) * (x.ndim - 2))
        num = (np.nan_to_num(x) * ww).sum(axis=0)
        den = ww.sum(axis=0)
        with np.errstate(divide="ignore", invalid="ignore"):
            return np.where(den > 0, num / den, np.nan)
    raise ValueError(how)


def _features_from(abs_pool: np.ndarray, rel_slow: np.ndarray, rel_fast: np.ndarray | None = None) -> dict[str, np.ndarray]:
    """abs delta / theta from ``abs_pool``; theta share from ``rel_slow``; alpha / beta share from ``rel_fast``."""
    rf = rel_slow if rel_fast is None else rel_fast
    th, al, be = rel_slow[:, 1], rf[:, 2], rf[:, 3]
    with np.errstate(divide="ignore", invalid="ignore"):
        return {
            "delta": abs_pool[:, 0],
            "theta": abs_pool[:, 1],
            "rel_theta": th,
            "tar": np.where(al > 0, th / al, np.nan),
            "tab": np.where(be > 0, (th + al) / be, np.nan),
        }


def variant_features(corpus: dict[str, Any], key: str) -> dict[str, np.ndarray]:
    """Feature arrays (N,) for one variant."""
    pads = {c: _bands(corpus, f"ch_{c}") for c in CH}
    q = {c: np.asarray(corpus[f"ch_{c}_q"], dtype=float) for c in CH}

    def pooled(names: tuple[str, ...], how: str = "mean", w: np.ndarray | None = None):
        P = np.stack([pads[c] for c in names])
        return _pool(P, how, w), _pool(_rel(P), how, w)

    four = CH
    if key == "af":
        a, r = pooled(("af7", "af8"))
        return _features_from(a, r)
    if key == "af_gate":
        w = np.stack([(q[c] >= Q_USABLE).astype(float) for c in ("af7", "af8")])
        a, r = pooled(("af7", "af8"), "weighted", w)
        return _features_from(a, r)
    if key == "tp":
        a, r = pooled(("tp9", "tp10"))
        return _features_from(a, r)
    if key == "all4":
        a, r = pooled(four)
        return _features_from(a, r)
    if key == "med4":
        a, r = pooled(four, "median")
        return _features_from(a, r)
    if key == "split":
        a_tp, r_tp = pooled(("tp9", "tp10"))
        _, r4 = pooled(four)
        return _features_from(a_tp, r_tp, r4)
    if key in ("w4_var", "w4_hf", "w4_q", "gate4"):
        if key == "w4_var":
            w = np.stack([1.0 / np.maximum(np.asarray(corpus[f"ch_{c}_std"], dtype=float) ** 2, 1e-6) for c in four])
        elif key == "w4_hf":
            w = np.stack([1.0 / np.maximum(pads[c][:, 4], 1e-9) for c in four])
        elif key == "w4_q":
            w = np.stack([q[c] for c in four])
        else:
            w = np.stack([(q[c] >= Q_USABLE).astype(float) for c in four])
        a, r = pooled(four, "weighted", w)
        return _features_from(a, r)
    if key == "bip":
        b = _bands(corpus, "bip")
        return _features_from(b, _rel(b))
    if key == "tpbip":
        b = _bands(corpus, "tpbip")
        return _features_from(b, _rel(b))
    if key in ("tphp", "eogcal", "eogrun", "car"):
        P = np.stack([_bands(corpus, f"{key}_{t}") for t in ("tp9", "tp10")])
        return _features_from(np.nanmean(P, axis=0), np.nanmean(_rel(P), axis=0))
    if key == "car_tp":
        return variant_features(corpus, "car")
    raise KeyError(key)


# --- metrics ---------------------------------------------------------------------


def _task_of(rid: str) -> str:
    return rid.rsplit("/", 1)[-1]


def per_recording(series: np.ndarray, corpus: dict[str, Any], p: int = FIXED_P) -> list[dict[str, Any]]:
    """Per recording: directional AUC (label 1 higher) + p-th-percentile guard warn rates."""
    plan = build_cal_plan(corpus)
    y_all = np.asarray(corpus["labels"]).astype(int)
    s = np.asarray(series, dtype=float)
    out = []
    for g in plan.groups:
        base = s[g.cal_idx]
        base = base[np.isfinite(base)]
        rows = plan.play_idx[g.play_pos]
        ss, yy = s[rows], y_all[rows]
        ok = np.isfinite(ss)
        if base.size < 5 or not ok.any():
            continue
        thr = threshold_at_percentile(base, p)
        warn = ok & (np.nan_to_num(ss, nan=-np.inf) > thr)  # an undefined (skipped) window never warns
        n1, n0 = int((yy[ok] == 1).sum()), int((yy[ok] == 0).sum())
        out.append({
            "rid": g.recording_id,
            "auc": roc_auc_up(ss[ok], yy[ok]) if n1 >= MIN_CLASS_ROWS and n0 >= MIN_CLASS_ROWS else None,
            "warn0": float(warn[yy == 0].mean()) if (yy == 0).any() else None,
            "warn1": float(warn[yy == 1].mean()) if (yy == 1).any() else None,
            "cover0": float(ok[yy == 0].mean()) if (yy == 0).any() else None,
        })
    return out


def blink_eo_matched(series: np.ndarray, corpus: dict[str, Any], p: int = FIXED_P) -> dict[str, Any]:
    """EB task (eyes open + cued blinks) vs the same subject's MVO eyes-open rest.

    The EB recording's own rests are eyes CLOSED, so its within-recording
    contrast mixes blinks with eye opening. Here both sides are eyes open;
    threshold = p-th percentile of the MVO baseline block.
    """
    s = np.asarray(series, dtype=float)
    rid = np.asarray(corpus["recording_id"]).astype(str)
    seg = np.asarray(corpus["segment"]).astype(str)
    plan = build_cal_plan(corpus)
    groups = {g.recording_id: g for g in plan.groups}
    aucs, w0, w1 = [], [], []
    for r, g in groups.items():
        if _task_of(r) != "MVO":
            continue
        eb = r[: -len("MVO")] + "EB"
        if eb not in groups:
            continue
        base = s[g.cal_idx]
        base = base[np.isfinite(base)]
        rest = plan.play_idx[g.play_pos]
        rest = rest[np.char.find(seg[rest], "_rest/") >= 0]
        task = np.where((rid == eb) & (np.char.find(seg, "/task/") >= 0))[0]
        if base.size < 5 or rest.size < MIN_CLASS_ROWS or task.size < MIN_CLASS_ROWS:
            continue
        thr = threshold_at_percentile(base, p)
        a, b = s[rest], s[task]
        w0.append(float((np.isfinite(a) & (np.nan_to_num(a, nan=-np.inf) > thr)).mean()))
        w1.append(float((np.isfinite(b) & (np.nan_to_num(b, nan=-np.inf) > thr)).mean()))
        a, b = a[np.isfinite(a)], b[np.isfinite(b)]
        if a.size >= MIN_CLASS_ROWS and b.size >= MIN_CLASS_ROWS:
            auc = roc_auc_up(np.concatenate([a, b]), np.r_[np.zeros(a.size, int), np.ones(b.size, int)])
            if auc is not None:
                aucs.append(auc)
    return {
        "auc_median": _med(aucs),
        "n": len(aucs),
        "above_half": int(sum(1 for x in aucs if x > 0.5)),
        "warn_clean": _mean(w0),
        "warn_artifact": _mean(w1),
    }


def _med(v: list[float | None]) -> float | None:
    v = [x for x in v if x is not None and np.isfinite(x)]
    return float(np.median(v)) if v else None


def _mean(v: list[float | None]) -> float | None:
    v = [x for x in v if x is not None and np.isfinite(x)]
    return float(np.mean(v)) if v else None


def artifact_metrics(series: np.ndarray, corpus: dict[str, Any]) -> dict[str, Any]:
    recs = per_recording(series, corpus)
    out: dict[str, Any] = {}
    for task, name in LEE_TASKS.items():
        rs = [r for r in recs if _task_of(r["rid"]) == task]
        aucs = [r["auc"] for r in rs if r["auc"] is not None]
        out[name] = {
            "auc_median": _med(aucs),
            "n": len(aucs),
            "above_half": int(sum(1 for a in aucs if a > 0.5)),
            "warn_clean": _mean([r["warn0"] for r in rs]),
            "warn_artifact": _mean([r["warn1"] for r in rs]),
            "coverage_clean": _mean([r["cover0"] for r in rs]),
        }
    out["blink EO-matched"] = blink_eo_matched(series, corpus)
    out["coverage_clean"] = _mean([r["cover0"] for r in recs])
    return out


def eo_ec_metrics(series: np.ndarray, corpus: dict[str, Any]) -> dict[str, Any]:
    recs = per_recording(series, corpus)
    aucs = [r["auc"] for r in recs if r["auc"] is not None]
    return {
        "auc_median": _med(aucs),
        "n": len(aucs),
        "above_half": int(sum(1 for a in aucs if a > 0.5)),
        "warn_eo": _mean([r["warn0"] for r in recs]),
        "warn_ec": _mean([r["warn1"] for r in recs]),
    }


def _spearman(a: np.ndarray, b: np.ndarray) -> float | None:
    ok = np.isfinite(a) & np.isfinite(b)
    if ok.sum() < 5:
        return None

    def rank(x: np.ndarray) -> np.ndarray:
        order = np.argsort(x, kind="mergesort")
        r = np.empty(x.size)
        r[order] = np.arange(x.size)
        # average ties
        _, inv, cnt = np.unique(x, return_inverse=True, return_counts=True)
        sums = np.bincount(inv, weights=r)
        return (sums / cnt)[inv]

    ra, rb = rank(a[ok]), rank(b[ok])
    if ra.std() == 0 or rb.std() == 0:
        return None
    return float(np.corrcoef(ra, rb)[0, 1])


def stability_metrics(series: np.ndarray, corpus: dict[str, Any]) -> dict[str, Any]:
    """Clean-rest test-retest on Lee artifacts: median(pre-rest) vs median(post-rest) per recording."""
    s = np.asarray(series, dtype=float)
    seg = np.asarray(corpus["segment"]).astype(str)
    rid = np.asarray(corpus["recording_id"]).astype(str)
    plan = build_cal_plan(corpus)
    play = np.zeros(s.size, dtype=bool)
    play[plan.play_idx] = True
    pre, post, cv = [], [], []
    for r in dict.fromkeys(rid):
        m = rid == r
        a = s[m & play & (np.char.find(seg, "/pre_rest/") >= 0)]
        b = s[m & (np.char.find(seg, "/post_rest/") >= 0)]
        a, b = a[np.isfinite(a)], b[np.isfinite(b)]
        if a.size < 5 or b.size < 5:
            continue
        pre.append(np.median(a))
        post.append(np.median(b))
        clean = np.concatenate([a, b])
        med = np.median(clean)
        if med != 0:  # |median|: falling features are scored negated
            cv.append(1.4826 * np.median(np.abs(clean - med)) / abs(med))
    return {
        "retest_rho": _spearman(np.asarray(pre), np.asarray(post)),
        "within_cv": _med(cv),
        "n": len(pre),
    }


def universe_metrics(series: np.ndarray, corpus: dict[str, Any]) -> dict[str, Any]:
    recs = per_recording(series, corpus)
    aucs = [r["auc"] for r in recs if r["auc"] is not None]
    return {
        "auc_median": _med(aucs),
        "warn_relax": _mean([r["warn0"] for r in recs]),
        "warn_stress": _mean([r["warn1"] for r in recs]),
        "n": len(recs),
    }


def score_series(series: np.ndarray, corpora: dict[str, dict[str, Any]]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    if "lee-artifacts" in corpora:
        out["artifacts"] = artifact_metrics(series["lee-artifacts"], corpora["lee-artifacts"])
        out["stability"] = stability_metrics(series["lee-artifacts"], corpora["lee-artifacts"])
    if "lee-eo-ec" in corpora:
        out["eo_ec"] = eo_ec_metrics(series["lee-eo-ec"], corpora["lee-eo-ec"])
    if "universe" in corpora:
        out["universe"] = universe_metrics(series["universe"], corpora["universe"])
    return out


# --- report ----------------------------------------------------------------------


def _f(x: Any, nd: int = 2) -> str:
    if x is None or (isinstance(x, float) and not np.isfinite(x)):
        return "—"
    return f"{x:.{nd}f}"


def _row(name: str, live: str, m: dict[str, Any]) -> str:
    art = m.get("artifacts", {})
    a = lambda k: art.get(k, {})  # noqa: E731
    eo = m.get("eo_ec", {})
    st = m.get("stability", {})
    un = m.get("universe", {})
    eo_dir = "—" if eo.get("auc_median") is None else ("EC↑" if eo["auc_median"] > 0.5 else "EC↓")
    return (
        f"| {name} | {_f(a('blink').get('auc_median'))} / {_f(a('blink EO-matched').get('auc_median'))} | "
        f"{_f(a('jaw').get('auc_median'))} | "
        f"{_f(a('head turn EO').get('auc_median'))} / {_f(a('head turn EC').get('auc_median'))} | "
        f"{_f(eo.get('auc_median'))} {eo_dir} | {_f(st.get('retest_rho'))} | {_f(art.get('coverage_clean'))} | {live} |"
    )


def _warn_row(name: str, m: dict[str, Any]) -> str:
    art = m.get("artifacts", {})
    cells = []
    for t in (*LEE_TASKS.values(), "blink EO-matched"):
        d = art.get(t, {})
        cells.append(f"{_f(d.get('warn_clean'))} → {_f(d.get('warn_artifact'))}")
    un = m.get("universe", {})
    st = m.get("stability", {})
    return (f"| {name} | " + " | ".join(cells)
            + f" | {_f(un.get('warn_relax'))} / {_f(un.get('warn_stress'))} | {_f(st.get('within_cv'))} |")


TABLE_HEAD = (
    "| variant · feature | blink AUC (EB rest / EO-matched) | jaw AUC | movement AUC (EO / EC) | EO/EC AUC | "
    "stability (retest ρ) | coverage | live-capable |\n"
    "|---|---:|---:|---:|---:|---:|---:|---|\n"
)
WARN_HEAD = (
    "| variant · feature | p90 warn clean → blink | clean → jaw | clean → head turn EO | clean → head turn EC | "
    "EO rest → blink (EO-matched) | UNIVERSE warn relax / stress | within-rec CV (clean) |\n|---|---|---|---|---|---|---|---:|\n"
)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ext = GYM_ROOT / "corpora" / "external"
    ap.add_argument("--lee-eo-ec", type=Path, default=ext / "lee2026_eo_ec.npz")
    ap.add_argument("--lee-artifacts", type=Path, default=ext / "lee2026_artifacts.npz")
    ap.add_argument("--universe", type=Path, default=ext / "universe_stress.npz")
    ap.add_argument("--out-dir", type=Path, default=None)
    args = ap.parse_args(argv)

    corpora: dict[str, dict[str, Any]] = {}
    skipped: dict[str, str] = {}
    for name, p in (("lee-artifacts", args.lee_artifacts), ("lee-eo-ec", args.lee_eo_ec), ("universe", args.universe)):
        if not p.exists():
            skipped[name] = "missing"
            continue
        c = load_corpus(p)
        if not has_pad_mix(c):
            skipped[name] = "no pad-mix columns (rebuild with --pad-mix)"
            continue
        corpora[name] = c
    if "lee-artifacts" not in corpora:
        print("lee-artifacts with pad-mix columns is required", file=sys.stderr)
        return 2

    board: dict[str, Any] = {
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "corpora": {k: int(len(v["labels"])) for k, v in corpora.items()},
        "skipped": skipped,
        "variants": {},
        "eye_features": {},
    }
    rows_main: dict[str, list[str]] = {f: [] for f in FEATURES}
    rows_warn: dict[str, list[str]] = {f: [] for f in FEATURES}
    for v in VARIANTS:
        feats = {name: variant_features(c, v.key) for name, c in corpora.items()}
        board["variants"][v.key] = {"label": v.label, "live": v.live, "features": {}}
        for f in FEATURES:
            m = score_series({name: feats[name][f] for name in corpora}, corpora)
            board["variants"][v.key]["features"][f] = m
            rows_main[f].append(_row(f"{v.key} · {FEATURE_LABEL[f]}", v.live, m))
            rows_warn[f].append(_warn_row(f"{v.key} · {FEATURE_LABEL[f]}", m))
    eye_rows, eye_warn = [], []
    for f, flabel, sdir in EYE_FEATURES:
        ser = {name: eye_series(c, f) for name, c in corpora.items()}
        if ser.get("lee-artifacts") is None:
            continue
        # scored in the sleep direction: a falling feature is negated (warn when it drops below p10)
        m = score_series({k: sdir * v for k, v in ser.items() if v is not None}, corpora)
        board["eye_features"][f] = {"label": flabel, "sleep_dir": sdir, **m}
        live = "yes: +1 FFT/s" if f.endswith("2s") else "yes: 8 s ring + 1 FFT/s"
        name = f"{f} ({'↑' if sdir > 0 else '↓'})"
        eye_rows.append(_row(name, live, m))
        eye_warn.append(_warn_row(name, m))

    md = [
        "_Lee 2026 Muse 2 (artifacts: 102 recordings, EB / BT / MVO / MVC; EO/EC: 25 subjects), per-recording "
        f"baselines, cal rows not scored, per-recording AUC with label 1 = artifact / eyes closed (higher = "
        f"feature rises), median over recordings. Guard = warn when the feature rises above p{FIXED_P} of the "
        "recording's own baseline. Corpora: " + ", ".join(f"{k} N={n}" for k, n in board["corpora"].items())
        + (f"; skipped: {skipped}" if skipped else "") + "_\n\n",
    ]
    for f in FEATURES:
        md.append(f"#### {FEATURE_LABEL[f]}\n\n" + TABLE_HEAD + "\n".join(rows_main[f]) + "\n\n")
    md.append("#### eye-movement features (↑ / ↓ = sleep direction; AUCs and warnings are in that direction)\n\n"
              + TABLE_HEAD + "\n".join(eye_rows) + "\n\n")
    md.append("#### false warnings (p90 guard) and within-recording spread\n\n")
    for f in FEATURES:
        md.append(f"{FEATURE_LABEL[f]}\n\n" + WARN_HEAD + "\n".join(rows_warn[f]) + "\n\n")
    md.append("eye-movement features\n\n" + WARN_HEAD + "\n".join(eye_warn) + "\n")

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = args.out_dir or (GYM_ROOT / "results" / f"{ts}_padmix")
    out_dir.mkdir(parents=True, exist_ok=True)

    def _clean(o: Any) -> Any:
        if isinstance(o, dict):
            return {str(k): _clean(v) for k, v in o.items()}
        if isinstance(o, (list, tuple)):
            return [_clean(v) for v in o]
        if isinstance(o, (np.floating, float)):
            return None if not np.isfinite(o) else round(float(o), 4)
        if isinstance(o, np.integer):
            return int(o)
        return o

    (out_dir / "padmix_board.json").write_text(json.dumps(_clean(board), indent=1), encoding="utf-8")
    (out_dir / "padmix_tables.md").write_text("".join(md), encoding="utf-8")
    print(out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
