#!/usr/bin/env python3
"""Fair band-math round: per-recording baselines, both directions, validity vs playability.

Answers (FAIR_BANDMATH.md):

1. Is each band feature a sleep / drowsiness GUARD when it is scored fairly?
   - every recording against its OWN calibration block (``cal_starts`` /
     ``cal_lens``; cal rows never scored),
   - BOTH directions (``up``: warn when the value rises above the p-th
     percentile of the baseline; ``down``: warn when it falls below the
     (100-p)-th), with the physiological sleep direction fixed up front,
   - per-recording AUC (direction kept, not folded to max(auc, 1-auc)),
     side by side with ``ai.a_vig`` / ``ai.wake_light`` on the same rows.
2. Which numbers are validity (AUC, balanced accuracy vs labels) and which are
   playability (reward hit rate + stability, the old ``reward`` score).
3. What the same features do on awake-only corpora (Lee EO/EC, Lee artifacts,
   UNIVERSE): how often a sleep guard would fire with no sleep present.

Gym-only derived features (computed here from the corpus relative bands, no
app change): ``gym.tab`` = (theta+alpha)/beta, ``gym.theta_rel``,
``gym.delta_rel``. ``band.delta`` stays absolute delta (uV^2).

Writes ``results/<ts>_fair/fair_board.json`` + ``fair_tables.md`` (aggregates
only). Usage::

    cd feedback_gym && python3 runners/fair_round.py \
        [--catalog ../assets/protocols.json] [--old-sleep-edf corpora/external/sleep_edf_test_global_old.npz]
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

from runners.helpers import (  # noqa: E402
    build_cal_plan,
    label_align,
    load_corpus,
    load_grids,
    roc_auc_up,
    threshold_at_percentile,
)

GUARD_PS = (50, 60, 70, 75, 80, 85, 90, 95)
FIXED_P = 90
MIN_CLASS_ROWS = 20  # per recording, for a per-recording AUC


# --- features ------------------------------------------------------------------


@dataclass(frozen=True)
class Feat:
    id: str
    label: str
    sleep_dir: int  # +1: rises toward sleep (warn when up); -1: falls toward sleep
    kind: str  # "ratio" | "relative" | "absolute" | "ai"
    getter: Callable[[dict[str, Any], str], np.ndarray | None]


def _col(name: str) -> Callable[[dict[str, Any], str], np.ndarray | None]:
    def get(c: dict[str, Any], prefix: str = "") -> np.ndarray | None:
        key = f"{prefix}{name}" if not name.startswith("ai_") else name
        v = c.get(key)
        return None if v is None else np.asarray(v, dtype=float)

    return get


def _tab(c: dict[str, Any], prefix: str = "") -> np.ndarray | None:
    t, a, b = (c.get(f"{prefix}{k}") for k in ("theta_rel", "alpha_rel", "beta_rel"))
    if t is None or a is None or b is None:
        return None
    t, a, b = (np.asarray(x, dtype=float) for x in (t, a, b))
    with np.errstate(divide="ignore", invalid="ignore"):
        return np.where(b > 0, (t + a) / b, np.nan)


# Sleep direction is the physiological prior, fixed before scoring:
# sleep onset (W -> N1) = alpha dropout, theta up, beta down, slow activity up.
FEATURES: tuple[Feat, ...] = (
    Feat("band.tar", "TAR theta/alpha", +1, "ratio", _col("band_tar")),
    Feat("gym.tab", "(theta+alpha)/beta", +1, "ratio", _tab),
    Feat("band.alpha", "alpha share", -1, "relative", _col("band_alpha")),
    Feat("band.atr", "ATR alpha/theta", -1, "ratio", _col("band_atr")),
    Feat("band.btr", "BTR beta/theta", -1, "ratio", _col("band_btr")),
    Feat("gym.theta_rel", "relative theta", +1, "relative", _col("theta_rel")),
    Feat("gym.delta_rel", "relative delta", +1, "relative", _col("delta_rel")),
    Feat("band.delta", "absolute delta (uV^2)", +1, "absolute", _col("band_delta")),
    Feat("ai.a_vig", "AI a_vig P(N1)", +1, "ai", _col("ai_a_vig")),
    Feat("ai.wake_light", "AI wake_light P(light)", +1, "ai", _col("ai_wake_light")),
)
FEATURE_BY_ID = {f.id: f for f in FEATURES}


# --- metrics -------------------------------------------------------------------


def auc_up(scores: np.ndarray, labels: np.ndarray) -> float | None:
    """Directional AUC (0.5 = chance, < 0.5 = moves the other way)."""
    return roc_auc_up(scores, labels)


def _q(v: list[float], q: float) -> float | None:
    return float(np.percentile(v, q)) if v else None


def score_direction(
    series: np.ndarray, corpus: dict[str, Any], sign: int, ps: tuple[int, ...] = GUARD_PS
) -> dict[str, Any]:
    """Guard metrics for ``sign * series`` (warn when it rises above the baseline)."""
    plan = build_cal_plan(corpus)
    labels = np.asarray(corpus["labels"]).astype(int)
    s = sign * np.asarray(series, dtype=float)
    rec = (
        np.asarray(corpus["recording_id"]).astype(str)
        if corpus.get("recording_id") is not None
        else np.full(s.size, "*")
    )
    play = plan.play_idx
    s_play, y_play = s[play], labels[play]
    fin = np.isfinite(s_play)

    per_rec: list[float] = []
    per_rec_ids: list[str] = []
    norm = np.full(s_play.size, np.nan)
    thr_by_p = {p: np.full(s_play.size, np.nan) for p in ps}
    for g in plan.groups:
        base = s[g.cal_idx]
        base = base[np.isfinite(base)]
        pos = g.play_pos
        if base.size == 0 or pos.size == 0:
            continue
        med = float(np.median(base))
        iqr = float(np.subtract(*np.percentile(base, [75, 25])))
        scale = iqr if iqr > 0 else (float(np.std(base)) or 1.0)
        norm[pos] = (s_play[pos] - med) / scale
        for p in ps:
            thr_by_p[p][pos] = threshold_at_percentile(base, p)
        yy, ss = y_play[pos], s_play[pos]
        ok = np.isfinite(ss)
        if (yy[ok] == 1).sum() >= MIN_CLASS_ROWS and (yy[ok] == 0).sum() >= MIN_CLASS_ROWS:
            a = auc_up(ss[ok], yy[ok])
            if a is not None:
                per_rec.append(a)
                per_rec_ids.append(g.recording_id)

    out: dict[str, Any] = {
        "pooled_auc_raw": auc_up(s_play, y_play),
        "pooled_auc_baseline_norm": auc_up(norm, y_play),
        "per_rec_auc": dict(zip(per_rec_ids, [round(x, 4) for x in per_rec])),
        "per_rec_auc_median": _q(per_rec, 50),
        "per_rec_auc_q25": _q(per_rec, 25),
        "per_rec_auc_q75": _q(per_rec, 75),
        "per_rec_n": len(per_rec),
        "per_rec_above_half": int(sum(1 for a in per_rec if a > 0.5)),
        "guard": {},
    }
    for p in ps:
        thr = thr_by_p[p]
        ok = fin & np.isfinite(thr)
        warn = s_play[ok] > thr[ok]
        yy = y_play[ok]
        out["guard"][p] = {
            "balanced_acc": label_align(warn, yy),
            "warn_rate_label0": float(warn[yy == 0].mean()) if (yy == 0).any() else None,
            "warn_rate_label1": float(warn[yy == 1].mean()) if (yy == 1).any() else None,
        }
    best = max(
        ((p, v["balanced_acc"]) for p, v in out["guard"].items() if v["balanced_acc"] is not None),
        key=lambda t: t[1],
        default=(None, None),
    )
    out["guard_best_p"], out["guard_best_ba"] = best
    return out


def score_feature_fair(feat: Feat, corpus: dict[str, Any], prefix: str = "") -> dict[str, Any] | None:
    series = feat.getter(corpus, prefix)
    if series is None or not np.isfinite(series).any():
        return None
    up = score_direction(series, corpus, +1)
    down = score_direction(series, corpus, -1)
    sleep = up if feat.sleep_dir > 0 else down
    data_dir = None
    if up["per_rec_auc_median"] is not None:
        data_dir = "up" if up["per_rec_auc_median"] > 0.5 else "down"
    return {
        "id": feat.id,
        "label": feat.label,
        "kind": feat.kind,
        "prior_sleep_dir": "up" if feat.sleep_dir > 0 else "down",
        "data_dir": data_dir,
        "up": up,
        "down": down,
        "sleep": sleep,
    }


def paired_vs(ref: dict[str, Any], other: dict[str, Any]) -> dict[str, Any] | None:
    """Per-recording AUC(other, its sleep dir) - AUC(ref, its sleep dir)."""
    a = ref["sleep"]["per_rec_auc"]
    b = other["sleep"]["per_rec_auc"]
    common = sorted(set(a) & set(b))
    if not common:
        return None
    d = [b[k] - a[k] for k in common]
    return {
        "n": len(common),
        "median_diff": float(np.median(d)),
        "other_ge_ref": int(sum(1 for x in d if x >= 0)),
    }


# --- protocols -----------------------------------------------------------------


def protocol_rows(
    catalog: dict[str, Any], corpora: dict[str, dict[str, Any]], grids: dict[str, Any]
) -> list[dict[str, Any]]:
    from runners.simulate_protocol import simulate_protocol

    rows = []
    for pid, proto in catalog.items():
        proto = dict(proto)
        proto.setdefault("id", pid)
        row: dict[str, Any] = {"id": pid, "corpora": {}}
        for name, corpus in corpora.items():
            if not (proto.get("reward") or proto.get("guard")):
                row["corpora"][name] = None
                continue
            res = simulate_protocol(proto, corpus, grids)
            parts = res["parts"]
            r = parts.get("reward") or {}
            g = parts.get("guard") or {}
            i = parts.get("inhibit") or {}
            row["corpora"][name] = {
                "final": res["final"],
                "reward_hit_rate": r.get("hit_rate"),
                "reward_score": r.get("score"),
                "inhibit_score": i.get("score") if isinstance(i, dict) else None,
                "inhibit_items": i.get("items") if isinstance(i, dict) else None,
                "guard_label_align": g.get("label_align"),
                "guard_status": g.get("status"),
            }
        rows.append(row)
    return rows


# --- report --------------------------------------------------------------------


def _f(x: Any, nd: int = 3) -> str:
    if x is None:
        return "—"
    if isinstance(x, float) and not np.isfinite(x):
        return "—"
    return f"{x:.{nd}f}"


def feature_table(results: list[dict[str, Any]], *, labels_note: str) -> str:
    head = (
        f"| feature | kind | sleep dir (prior / data) | per-rec AUC, sleep dir: median [IQR] | recs > 0.5 | "
        f"pooled AUC raw | pooled AUC baseline-norm | BA p{FIXED_P} up | BA p{FIXED_P} down | best BA (p) | "
        f"warn p{FIXED_P} on 0 / 1 |\n"
        "|---|---|---|---|---|---:|---:|---:|---:|---:|---|\n"
    )
    lines = []
    for r in results:
        s = r["sleep"]
        gp = s["guard"][FIXED_P]
        lines.append(
            f"| {r['label']} | {r['kind']} | {r['prior_sleep_dir']} / {r['data_dir'] or '—'} | "
            f"{_f(s['per_rec_auc_median'])} [{_f(s['per_rec_auc_q25'])}–{_f(s['per_rec_auc_q75'])}] | "
            f"{s['per_rec_above_half']}/{s['per_rec_n']} | {_f(s['pooled_auc_raw'])} | "
            f"{_f(s['pooled_auc_baseline_norm'])} | {_f(r['up']['guard'][FIXED_P]['balanced_acc'])} | "
            f"{_f(r['down']['guard'][FIXED_P]['balanced_acc'])} | {_f(s['guard_best_ba'])} (p{s['guard_best_p']}) | "
            f"{_f(gp['warn_rate_label0'], 2)} / {_f(gp['warn_rate_label1'], 2)} |"
        )
    return f"_{labels_note}_\n\n" + head + "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ext = GYM_ROOT / "corpora" / "external"
    ap.add_argument("--sleep-edf", type=Path, default=ext / "sleep_edf_test.npz")
    ap.add_argument("--old-sleep-edf", type=Path, default=ext / "sleep_edf_test_global_old.npz")
    ap.add_argument("--lee-eo-ec", type=Path, default=ext / "lee2026_eo_ec.npz")
    ap.add_argument("--lee-artifacts", type=Path, default=ext / "lee2026_artifacts.npz")
    ap.add_argument("--universe", type=Path, default=ext / "universe_stress.npz")
    ap.add_argument("--catalog", type=Path, default=GYM_ROOT.parent / "assets" / "protocols.json")
    ap.add_argument("--out-dir", type=Path, default=None)
    args = ap.parse_args(argv)

    corpora: dict[str, dict[str, Any]] = {}
    notes = {
        "sleep-edf": "label 0 = W, 1 = N1 (30 s scoring); per-recording wake baseline",
        "lee-eo-ec": "label 0 = eyes-open rest, 1 = eyes-closed rest (both awake); EO baseline",
        "lee-artifacts": "label 0 = clean rest, 1 = cued artifact task (both awake); clean-rest baseline",
        "universe": "label 0 = relax / low load, 1 = stress / high load (both awake); relax baseline",
    }
    paths = {
        "sleep-edf": args.sleep_edf,
        "lee-eo-ec": args.lee_eo_ec,
        "lee-artifacts": args.lee_artifacts,
        "universe": args.universe,
    }
    for k, p in paths.items():
        if p.exists():
            corpora[k] = load_corpus(p)
    board: dict[str, Any] = {"generated_utc": datetime.now(timezone.utc).isoformat(), "corpora": {}}
    md: list[str] = []

    for name, corpus in corpora.items():
        plan = build_cal_plan(corpus)
        feats = [r for f in FEATURES if (r := score_feature_fair(f, corpus)) is not None]
        entry: dict[str, Any] = {
            "calibration": plan.describe(),
            "n_play": int(plan.play_idx.size),
            "label_counts_play": np.bincount(np.asarray(corpus["labels"])[plan.play_idx]).tolist(),
            "features": feats,
        }
        md.append(f"### {name}\n")
        md.append(feature_table(feats, labels_note=notes[name] + f"; calibration {plan.describe()}"))
        ai = next((r for r in feats if r["id"] == "ai.a_vig"), None)
        if ai is not None:
            pv = {r["id"]: paired_vs(ai, r) for r in feats if r["id"] != "ai.a_vig"}
            entry["paired_vs_ai_a_vig"] = pv
            md.append("\nPer-recording AUC (sleep dir) minus ai.a_vig, same recordings:\n\n")
            md.append("| feature | n | median diff | recs where feature >= AI |\n|---|---:|---:|---:|\n")
            for r in feats:
                if r["id"] == "ai.a_vig" or pv.get(r["id"]) is None:
                    continue
                d = pv[r["id"]]
                md.append(f"| {r['label']} | {d['n']} | {_f(d['median_diff'])} | {d['other_ge_ref']}/{d['n']} |\n")
        # variants (Sleep-EDF only): app band math, posterior proxy
        variants = {}
        for prefix, vname in (("app_", "app band math (Hamming, [lo,hi), gamma 30-45)"),
                              ("post_", "posterior proxy Pz-Oz (flutter_bands math)")):
            if f"{prefix}band_tar" not in corpus:
                continue
            vr = []
            for f in FEATURES:
                if f.kind == "ai":
                    continue
                r = score_feature_fair(f, corpus, prefix=prefix)
                if r is not None:
                    vr.append(r)
            variants[prefix] = vr
            md.append(f"\nVariant: {vname}\n\n")
            md.append(feature_table(vr, labels_note=f"{vname}; same rows / baselines"))
            if ai is not None:
                md.append("\n| feature (variant) | median diff vs ai.a_vig | recs >= AI |\n|---|---:|---:|\n")
                for r in vr:
                    d = paired_vs(ai, r)
                    if d is not None:
                        md.append(f"| {r['label']} | {_f(d['median_diff'])} | {d['other_ge_ref']}/{d['n']} |\n")
        if variants:
            entry["variants"] = variants
        board["corpora"][name] = entry
        md.append("\n")

    # old (global baseline) vs fair on Sleep-EDF: guard BA at p90, both directions
    if args.old_sleep_edf.exists() and "sleep-edf" in corpora:
        old = load_corpus(args.old_sleep_edf)
        md.append("### sleep-edf: old global baseline vs per-recording baseline\n\n")
        md.append(
            "| feature | old sep (direction-free, pooled) | old BA p90 sleep dir | fair BA p90 sleep dir | "
            "fair per-rec AUC sleep dir |\n|---|---:|---:|---:|---:|\n"
        )
        rows = []
        for f in FEATURES:
            ro = score_feature_fair(f, old)
            rn = next((r for r in board["corpora"]["sleep-edf"]["features"] if r["id"] == f.id), None)
            if ro is None or rn is None:
                continue
            a = ro["up"]["pooled_auc_raw"]
            sep_old = None if a is None else max(a, 1 - a)
            rows.append({"id": f.id, "old_sep": sep_old,
                         "old_ba": ro["sleep"]["guard"][FIXED_P]["balanced_acc"],
                         "fair_ba": rn["sleep"]["guard"][FIXED_P]["balanced_acc"]})
            md.append(
                f"| {f.label} | {_f(sep_old)} | {_f(ro['sleep']['guard'][FIXED_P]['balanced_acc'])} | "
                f"{_f(rn['sleep']['guard'][FIXED_P]['balanced_acc'])} | {_f(rn['sleep']['per_rec_auc_median'])} |\n"
            )
        board["old_vs_fair_sleep_edf"] = rows
        corpora_for_protocols = {"sleep-edf (old global)": old, **corpora}
    else:
        corpora_for_protocols = dict(corpora)

    if args.catalog.exists():
        catalog = json.loads(args.catalog.read_text(encoding="utf-8"))["protocols"]
        prow = protocol_rows(catalog, corpora_for_protocols, load_grids())
        board["protocols"] = prow
        names = list(corpora_for_protocols)
        md.append("\n### protocols (gym simulate_protocol; playability parts, not validity)\n\n")
        md.append("| id | " + " | ".join(names) + " |\n|---|" + "---|" * len(names) + "\n")
        for row in prow:
            cells = []
            for n in names:
                c = row["corpora"][n]
                if c is None:
                    cells.append("N/A")
                    continue
                cells.append(
                    f"final {_f(c['final'])} · hit {_f(c['reward_hit_rate'])} · rew {_f(c['reward_score'])} · "
                    f"inh {_f(c['inhibit_score'])} · guard LA {_f(c['guard_label_align'])}"
                )
            md.append(f"| {row['id']} | " + " | ".join(cells) + " |\n")

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = args.out_dir or (GYM_ROOT / "results" / f"{ts}_fair")
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

    (out_dir / "fair_board.json").write_text(json.dumps(_clean(board), indent=1), encoding="utf-8")
    (out_dir / "fair_tables.md").write_text("".join(md), encoding="utf-8")
    print(out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
