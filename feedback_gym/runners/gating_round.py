#!/usr/bin/env python3
"""App-matching gating round (FAIR_BANDMATH.md "Gating").

For every built corpus: how much the app's live gates would remove, what they
catch on cued artifacts (Lee head turns / blinks / jaw), and how the sleep
guards' warning rates change when the gym scores only the rows the app would
score (gated) vs every row (ungated, ``--no-gate`` behaviour).

Gates (runners/helpers.py ``gating_masks``):
- pad quality: the app's per-pad score (features.rs formula, recomputed offline
  by the builders' ``--pad-mix`` as ``ch_<pad>_q``) >= 80 on at least one feature
  pad (AF7/AF8); bands re-aggregated over usable pads only.
- movement: ``imu_movement`` (Rust compute_movement: SD of |accel| over 2 s at
  52 Hz) > 0.05 g marks this tick and the next dirty. No corpus built so far
  carries IMU, so this gate reports "n/a" (coverage table).

Writes ``results/<ts>_gating/gating_board.json`` + ``gating_tables.md``.
Lab-only corpora are reported in a separate section (never product docs).
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np

GYM_ROOT = Path(__file__).resolve().parent.parent
if str(GYM_ROOT) not in sys.path:
    sys.path.insert(0, str(GYM_ROOT))

from runners.fair_round import FEATURE_BY_ID, FIXED_P, score_direction  # noqa: E402
from runners.helpers import apply_app_gating, build_cal_plan, gating_masks, load_corpus  # noqa: E402

EXT = GYM_ROOT / "corpora" / "external"
CORPORA = {
    "lee2026-artifacts": (EXT / "lee2026_artifacts.npz", "awake", False),
    "lee2026-eo-ec": (EXT / "lee2026_eo_ec.npz", "awake", False),
    "universe-stress": (EXT / "universe_stress.npz", "awake", False),
    "ds001787-mw-muse": (EXT / "ds001787_mw_muse.npz", "awake", False),
    "rl2021-mw-muse": (EXT / "rl2021_mw_muse.npz", "awake", False),
    "boas-wake-n1": (EXT / "boas_wake_n1.npz", "sleep", False),
    "muse-sleeponset (LAB-ONLY)": (Path("/workspace/lab_only_out/muse_sleeponset.npz"), "sleep", True),
}
GUARDS = ("band.delta", "gym.delta_rel", "gym.theta_rel", "band.tar", "gym.tab", "ai.a_vig", "ai.wake_light")


def _task(rid: str) -> str:
    return rid.rsplit("/", 1)[-1]


def coverage(c: dict[str, Any]) -> dict[str, Any]:
    m = gating_masks(c)
    y = np.asarray(c["labels"]).astype(int)
    out = {"rows": int(y.size), "pad_gate": m["pad_gate"], "move_gate": m["move_gate"]}
    for k, ok in (("pad", m["pad_ok"]), ("move", m["move_ok"]), ("any", m["pad_ok"] & m["move_ok"])):
        out[f"drop_{k}"] = float((~ok).mean())
        out[f"drop_{k}_label0"] = float((~ok)[y == 0].mean()) if (y == 0).any() else None
        out[f"drop_{k}_label1"] = float((~ok)[y == 1].mean()) if (y == 1).any() else None
    return out


def artifact_catch(c: dict[str, Any]) -> dict[str, Any]:
    """Lee artifacts: fraction of cued-artifact rows (label 1) / clean rows (label 0) each gate flags, per task."""
    m = gating_masks(c)
    rid = np.asarray(c["recording_id"]).astype(str)
    y = np.asarray(c["labels"]).astype(int)
    out = {}
    for t in ("EB", "BT", "MVO", "MVC"):
        sel = np.array([_task(r) == t for r in rid])
        row = {}
        for lab in (1, 0):
            s = sel & (y == lab)
            if not s.any():
                continue
            pad = ~m["pad_ok"][s]
            mov = ~m["move_ok"][s]
            row[f"label{lab}"] = {"n": int(s.sum()), "pad": float(pad.mean()),
                                  "move": float(mov.mean()) if m["move_gate"] else None,
                                  "both_or": float((pad | mov).mean()) if m["move_gate"] else None}
        out[t] = row
    return out


def warn_rates(c: dict[str, Any]) -> dict[str, Any]:
    out = {}
    for fid in GUARDS:
        f = FEATURE_BY_ID[fid]
        s = f.getter(c, "")
        if s is None or not np.isfinite(s).any():
            continue
        r = score_direction(s, c, f.sleep_dir, ps=(FIXED_P,))
        g = r["guard"][FIXED_P]
        out[fid] = {"warn0": g["warn_rate_label0"], "warn1": g["warn_rate_label1"], "ba": g["balanced_acc"],
                    "auc_med": r["per_rec_auc_median"], "n_rec": r["per_rec_n"]}
    return out


def _f(x: Any, nd: int = 3) -> str:
    return "—" if x is None or (isinstance(x, float) and not np.isfinite(x)) else (f"{x:.{nd}f}" if isinstance(x, float) else str(x))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out-dir", type=Path, default=None)
    ap.add_argument("--only", default="")
    a = ap.parse_args(argv)
    board: dict[str, Any] = {"generated_utc": datetime.now(timezone.utc).isoformat(), "corpora": {}}
    md = ["# gating round\n\n"]
    for name, (path, kind, lab_only) in CORPORA.items():
        if a.only and a.only not in name:
            continue
        if not path.exists():
            board["corpora"][name] = {"status": "not built"}
            continue
        raw = load_corpus(path, gate=False)
        gated = apply_app_gating(raw)
        e = {"kind": kind, "lab_only": lab_only, "coverage": coverage(raw), "gating": gated["gating"],
             "cal_plan_ungated": build_cal_plan(raw).describe(), "cal_plan_gated": build_cal_plan(gated).describe(),
             "warn_ungated": warn_rates(raw), "warn_gated": warn_rates(gated)}
        if name == "lee2026-artifacts":
            e["artifact_catch"] = artifact_catch(raw)
        board["corpora"][name] = e
        print(name, e["coverage"]["drop_pad"], flush=True)
    # markdown
    md.append("## Coverage (fraction of rows each gate removes)\n\n| corpus | rows | pad gate | movement gate | removed: pad | label 0 / 1 | removed: movement |\n|---|---:|---|---|---:|---|---:|\n")
    for n, e in board["corpora"].items():
        if "coverage" not in e:
            md.append(f"| {n} | — | not built | | | | |\n")
            continue
        cv = e["coverage"]
        md.append(f"| {n} | {cv['rows']} | {'yes' if cv['pad_gate'] else 'no (no ch_*_q)'} | {'yes' if cv['move_gate'] else 'n/a (no IMU)'} | "
                  f"{_f(cv['drop_pad'])} | {_f(cv['drop_pad_label0'])} / {_f(cv['drop_pad_label1'])} | {_f(cv['drop_move']) if cv['move_gate'] else 'n/a'} |\n")
    if "lee2026-artifacts" in board["corpora"] and "artifact_catch" in board["corpora"]["lee2026-artifacts"]:
        md.append("\n## Lee 2026 cued artifacts: share of rows each gate flags\n\n| task | artifact rows: pad gate | movement | both (OR) | clean-rest rows: pad gate |\n|---|---:|---:|---:|---:|\n")
        for t, r in board["corpora"]["lee2026-artifacts"]["artifact_catch"].items():
            l1, l0 = r.get("label1", {}), r.get("label0", {})
            md.append(f"| {t} | {_f(l1.get('pad'))} (n={l1.get('n')}) | {_f(l1.get('move')) if l1.get('move') is not None else 'n/a'} | "
                      f"{_f(l1.get('both_or')) if l1.get('both_or') is not None else 'n/a'} | {_f(l0.get('pad'))} (n={l0.get('n')}) |\n")
    md.append(f"\n## Sleep-guard warning rate at p{FIXED_P} of each recording's own baseline, ungated → gated\n\n"
              "Awake corpora: every warning is false (both labels awake). Sleep corpora: label 0 = wake (false warnings), label 1 = N1 / pre-N2 (hits).\n\n"
              "| corpus | guard | warn on label 0: ungated → gated | warn on label 1: ungated → gated | BA ungated → gated | per-rec AUC ungated → gated |\n|---|---|---|---|---|---|\n")
    for n, e in board["corpora"].items():
        if "warn_ungated" not in e:
            continue
        for fid, u in e["warn_ungated"].items():
            g = e["warn_gated"].get(fid, {})
            md.append(f"| {n} | {fid} | {_f(u['warn0'])} → {_f(g.get('warn0'))} | {_f(u['warn1'])} → {_f(g.get('warn1'))} | "
                      f"{_f(u['ba'])} → {_f(g.get('ba'))} | {_f(u['auc_med'])} → {_f(g.get('auc_med'))} |\n")
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = a.out_dir or (GYM_ROOT / "results" / f"{ts}_gating")
    out.mkdir(parents=True, exist_ok=True)

    def clean(o: Any) -> Any:
        if isinstance(o, dict):
            return {str(k): clean(v) for k, v in o.items()}
        if isinstance(o, (list, tuple)):
            return [clean(v) for v in o]
        if isinstance(o, (float, np.floating)):
            return None if not np.isfinite(o) else round(float(o), 4)
        if isinstance(o, (np.integer, np.bool_)):
            return o.item()
        return o

    (out / "gating_board.json").write_text(json.dumps(clean(board), indent=1), encoding="utf-8")
    (out / "gating_tables.md").write_text("".join(md), encoding="utf-8")
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
