#!/usr/bin/env python3
"""Fixed-probability threshold sweep for the AI sleep guard (ai.a_vig /
ai.wake_light) vs the percentile-of-baseline rule.

Inputs (gitignored external NPZs, see corpora/external/.gitignore):
  sleep_edf_test.npz        per-recording cal (cal_starts / cal_lens), W vs N1,
                            0.5 s hop; recordings with cal_len 0 are not scored
  lee2026_eo_ec_ai.npz      + lee2026_eo_ec.npz      (awake EO / EC rest, 1 s hop)
  lee2026_artifacts_ai.npz  + lee2026_artifacts.npz  (awake clean rest / cued
                            artifact task, 1 s hop); AI sidecars come from
                            runners/lee_ai_columns.py
Cal rows are never scored (the app does not warn while calibrating).

Warn rule (app GuardLane, deltaRail off as in the catalog): warn while
P(class 1) > threshold. P(class 1) is P(hypnagogic) for a_vig and P(light)
for wake_light, so high = drowsy and the inequality is ">".

Per threshold:
  BA        balanced accuracy W vs N1, per recording, median [IQR] over
            recordings (+ pooled)
  warn W    warn rate on Sleep-EDF wake play rows (pooled)
  warn N1   warn rate on Sleep-EDF N1 rows (pooled)
  Lee EO / EC / art / clean   warn rate on Lee awake rows: eyes-open rest,
            eyes-closed rest, cued artifact task, clean rest of the artifact
            recordings (pooled)
  latency   per recording: seconds from the first N1 row to the first warn
            at or after it (window start times from the muse-eeg-heads
            windows when available); median over recordings that warned;
            "missed" = recordings with no warn in N1 or later rows

Run: python feedback_gym/runners/ai_threshold_sweep.py [--md out.md]
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

GYM = Path(__file__).resolve().parents[1]
EXTERNAL = GYM / "corpora" / "external"
SLEEP_EDF_WINDOWS = Path("/workspace/muse-eeg-heads/kaggle_datasets/muse-eeg-heads-windows/vigilance_sleep_edf/windows")
SLEEP_EDF_EMB = Path("/workspace/muse-eeg-heads/exports/head_c_full_corpus/emb_cache")
FIXED = [round(0.30 + 0.05 * i, 2) for i in range(11)]
PERCENTILES = [75, 90]
HOP_S = 0.5


def app_percentile(base: np.ndarray, p: float) -> float:
    arr = np.sort(base[np.isfinite(base)])
    idx = int(np.floor((p / 100.0) * (arr.size - 1) + 0.5))
    return float(arr[min(max(idx, 0), arr.size - 1)])


def unique_in_order(a: np.ndarray) -> list[str]:
    _, first = np.unique(a, return_index=True)
    return [a[i] for i in sorted(first)]


def cal_mask(rid: np.ndarray, starts: np.ndarray, lens: np.ndarray) -> tuple[np.ndarray, dict[str, np.ndarray]]:
    """Boolean cal-row mask and per-recording cal row indices."""
    cal = np.zeros(rid.size, dtype=bool)
    per: dict[str, np.ndarray] = {}
    for r, s, n in zip(unique_in_order(rid), starts, lens):
        idx = np.arange(int(s), int(s) + int(n))
        cal[idx] = True
        per[r] = idx
    return cal, per


def ba(warn: np.ndarray, y: np.ndarray) -> float | None:
    if not (y == 0).any() or not (y == 1).any():
        return None
    return 0.5 * (float(warn[y == 1].mean()) + float(1.0 - warn[y == 0].mean()))


def sleep_edf_row_starts(rid: np.ndarray) -> dict[str, np.ndarray] | None:
    """Window start (s) per corpus row, replaying the emb_cache keep mask."""
    try:
        import sys

        sys.path.insert(0, str(GYM))
        from runners.build_corpus_sleep_edf import emb_keep_indices  # noqa: PLC0415
    except Exception:  # noqa: BLE001
        return None
    out: dict[str, np.ndarray] = {}
    for r in unique_in_order(rid):
        n = int((rid == r).sum())
        wp = SLEEP_EDF_WINDOWS / f"{r}_windows.npz"
        if not wp.exists():
            return None
        w = np.load(wp, allow_pickle=True)
        starts = np.asarray(w["starts"], dtype=np.float64) / 256.0
        if len(starts) != n:
            keep = emb_keep_indices(w)
            if len(keep) != n:
                return None
            starts = starts[keep]
        out[r] = starts
    return out


def load_sleep_edf(feature: str) -> dict:
    d = np.load(EXTERNAL / "sleep_edf_test.npz", allow_pickle=True)
    rid = d["recording_id"].astype(str)
    cal, per_cal = cal_mask(rid, d["cal_starts"], d["cal_lens"])
    return {
        "x": np.asarray(d[feature], dtype=float),
        "y": np.asarray(d["labels"]),
        "rid": rid,
        "cal": cal,
        "per_cal": per_cal,
        "times": sleep_edf_row_starts(rid),
    }


def load_lee(base: str, feature: str) -> dict:
    d = np.load(EXTERNAL / f"{base}.npz", allow_pickle=True)
    a = np.load(EXTERNAL / f"{base}_ai.npz", allow_pickle=True)
    rid = d["recording_id"].astype(str)
    if not np.array_equal(rid, a["recording_id"].astype(str)) or not np.array_equal(d["labels"], a["labels"]):
        raise SystemExit(f"{base}_ai.npz is not row-aligned with {base}.npz; rerun lee_ai_columns.py")
    cal, per_cal = cal_mask(rid, d["cal_starts"], d["cal_lens"])
    return {"x": np.asarray(a[feature], dtype=float), "y": np.asarray(d["labels"]), "rid": rid, "cal": cal, "per_cal": per_cal}


def thresholds_per_row(c: dict, rule: tuple[str, float]) -> np.ndarray:
    kind, v = rule
    if kind == "fixed":
        return np.full(c["x"].size, v)
    thr = np.full(c["x"].size, np.nan)
    for r, idx in c["per_cal"].items():
        if idx.size:
            thr[c["rid"] == r] = app_percentile(c["x"][idx], v)
    return thr


def sleep_edf_metrics(c: dict, rule: tuple[str, float]) -> dict:
    thr = thresholds_per_row(c, rule)
    scored = ~c["cal"] & np.isfinite(thr) & np.isfinite(c["x"])
    warn = c["x"] > thr
    bas, lats, missed, n_rec = [], [], 0, 0
    for r, idx in c["per_cal"].items():
        if idx.size == 0:
            continue
        n_rec += 1
        m = (c["rid"] == r) & scored
        b = ba(warn[m], c["y"][m])
        if b is not None:
            bas.append(b)
        rows = np.where(c["rid"] == r)[0]
        y_r, w_r, s_r = c["y"][rows], warn[rows] & scored[rows], scored[rows]
        n1 = np.where((y_r == 1) & s_r)[0]
        if n1.size == 0:
            continue
        onset = n1[0]
        after = np.where(w_r[onset:])[0]
        if after.size == 0:
            missed += 1
            continue
        hit = onset + after[0]
        if c["times"] is not None:
            t = c["times"][r]
            lats.append(float(t[hit] - t[onset]))
        else:
            lats.append(float((hit - onset) * HOP_S))
    y, w = c["y"][scored], warn[scored]
    return {
        "ba_med": float(np.median(bas)),
        "ba_q1": float(np.percentile(bas, 25)),
        "ba_q3": float(np.percentile(bas, 75)),
        "ba_pooled": ba(w, y),
        "warn_w": float(w[y == 0].mean()),
        "warn_n1": float(w[y == 1].mean()),
        "lat_med": float(np.median(lats)) if lats else None,
        "lat_q3": float(np.percentile(lats, 75)) if lats else None,
        "missed": missed,
        "n_rec": n_rec,
    }


def lee_rates(c: dict, rule: tuple[str, float]) -> tuple[float, float]:
    thr = thresholds_per_row(c, rule)
    scored = ~c["cal"] & np.isfinite(thr)
    warn = (c["x"] > thr) & scored
    y = c["y"]
    return float(warn[scored & (y == 0)].mean()), float(warn[scored & (y == 1)].mean())


def sweep(feature: str) -> list[dict]:
    se = load_sleep_edf(feature)
    eo = load_lee("lee2026_eo_ec", feature)
    art = load_lee("lee2026_artifacts", feature)
    rows = []
    for rule in [("percentile", p) for p in PERCENTILES] + [("fixed", t) for t in FIXED]:
        m = sleep_edf_metrics(se, rule)
        m["lee_eo"], m["lee_ec"] = lee_rates(eo, rule)
        m["lee_clean"], m["lee_art"] = lee_rates(art, rule)
        m["rule"] = f"p{int(rule[1])} of cal" if rule[0] == "percentile" else f"P > {rule[1]:.2f}"
        m["kind"], m["value"] = rule
        rows.append(m)
    return rows


def fmt(v, nd=3):
    return "—" if v is None else f"{v:.{nd}f}"


def table(feature: str, rows: list[dict]) -> str:
    out = [
        f"#### `{feature.replace('ai_', 'ai.')}`",
        "",
        "| rule | BA W/N1 per-rec median [IQR] | BA pooled | warn W | warn N1 | Lee EO rest | Lee EC rest | Lee artifact task | Lee clean rest | latency into N1, median (p75) | missed recs |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---|---:|",
    ]
    for m in rows:
        lat = "—" if m["lat_med"] is None else f"{m['lat_med']:.0f} s ({m['lat_q3']:.0f} s)"
        out.append(
            f"| {m['rule']} | {fmt(m['ba_med'])} [{fmt(m['ba_q1'])}–{fmt(m['ba_q3'])}] | {fmt(m['ba_pooled'])} | "
            f"{fmt(m['warn_w'], 2)} | {fmt(m['warn_n1'], 2)} | {fmt(m['lee_eo'], 2)} | {fmt(m['lee_ec'], 2)} | "
            f"{fmt(m['lee_art'], 2)} | {fmt(m['lee_clean'], 2)} | {lat} | {m['missed']}/{m['n_rec']} |"
        )
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--md", type=Path)
    p.add_argument("--json", type=Path)
    a = p.parse_args(argv)
    res = {f: sweep(f) for f in ("ai_a_vig", "ai_wake_light")}
    md = "\n\n".join(table(f, r) for f, r in res.items())
    print(md)
    if a.md:
        a.md.write_text(md + "\n")
    if a.json:
        a.json.write_text(json.dumps(res, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
