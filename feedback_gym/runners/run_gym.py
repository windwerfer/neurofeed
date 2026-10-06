#!/usr/bin/env python3
"""One-command feedback_gym entry: simulate protocols, score features, write stats+UI."""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Allow `python runners/run_gym.py` from feedback_gym/
GYM_ROOT = Path(__file__).resolve().parent.parent
if str(GYM_ROOT) not in sys.path:
    sys.path.insert(0, str(GYM_ROOT))

from runners.helpers import (  # noqa: E402
    GYM_ROOT as _GYM,
    build_cal_plan,
    generate_synthetic_corpus,
    load_catalog,
    load_corpus,
    load_grids,
    load_manifest,
    orphan_features,
)
from runners.score_feature import score_feature  # noqa: E402
from runners.simulate_protocol import simulate_protocol  # noqa: E402

NEUROFEED_ROOT = GYM_ROOT.parent
# Private findings-only corpora lab (windwerfer/neurofeed-gym-corpora), sibling checkout.
DEFAULT_CORPUS_ROOT = NEUROFEED_ROOT.parent / "neurofeed-gym-corpora"
CORPUS_ROOT_ENV = "NEUROFEED_GYM_CORPORA"
EXIT_MISSING_CORPUS = 2

BUILTIN_PRESETS = {
    "synthetic": "corpora/synthetic/demo_session.npz",
    "sleep-edf-test": "corpora/external/sleep_edf_test.npz",
}


class MissingCorpusError(RuntimeError):
    """A preset's NPZ is not built; message carries the exact build command."""


def sibling_presets(manifest: dict | None = None) -> dict[str, dict]:
    """Presets backed by the sibling corpora repo (manifest external[] with ``builder``)."""
    manifest = manifest if manifest is not None else load_manifest()
    out: dict[str, dict] = {}
    for entry in manifest.get("external", []):
        if entry.get("source_repo") and entry.get("builder") and entry.get("preset"):
            out[entry["preset"]] = entry
    return out


SIBLING_PRESETS = sibling_presets()
PRESETS = {**BUILTIN_PRESETS, **{k: e["path"] for k, e in SIBLING_PRESETS.items()}}


def default_corpus_root() -> Path | None:
    """``$NEUROFEED_GYM_CORPORA`` or ``../neurofeed-gym-corpora`` (if it exists)."""
    env = os.environ.get(CORPUS_ROOT_ENV)
    if env:
        return Path(env)
    return DEFAULT_CORPUS_ROOT if DEFAULT_CORPUS_ROOT.is_dir() else None


def builder_command(entry: dict, corpus_root: Path, out: Path) -> str:
    return f"python3 {corpus_root / entry['builder']} --out {out}"


def missing_corpus_message(preset: str, entry: dict, corpus_root: Path | None) -> str:
    out = (GYM_ROOT / entry["path"]).resolve()
    root = corpus_root if corpus_root is not None else DEFAULT_CORPUS_ROOT
    root = root.resolve()
    lines = [
        f"error: preset '{preset}' needs {entry['path']} (not found: {out}).",
        f"Build it with the sibling corpora repo ({entry.get('source_repo')}); "
        "the NPZ stays gitignored, findings-only:",
        f"  {builder_command(entry, root, out)}",
        f"then: python3 runners/run_gym.py --preset {preset}",
    ]
    if not root.is_dir():
        lines.append(
            f"note: corpus root {root} does not exist; clone "
            f"{entry.get('source_repo')} there, set ${CORPUS_ROOT_ENV}, or pass --corpus-root."
        )
    elif not (root / entry["builder"]).is_file():
        lines.append(f"note: {entry['builder']} is not in {root} yet (builder status: planned).")
    if entry.get("builder_status"):
        lines.append(f"note: builder status: {entry['builder_status']}")
    lines.append("Not falling back to the synthetic corpus.")
    return "\n".join(lines)


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


def _ensure_synthetic(manifest: dict) -> Path:
    synth = manifest.get("synthetic", {})
    rel = synth.get("path", "corpora/synthetic/demo_session.npz")
    path = GYM_ROOT / rel
    if not path.exists():
        generate_synthetic_corpus(path.parent)
    return path


def _ensure_sleep_edf(max_windows_per_rec: int | None, *, allow_fallback: bool = True) -> Path:
    """Build external Sleep-EDF NPZ if missing; fall back to synthetic on failure.

    ``allow_fallback=False`` (multi-corpus boards) raises MissingCorpusError instead,
    so a board column is never silently the synthetic demo.
    """
    out = GYM_ROOT / PRESETS["sleep-edf-test"]
    if out.exists():
        return out
    try:
        from runners.build_corpus_sleep_edf import build_corpus

        summary = build_corpus(
            out_path=out,
            max_windows_per_rec=max_windows_per_rec,
        )
        print(f"built sleep-edf corpus: n={summary['n']} -> {out}")
        return out
    except Exception as exc:  # noqa: BLE001 — intentional demo fallback
        if not allow_fallback:
            raise MissingCorpusError(
                f"error: preset 'sleep-edf-test' needs {PRESETS['sleep-edf-test']} and the "
                f"build failed ({exc}).\n"
                "  python3 runners/build_corpus_sleep_edf.py [--max-windows-per-rec 500]"
            ) from exc
        print(
            f"warning: sleep-edf corpus unavailable ({exc}); "
            "falling back to synthetic demo",
            file=sys.stderr,
        )
        return _ensure_synthetic(load_manifest())


def resolve_preset(
    name: str,
    *,
    corpus_root: Path | None,
    max_windows_per_rec: int | None = None,
    allow_fallback: bool = True,
) -> Path:
    """Preset name -> NPZ path. Sibling presets never build or fall back."""
    if name == "synthetic":
        return _ensure_synthetic(load_manifest())
    if name == "sleep-edf-test":
        return _ensure_sleep_edf(max_windows_per_rec, allow_fallback=allow_fallback)
    entry = SIBLING_PRESETS.get(name)
    if entry is None:
        raise ValueError(f"unknown preset '{name}'; choose from {sorted(PRESETS)}")
    path = GYM_ROOT / entry["path"]
    if not path.exists():
        raise MissingCorpusError(missing_corpus_message(name, entry, corpus_root))
    return path


def write_runs_index(out_path: Path) -> None:
    """Index results/*/summary.json (fallback run.json) for the Compare UI."""
    results = GYM_ROOT / "results"
    rows = []
    if results.is_dir():
        for d in sorted(results.iterdir()):
            if not d.is_dir():
                continue
            summary_path = d / "summary.json"
            run_path = d / "run.json"
            src = summary_path if summary_path.exists() else run_path
            if not src.exists():
                continue
            try:
                data = json.loads(src.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                continue
            rows.append(
                {
                    "run_id": data.get("run_id", d.name),
                    "timestamp": data.get("timestamp"),
                    "corpus": data.get("corpus"),
                    "summary": f"../results/{d.name}/summary.json",
                    "run": f"../results/{d.name}/run.json",
                }
            )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps({"runs": rows}, indent=2), encoding="utf-8")


def _extra_header_lines(run: dict) -> list[str]:
    """Only emitted for sibling / per-recording runs (legacy stats stay byte-identical)."""
    lines = []
    sib = run.get("sibling")
    if sib:
        lines.append(
            f"_Sibling corpus `{sib.get('id')}` ({sib.get('license')}, "
            f"{sib.get('use_status')}): aggregates only, no data in neurofeed._"
        )
    cal = run.get("calibration") or {}
    if cal.get("mode") == "per_recording":
        lines.append(
            f"_Calibration: per-recording (cal_starts/cal_lens), "
            f"{cal.get('n_recordings')} recordings, {cal.get('cal_rows')} cal rows excluded._"
        )
    return lines


def write_protocol_stats(run: dict, out_path: Path) -> None:
    lines = [
        "# PROTOCOL_STATS",
        "",
        f"_Generated: {run['timestamp']} _",
        f"_Run id: `{run['run_id']}`_",
        f"_Corpus: `{run['corpus']}`_",
        *_extra_header_lines(run),
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
        "- AI uses precomputed emb_cache + linear heads (no CBraMod/REVE forward).",
        "- Guard **scores** use `warn_feature` (percentile only); combined warn + rail "
        "still reported (Sleep-EDF abs delta often trips the 0.25 rail).",
        "- REVE columns are subsample-aligned (≤80/class/rec) and NaN-padded — Diggus: "
        "directional only vs full CBraMod.",
        "- Crown `device.*` marked N/A (no corpus).",
        "",
    ]
    out_path.write_text("\n".join(lines), encoding="utf-8")


def _commit_note(corpus_rel: str, sibling: dict | None) -> str:
    if sibling:
        return (
            f"sibling findings-only corpus {sibling.get('id')} "
            f"({sibling.get('source_repo')}); aggregates only"
        )
    if "sleep_edf" in corpus_rel:
        return "sleep-edf CBraMod+REVE emb_cache; guard warn_feature scoring"
    return "offline synthetic/demo unless --corpus/--preset overridden"


def _corpus_meta(corpus: dict) -> dict[str, Any]:
    def _s(key):
        v = corpus.get(key)
        if v is None:
            return None
        v = v.tolist() if hasattr(v, "tolist") else v
        return v

    return {
        "corpus_id": _s("corpus_id"),
        "label_names": _s("label_names"),
        "cal_policy": _s("cal_policy"),
        "n": int(len(corpus["delta_rel"])),
    }


def run_corpus(
    corpus_path: Path,
    *,
    run_id: str,
    timestamp: str,
    protocols: dict,
    features: dict,
    grids: dict,
    preset: str | None = None,
) -> dict[str, Any]:
    """Score one corpus into results/<run_id>/ (run/protocols/features/summary json)."""
    corpus = load_corpus(corpus_path)
    plan = build_cal_plan(corpus)
    orphans = orphan_features(protocols, features)
    roles = _feature_roles(protocols)

    results_dir = GYM_ROOT / "results" / run_id
    results_dir.mkdir(parents=True, exist_ok=True)

    protocol_results = [simulate_protocol(proto, corpus, grids) for proto in protocols.values()]
    feature_results = [
        score_feature(
            fid,
            meta,
            corpus,
            grids,
            is_orphan=fid in orphans,
            roles_in_protocols=roles.get(fid, []),
        )
        for fid, meta in features.items()
    ]

    try:
        corpus_rel = str(corpus_path.resolve().relative_to(GYM_ROOT.resolve()))
    except ValueError:
        corpus_rel = str(corpus_path)

    sib_entry = SIBLING_PRESETS.get(preset) if preset else None
    sibling = (
        {
            k: sib_entry.get(k)
            for k in ("id", "source_repo", "license", "use_status", "corpus_id")
        }
        if sib_entry
        else None
    )

    run: dict[str, Any] = {
        "run_id": run_id,
        "timestamp": timestamp,
        "corpus": corpus_rel,
        "commit_note": _commit_note(corpus_rel, sibling),
        "protocols": protocol_results,
        "features": feature_results,
        "grids": {
            "reward_percentiles": grids.get("reward_percentiles"),
            "guard_percentiles": grids.get("guard_percentiles"),
            "defaults": grids.get("defaults"),
        },
        "preset": preset,
        "calibration": plan.describe(),
        "corpus_meta": _corpus_meta(corpus),
    }
    if sibling:
        run["sibling"] = sibling

    (results_dir / "run.json").write_text(json.dumps(run, indent=2), encoding="utf-8")
    (results_dir / "protocols.json").write_text(
        json.dumps(protocol_results, indent=2), encoding="utf-8"
    )
    (results_dir / "features.json").write_text(
        json.dumps(feature_results, indent=2), encoding="utf-8"
    )
    summary = {
        "run_id": run_id,
        "timestamp": run["timestamp"],
        "corpus": corpus_rel,
        "preset": preset,
        "commit_note": run.get("commit_note"),
        "calibration": run["calibration"],
        "protocols": [
            {
                "id": p["id"],
                "final": p.get("final"),
                "reward_score": ((p.get("parts") or {}).get("reward") or {}).get("score"),
                "inhibit_score": ((p.get("parts") or {}).get("inhibit") or {}).get("score"),
                "guard_score": ((p.get("parts") or {}).get("guard") or {}).get("score"),
            }
            for p in protocol_results
        ],
        "features": [
            {
                "id": f["id"],
                "score": f.get("score"),
                "sep": f.get("sep"),
                "best_p": f.get("best_p"),
                "status": f.get("status"),
            }
            for f in feature_results
        ],
    }
    (results_dir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    run["_results_dir"] = str(results_dir)
    return run


# --- Multi-corpus board -----------------------------------------------------------


def _na(status: str | None, reason: str | None = None) -> dict[str, Any]:
    cell: dict[str, Any] = {"na": True, "status": status or "absent"}
    if reason:
        cell["reason"] = reason
    return cell


def _part_score(part: Any) -> float | None | str:
    """Score of a protocol part; 'N/A' when the lane exists but its feature is missing."""
    if part is None:
        return None  # lane not declared by the protocol
    if isinstance(part, dict) and part.get("status") in ("unavailable", "n/a"):
        return "N/A"
    return part.get("score") if isinstance(part, dict) else None


def merge_boards(runs: list[tuple[str, dict]]) -> dict[str, Any]:
    """Side-by-side board from per-corpus runs: [(label, run_dict), ...].

    A feature/protocol a corpus cannot score (missing column, all-NaN, device.*,
    absent from that run) becomes ``{"na": true, "status": ...}``.
    """
    labels = [lab for lab, _ in runs]
    corpora = []
    feat_ids: list[str] = []
    proto_ids: list[str] = []
    feat_by: dict[str, dict[str, dict]] = {}
    proto_by: dict[str, dict[str, dict]] = {}
    for lab, run in runs:
        corpora.append(
            {
                "label": lab,
                "run_id": run.get("run_id"),
                "corpus": run.get("corpus"),
                "preset": run.get("preset"),
                "calibration": run.get("calibration"),
                "corpus_meta": run.get("corpus_meta"),
                "sibling": run.get("sibling"),
            }
        )
        for f in run.get("features", []):
            if f["id"] not in feat_ids:
                feat_ids.append(f["id"])
            feat_by.setdefault(f["id"], {})[lab] = f
        for p in run.get("protocols", []):
            if p["id"] not in proto_ids:
                proto_ids.append(p["id"])
            proto_by.setdefault(p["id"], {})[lab] = p

    features_out = []
    for fid in feat_ids:
        row: dict[str, Any] = {"id": fid, "by_corpus": {}}
        for lab in labels:
            f = feat_by[fid].get(lab)
            if f is None:
                row["by_corpus"][lab] = _na("absent", "feature not in this run")
            elif f.get("status") != "ok" or f.get("score") is None:
                notes = f.get("notes") or []
                row["by_corpus"][lab] = _na(f.get("status"), notes[0] if notes else None)
            else:
                row["by_corpus"][lab] = {
                    "score": f.get("score"),
                    "sep": f.get("sep"),
                    "best_p": f.get("best_p"),
                    "status": "ok",
                }
        features_out.append(row)

    protocols_out = []
    for pid in proto_ids:
        row = {"id": pid, "by_corpus": {}}
        for lab in labels:
            p = proto_by[pid].get(lab)
            if p is None:
                row["by_corpus"][lab] = _na("absent", "protocol not in this run")
                continue
            parts = p.get("parts") or {}
            cell = {
                "final": p.get("final"),
                "reward": _part_score(parts.get("reward")),
                "inhibit": _part_score(parts.get("inhibit")),
                "guard": _part_score(parts.get("guard")),
                "notes": p.get("notes") or [],
            }
            if cell["final"] is None:
                cell["na"] = True
            row["by_corpus"][lab] = cell
        protocols_out.append(row)

    return {
        "corpora": corpora,
        "labels": labels,
        "features": features_out,
        "protocols": protocols_out,
    }


def _fmt(v: Any) -> str:
    if v == "N/A":
        return "N/A"
    return f"{v:.3f}" if isinstance(v, (int, float)) else "—"


def render_multi_stats(board: dict, *, run_id: str, timestamp: str) -> str:
    labels = board["labels"]
    lines = [
        "# MULTI_CORPUS_STATS",
        "",
        f"_Generated: {timestamp} _",
        f"_Board: `results/{run_id}/multi_board.json`_",
        "",
        "> Metrics: [`metrics.md`](metrics.md). Aggregates only; sibling corpora are "
        "findings-only and their data never lands in neurofeed. **N/A** = the corpus "
        "cannot score that feature/lane (e.g. no `ai_*` column).",
        "",
        "## Corpora",
        "",
        "| corpus | run | N | labels | calibration | license / use |",
        "|--------|-----|--:|--------|-------------|---------------|",
    ]
    for c in board["corpora"]:
        meta = c.get("corpus_meta") or {}
        cal = c.get("calibration") or {}
        cal_s = (
            f"per-recording ({cal.get('n_recordings')} rec)"
            if cal.get("mode") == "per_recording"
            else f"global cal_n={cal.get('cal_n')}"
        )
        sib = c.get("sibling") or {}
        lic = f"{sib.get('license')} / {sib.get('use_status')}" if sib else "built-in preset"
        ln = meta.get("label_names")
        ln_s = "/".join(ln) if isinstance(ln, list) else "—"
        lines.append(
            f"| {c['label']} | `{c.get('run_id')}` | {meta.get('n', '—')} | {ln_s} | {cal_s} | {lic} |"
        )

    head = "| id | " + " | ".join(labels) + " |"
    sep = "|----|" + "|".join("------:" for _ in labels) + "|"
    lines += ["", "## Protocols (final · r/i/g)", "", head, sep]
    for row in board["protocols"]:
        cells = []
        for lab in labels:
            c = row["by_corpus"][lab]
            if c.get("status") == "absent":
                cells.append("N/A")
                continue
            final = "N/A" if c.get("final") is None else _fmt(c["final"])
            cells.append(
                f"{final} (r {_fmt(c.get('reward'))} · i {_fmt(c.get('inhibit'))} · g {_fmt(c.get('guard'))})"
            )
        lines.append(f"| {row['id']} | " + " | ".join(cells) + " |")

    lines += ["", "## Features (score · sep · best_p)", "", head, sep]
    for row in board["features"]:
        cells = []
        for lab in labels:
            c = row["by_corpus"][lab]
            if c.get("na"):
                cells.append(f"N/A ({c.get('status')})")
            else:
                cells.append(f"{_fmt(c.get('score'))} · sep {_fmt(c.get('sep'))} · p{c.get('best_p')}")
        lines.append(f"| {row['id']} | " + " | ".join(cells) + " |")
    lines.append("")
    return "\n".join(lines)


def _write_living_outputs(run: dict) -> None:
    """Single-corpus 'living' outputs: ui/data/latest.json, latest_run_id, PROTOCOL_STATS.md."""
    ui_data = GYM_ROOT / "ui" / "data"
    ui_data.mkdir(parents=True, exist_ok=True)
    public = {k: v for k, v in run.items() if not k.startswith("_")}
    (ui_data / "latest.json").write_text(json.dumps(public, indent=2), encoding="utf-8")
    (GYM_ROOT / "results" / "latest_run_id.txt").write_text(run["run_id"] + "\n", encoding="utf-8")
    write_protocol_stats(run, GYM_ROOT / "PROTOCOL_STATS.md")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run feedback_gym offline harness")
    parser.add_argument("--all", action="store_true", default=True, help="run everything")
    parser.add_argument("--corpus", type=str, default=None, help="override corpus NPZ path")
    parser.add_argument(
        "--preset",
        type=str,
        choices=sorted(PRESETS.keys()),
        default=None,
        help="named corpus: synthetic (default), sleep-edf-test (builds if missing), "
        "or a sibling findings-only corpus (" + ", ".join(sorted(SIBLING_PRESETS)) + ")",
    )
    parser.add_argument(
        "--presets",
        type=str,
        default=None,
        help="comma list of presets: one results/<run_id>_<preset>/ each + one "
        "results/<run_id>_multi/multi_board.json and MULTI_CORPUS_STATS.md",
    )
    parser.add_argument(
        "--corpus-root",
        type=Path,
        default=None,
        help="checkout of windwerfer/neurofeed-gym-corpora used to resolve sibling "
        f"builder paths (default: ${CORPUS_ROOT_ENV} or {DEFAULT_CORPUS_ROOT} if it exists)",
    )
    parser.add_argument(
        "--max-windows-per-rec",
        type=int,
        default=None,
        help="when building sleep-edf-test, cap windows per recording",
    )
    args = parser.parse_args(argv)
    corpus_root = args.corpus_root if args.corpus_root is not None else default_corpus_root()

    if args.presets and (args.corpus or args.preset):
        parser.error("--presets cannot be combined with --corpus/--preset")

    protocols, features = load_catalog()
    grids = load_grids()
    manifest = load_manifest()
    ts = datetime.now(timezone.utc)
    stamp = ts.strftime("%Y-%m-%d %H:%M:%S UTC")
    base_id = ts.strftime("%Y%m%dT%H%M%SZ")

    if args.presets:
        names = list(dict.fromkeys(n.strip() for n in args.presets.split(",") if n.strip()))
        unknown = [n for n in names if n not in PRESETS]
        if unknown:
            parser.error(f"unknown preset(s) {unknown}; choose from {sorted(PRESETS)}")
        # Resolve everything first: no partial board if one corpus is missing.
        paths: dict[str, Path] = {}
        errors: list[str] = []
        for name in names:
            try:
                paths[name] = resolve_preset(
                    name,
                    corpus_root=corpus_root,
                    max_windows_per_rec=args.max_windows_per_rec,
                    allow_fallback=False,
                )
            except MissingCorpusError as exc:
                errors.append(str(exc))
        if errors:
            print("\n\n".join(errors), file=sys.stderr)
            return EXIT_MISSING_CORPUS

        runs: list[tuple[str, dict]] = []
        for name in names:
            run = run_corpus(
                paths[name],
                run_id=f"{base_id}_{name}",
                timestamp=stamp,
                protocols=protocols,
                features=features,
                grids=grids,
                preset=name,
            )
            runs.append((name, run))
            print(f"  [{name}] {run['corpus']} -> {run['_results_dir']}")

        multi_id = f"{base_id}_multi"
        multi_dir = GYM_ROOT / "results" / multi_id
        multi_dir.mkdir(parents=True, exist_ok=True)
        board = merge_boards(runs)
        board.update({"run_id": multi_id, "timestamp": stamp})
        (multi_dir / "multi_board.json").write_text(json.dumps(board, indent=2), encoding="utf-8")
        md = render_multi_stats(board, run_id=multi_id, timestamp=stamp)
        (multi_dir / "MULTI_CORPUS_STATS.md").write_text(md, encoding="utf-8")
        (GYM_ROOT / "MULTI_CORPUS_STATS.md").write_text(md, encoding="utf-8")
        write_runs_index(GYM_ROOT / "ui" / "data" / "runs_index.json")
        print(f"feedback_gym multi-corpus board {multi_id}")
        print(f"  corpora: {', '.join(names)}")
        print(f"  board:   {multi_dir / 'multi_board.json'}")
        print(f"  stats:   {GYM_ROOT / 'MULTI_CORPUS_STATS.md'}")
        print("  (PROTOCOL_STATS.md / ui/data/latest.json untouched in multi mode)")
        return 0

    if args.corpus:
        corpus_path = Path(args.corpus)
        if not corpus_path.is_absolute():
            # resolve relative to CWD first, then gym root
            cand = Path.cwd() / corpus_path
            corpus_path = cand if cand.exists() else (GYM_ROOT / corpus_path)
    elif args.preset is None:
        corpus_path = _ensure_synthetic(manifest)
    else:
        try:
            corpus_path = resolve_preset(
                args.preset,
                corpus_root=corpus_root,
                max_windows_per_rec=args.max_windows_per_rec,
            )
        except MissingCorpusError as exc:
            print(str(exc), file=sys.stderr)
            return EXIT_MISSING_CORPUS

    run = run_corpus(
        corpus_path,
        run_id=base_id,
        timestamp=stamp,
        protocols=protocols,
        features=features,
        grids=grids,
        preset=args.preset,
    )
    _write_living_outputs(run)
    ui_data = GYM_ROOT / "ui" / "data"
    write_runs_index(ui_data / "runs_index.json")

    print(f"feedback_gym run {run['run_id']}")
    print(f"  protocols: {len(run['protocols'])}")
    print(f"  features:  {len(run['features'])}")
    print(f"  corpus:    {run['corpus']}")
    print(f"  results:   {run['_results_dir']}")
    print(f"  stats:     {GYM_ROOT / 'PROTOCOL_STATS.md'}")
    print(f"  ui data:   {ui_data / 'latest.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
