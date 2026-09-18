#!/usr/bin/env python3
"""One-command feedback_gym entry: simulate protocols, score features, write stats+UI."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

# Allow `python runners/run_gym.py` from feedback_gym/
GYM_ROOT = Path(__file__).resolve().parent.parent
if str(GYM_ROOT) not in sys.path:
    sys.path.insert(0, str(GYM_ROOT))

from runners.helpers import (  # noqa: E402
    GYM_ROOT as _GYM,
    generate_synthetic_corpus,
    load_catalog,
    load_corpus,
    load_grids,
    load_manifest,
    orphan_features,
)
from runners.score_feature import score_feature  # noqa: E402
from runners.simulate_protocol import simulate_protocol  # noqa: E402


def _feature_roles(protocols: dict) -> dict[str, list[str]]:
    roles: dict[str, list[str]] = {}
    for pid, p in protocols.items():
        if p.get("reward"):
            fid = p["reward"]["feature"]
            roles.setdefault(fid, []).append(f"reward@{pid}")
        if p.get("guard"):
            fid = p["guard"]["feature"]
            roles.setdefault(fid, []).append(f"guard@{pid}")
    return roles


def _ensure_corpus(manifest: dict) -> Path:
    synth = manifest.get("synthetic", {})
    rel = synth.get("path", "corpora/synthetic/demo_session.npz")
    path = GYM_ROOT / rel
    if not path.exists():
        generate_synthetic_corpus(path.parent)
    return path


def write_protocol_stats(run: dict, out_path: Path) -> None:
    lines = [
        "# PROTOCOL_STATS",
        "",
        f"_Generated: {run['timestamp']} _",
        f"_Run id: `{run['run_id']}`_",
        f"_Corpus: `{run['corpus']}`_",
        "",
        "> Metrics are defined in [`metrics.md`](metrics.md). "
        "Do not claim performance without them.",
        "",
        f"UI dashboard: [`ui/index.html`](ui/index.html) "
        f"(loads `ui/data/latest.json`).",
        "",
        "## Protocols (composite + parts)",
        "",
        "| id | final | reward | inhibit | guard | notes |",
        "|----|------:|-------:|--------:|------:|-------|",
    ]
    for p in run["protocols"]:
        parts = p.get("parts") or {}
        r = parts.get("reward") or {}
        i = parts.get("inhibit") or {}
        g = parts.get("guard") or {}

        def _s(obj, key="score"):
            if obj is None:
                return "—"
            if isinstance(obj, dict) and obj.get("status") in ("unavailable", "n/a"):
                return "N/A"
            v = obj.get(key) if isinstance(obj, dict) else None
            return f"{v:.3f}" if isinstance(v, (int, float)) else "—"

        notes = "; ".join(p.get("notes") or []) or ""
        final = p.get("final")
        final_s = f"{final:.3f}" if isinstance(final, (int, float)) else "N/A"
        lines.append(
            f"| {p['id']} | {final_s} | {_s(r)} | {_s(i)} | {_s(g)} | {notes} |"
        )

    lines += [
        "",
        "## Features (standalone board)",
        "",
        "| id | role | orphan | best_p | score | sep | status | latency |",
        "|----|------|--------|-------:|------:|----:|--------|---------|",
    ]
    for f in run["features"]:
        roles = ",".join(f.get("usableFor") or [])
        orphan = "yes" if f.get("orphan") else ""
        bp = f.get("best_p")
        bp_s = str(bp) if bp is not None else "—"
        sc = f.get("score")
        sc_s = f"{sc:.3f}" if isinstance(sc, (int, float)) else "—"
        sep = f.get("sep")
        sep_s = f"{sep:.3f}" if isinstance(sep, (int, float)) else "—"
        lines.append(
            f"| {f['id']} | {roles} | {orphan} | {bp_s} | {sc_s} | {sep_s} | "
            f"{f.get('status')} | {f.get('latency')} |"
        )

    lines += [
        "",
        "## Sweeps",
        "",
        "Per-feature percentile curves are in the UI **Sweeps** tab and in "
        f"`results/{run['run_id']}/features.json`.",
        "",
        "## Approximations vs Dart lanes",
        "",
        "- Fixed calibration threshold (no EMA dynamic adapt).",
        "- No dirty-pad / quality gating.",
        "- AI uses precomputed fixture columns (no CBraMod/REVE forward).",
        "- Crown `device.*` marked N/A (no corpus).",
        "",
    ]
    out_path.write_text("\n".join(lines), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run feedback_gym offline harness")
    parser.add_argument("--all", action="store_true", default=True, help="run everything")
    parser.add_argument("--corpus", type=str, default=None, help="override corpus NPZ path")
    args = parser.parse_args(argv)

    protocols, features = load_catalog()
    grids = load_grids()
    manifest = load_manifest()

    if args.corpus:
        corpus_path = Path(args.corpus)
    else:
        corpus_path = _ensure_corpus(manifest)
    corpus = load_corpus(corpus_path)

    orphans = orphan_features(protocols, features)
    roles = _feature_roles(protocols)

    ts = datetime.now(timezone.utc)
    run_id = ts.strftime("%Y%m%dT%H%M%SZ")
    results_dir = GYM_ROOT / "results" / run_id
    results_dir.mkdir(parents=True, exist_ok=True)

    protocol_results = []
    for pid, proto in protocols.items():
        protocol_results.append(simulate_protocol(proto, corpus, grids))

    feature_results = []
    for fid, meta in features.items():
        feature_results.append(
            score_feature(
                fid,
                meta,
                corpus,
                grids,
                is_orphan=fid in orphans,
                roles_in_protocols=roles.get(fid, []),
            )
        )

    run = {
        "run_id": run_id,
        "timestamp": ts.strftime("%Y-%m-%d %H:%M:%S UTC"),
        "corpus": str(corpus_path.relative_to(GYM_ROOT)),
        "commit_note": "offline synthetic/demo unless --corpus overridden",
        "protocols": protocol_results,
        "features": feature_results,
        "grids": {
            "reward_percentiles": grids.get("reward_percentiles"),
            "guard_percentiles": grids.get("guard_percentiles"),
            "defaults": grids.get("defaults"),
        },
    }

    (results_dir / "run.json").write_text(json.dumps(run, indent=2), encoding="utf-8")
    (results_dir / "protocols.json").write_text(
        json.dumps(protocol_results, indent=2), encoding="utf-8"
    )
    (results_dir / "features.json").write_text(
        json.dumps(feature_results, indent=2), encoding="utf-8"
    )

    # Latest pointer for UI
    ui_data = GYM_ROOT / "ui" / "data"
    ui_data.mkdir(parents=True, exist_ok=True)
    (ui_data / "latest.json").write_text(json.dumps(run, indent=2), encoding="utf-8")
    # also copy under results as latest symlink-like file
    latest_ptr = GYM_ROOT / "results" / "latest_run_id.txt"
    latest_ptr.write_text(run_id + "\n", encoding="utf-8")

    write_protocol_stats(run, GYM_ROOT / "PROTOCOL_STATS.md")

    print(f"feedback_gym run {run_id}")
    print(f"  protocols: {len(protocol_results)}")
    print(f"  features:  {len(feature_results)}")
    print(f"  results:   {results_dir}")
    print(f"  stats:     {GYM_ROOT / 'PROTOCOL_STATS.md'}")
    print(f"  ui data:   {ui_data / 'latest.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
