"""Shared helpers: catalog load, percentile semantics, metrics, corpus I/O."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import numpy as np
import yaml

GYM_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = GYM_ROOT.parent


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as f:
        return yaml.safe_load(f)


def load_catalog() -> tuple[dict[str, Any], dict[str, Any]]:
    protocols = load_json(REPO_ROOT / "assets" / "protocols.json")["protocols"]
    features = load_json(REPO_ROOT / "assets" / "features.json")["features"]
    return protocols, features


def load_grids() -> dict[str, Any]:
    return load_yaml(GYM_ROOT / "sweeps" / "grids.yaml")


def load_manifest() -> dict[str, Any]:
    return load_json(GYM_ROOT / "corpora" / "manifest.json")


# --- Percentile / threshold (mirrors RatioEngine + GuardLane) -----------------


def threshold_at_percentile(baseline: np.ndarray, percentile: float) -> float:
    """Dart: idx = round((p/100) * (n-1)); threshold = sorted[idx]."""
    arr = np.sort(np.asarray(baseline, dtype=float))
    if arr.size == 0:
        raise ValueError("empty baseline")
    idx = int(round((percentile / 100.0) * (arr.size - 1)))
    idx = max(0, min(arr.size - 1, idx))
    return float(arr[idx])


def percentile_of(baseline: np.ndarray, value: float) -> float | None:
    """Dart: (count of baseline < value) / n * 100."""
    arr = np.asarray(baseline, dtype=float)
    if arr.size == 0:
        return None
    below = int(np.sum(arr < value))
    return (below / arr.size) * 100.0


def uptrain_in_target(values: np.ndarray, threshold: float) -> np.ndarray:
    """percentileUptrain: value > threshold."""
    return np.asarray(values, dtype=float) > threshold


def inhibit_passes(
    inhibit: list[dict[str, Any]],
    delta_rel: np.ndarray,
    theta_rel: np.ndarray,
    alpha_rel: np.ndarray,
    beta_rel: np.ndarray,
) -> tuple[np.ndarray, dict[str, np.ndarray]]:
    """AND-gate of inhibit conditions. Returns (all_pass, per_tag_fail_mask)."""
    n = len(delta_rel)
    all_pass = np.ones(n, dtype=bool)
    fails: dict[str, np.ndarray] = {}
    for cond in inhibit:
        ctype = cond.get("type")
        mx = float(cond.get("max", cond.get("maxBetaRel", cond.get("maxDeltaRel", 1.0))))
        if ctype == "betaCeiling":
            ok = beta_rel <= mx
            tag = "beta"
        elif ctype == "deltaCeiling":
            ok = delta_rel <= mx
            tag = "delta"
        else:
            raise ValueError(f"unknown inhibit type: {ctype}")
        fails[tag] = ~ok
        all_pass &= ok
    return all_pass, fails


def percentile_warn_parts(
    *,
    band_math: bool,
    feature_values: np.ndarray,
    delta_abs: np.ndarray,
    threshold: float,
    delta_ceiling: float = 0.25,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Split guard warn into feature / rail / combined.

    - ``warn_feature``: feature vs percentile threshold only (no delta rail)
    - ``warn_rail``: absolute delta-ceiling fires (plus band abs ceiling)
    - ``warn``: combined OR — fidelity to app ``percentileWarnOver``
    """
    feat = np.asarray(feature_values, dtype=float)
    delta = np.asarray(delta_abs, dtype=float)
    warn_feature = feat > threshold
    if band_math:
        # band path also treats feat > ceiling as an absolute rail
        warn_rail = (feat > delta_ceiling) | (delta > delta_ceiling)
    else:
        warn_rail = delta > delta_ceiling
    warn = warn_feature | warn_rail
    return warn_feature, warn_rail, warn


def percentile_warn_over(
    *,
    band_math: bool,
    feature_values: np.ndarray,
    delta_abs: np.ndarray,
    threshold: float,
    delta_ceiling: float = 0.25,
) -> np.ndarray:
    """Mirrors guard_lane.percentileWarnOver (combined feature | rail)."""
    _, _, warn = percentile_warn_parts(
        band_math=band_math,
        feature_values=feature_values,
        delta_abs=delta_abs,
        threshold=threshold,
        delta_ceiling=delta_ceiling,
    )
    return warn


# --- Metrics ------------------------------------------------------------------


def hit_rate(in_target: np.ndarray) -> float:
    if in_target.size == 0:
        return float("nan")
    return float(np.mean(in_target.astype(float)))


def flip_stability(decisions: np.ndarray) -> float:
    d = np.asarray(decisions, dtype=bool)
    if d.size < 2:
        return 1.0
    flips = np.mean(d[1:] != d[:-1])
    return float(1.0 - flips)


def inhibit_block_rate(
    above_threshold: np.ndarray, blocked_by_tag: np.ndarray
) -> float:
    """Share of otherwise-in-target samples blocked by this inhibit."""
    pool = int(np.sum(above_threshold))
    if pool == 0:
        return 0.0
    return float(np.sum(above_threshold & blocked_by_tag) / pool)


def warn_rate(warn: np.ndarray) -> float:
    if warn.size == 0:
        return float("nan")
    return float(np.mean(warn.astype(float)))


def label_align(warn: np.ndarray, labels: np.ndarray | None) -> float | None:
    if labels is None:
        return None
    y = np.asarray(labels, dtype=int)
    w = np.asarray(warn, dtype=bool)
    if y.size != w.size or y.size == 0:
        return None
    tp = int(np.sum((y == 1) & w))
    fn = int(np.sum((y == 1) & ~w))
    fp = int(np.sum((y == 0) & w))
    tn = int(np.sum((y == 0) & ~w))
    tpr = tp / (tp + fn) if (tp + fn) else 0.0
    fpr = fp / (fp + tn) if (fp + tn) else 0.0
    return float(0.5 * tpr + 0.5 * (1.0 - fpr))


def roc_auc(scores: np.ndarray, labels: np.ndarray | None) -> float | None:
    if labels is None:
        return None
    y = np.asarray(labels, dtype=int)
    s = np.asarray(scores, dtype=float)
    if y.size != s.size or y.size == 0:
        return None
    pos = s[y == 1]
    neg = s[y == 0]
    if pos.size == 0 or neg.size == 0:
        return None
    # Mann–Whitney U / ROC AUC; report direction-invariant separation
    correct = 0.0
    for pv in pos:
        correct += float(np.sum(neg < pv)) + 0.5 * float(np.sum(neg == pv))
    auc = float(correct / (pos.size * neg.size))
    return max(auc, 1.0 - auc)


def roc_auc_up(scores: np.ndarray, labels: np.ndarray | None) -> float | None:
    """Directional ROC AUC: P(label-1 score > label-0 score), ties 1/2.

    Unlike :func:`roc_auc` (``sep``, folded to ``max(auc, 1-auc)``) this keeps
    the direction: < 0.5 means the feature moves the other way for label 1.
    """
    if labels is None:
        return None
    y = np.asarray(labels, dtype=int)
    s = np.asarray(scores, dtype=float)
    if y.size != s.size or y.size == 0:
        return None
    m = np.isfinite(s)
    s, y = s[m], y[m]
    n1, n0 = int((y == 1).sum()), int((y == 0).sum())
    if n1 == 0 or n0 == 0:
        return None
    _, inv, counts = np.unique(s, return_inverse=True, return_counts=True)
    ends = np.cumsum(counts)
    avg_rank = ends - (counts - 1) / 2.0  # 1-based average rank per unique value
    ranks = avg_rank[inv]
    u = float(ranks[y == 1].sum()) - n1 * (n1 + 1) / 2.0
    return float(u / (n1 * n0))


def warn_rate_health(
    rate: float, *, target: float = 0.15, low: float = 0.01, high: float = 0.55
) -> float:
    """Fallback guard health when labels are absent (widened band).

    Prefer ``label_align(warn_feature)`` whenever labels exist.
    """
    if math.isnan(rate):
        return 0.0
    if rate < low or rate > high:
        return 0.0
    # Triangular peak at target within [low, high]
    if rate <= target:
        return float((rate - low) / (target - low)) if target > low else 1.0
    return float((high - rate) / (high - target)) if high > target else 1.0


def guard_feature_score(
    *,
    sep: float | None,
    label_align_feature: float | None,
    warn_rate_combined: float | None,
    sep_weight: float = 0.6,
    label_align_weight: float = 0.4,
    warn_health_target: float = 0.15,
    warn_health_low: float = 0.01,
    warn_health_high: float = 0.55,
) -> float | None:
    """Standalone feature guard score.

    With labels: ``sep_weight * sep + label_align_weight * label_align(warn_feature)``.
    Without labels: softened ``warn_rate_health`` on the combined warn rate.
    """
    if label_align_feature is not None and sep is not None:
        return float(sep_weight * sep + label_align_weight * label_align_feature)
    if label_align_feature is not None:
        return float(label_align_feature)
    if sep is not None and warn_rate_combined is None:
        return float(sep)
    if warn_rate_combined is not None:
        return warn_rate_health(
            warn_rate_combined,
            target=warn_health_target,
            low=warn_health_low,
            high=warn_health_high,
        )
    return sep


def inhibit_health(block: float, target: float = 0.25) -> float:
    return float(max(0.0, 1.0 - 2.0 * abs(block - target)))


def protocol_composite(
    *,
    reward_score: float | None,
    guard_score: float | None,
    inhibit_score: float | None,
    weights: dict[str, Any],
) -> float | None:
    parts: list[tuple[float, float]] = []
    rw = float(weights.get("reward_weight", 0.5))
    gw = float(weights.get("guard_weight", 0.3))
    iw = float(weights.get("inhibit_weight", 0.2))
    if reward_score is not None:
        parts.append((rw, reward_score))
    if guard_score is not None:
        parts.append((gw, guard_score))
    if inhibit_score is not None:
        parts.append((iw, inhibit_score))
    if not parts:
        return None
    tw = sum(w for w, _ in parts)
    return float(sum(w * s for w, s in parts) / tw)


# --- Corpus -------------------------------------------------------------------


def generate_synthetic_corpus(out_dir: Path, n: int = 600, seed: int = 42) -> Path:
    """Write demo NPZ with band + AI columns and drowsy labels."""
    rng = np.random.default_rng(seed)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Two regimes: wake (0) then drowsy drift (1)
    half = n // 2
    labels = np.array([0] * half + [1] * (n - half), dtype=np.int32)

    # Relative bands that sum ~1 across delta/theta/alpha/beta/(gamma stub)
    def rel_stack(drowsy_frac: float) -> dict[str, np.ndarray]:
        # drowsy → more delta/theta, less alpha/beta
        delta = 0.15 + 0.25 * drowsy_frac + 0.04 * rng.normal(size=n)
        theta = 0.18 + 0.12 * drowsy_frac + 0.03 * rng.normal(size=n)
        alpha = 0.30 - 0.12 * drowsy_frac + 0.04 * rng.normal(size=n)
        beta = 0.22 - 0.10 * drowsy_frac + 0.03 * rng.normal(size=n)
        gamma = 0.15 + 0.02 * rng.normal(size=n)
        stack = np.vstack([delta, theta, alpha, beta, gamma])
        stack = np.clip(stack, 0.02, None)
        stack = stack / stack.sum(axis=0, keepdims=True)
        return {
            "delta_rel": stack[0],
            "theta_rel": stack[1],
            "alpha_rel": stack[2],
            "beta_rel": stack[3],
            "gamma_rel": stack[4],
        }

    drowsy_frac = labels.astype(float)
    # Smooth transition
    ramp = np.linspace(0, 1, 40)
    drowsy_frac = drowsy_frac.copy().astype(float)
    drowsy_frac[half - 20 : half + 20] = np.concatenate(
        [ramp[:20], ramp[20:]]
    ) if n >= half + 20 else drowsy_frac[half - 20 : half + 20]

    rel = rel_stack(drowsy_frac)

    atr = rel["alpha_rel"] / np.clip(rel["theta_rel"], 1e-3, None)
    tar = rel["theta_rel"] / np.clip(rel["alpha_rel"], 1e-3, None)
    btr = rel["beta_rel"] / np.clip(rel["theta_rel"], 1e-3, None)
    alpha = rel["alpha_rel"]
    # Absolute frontal delta proxy (µV²/Hz-ish scale around 0.05–0.4)
    delta_abs = 0.08 + 0.35 * drowsy_frac + 0.03 * rng.normal(size=n)
    delta_abs = np.clip(delta_abs, 0.01, 1.0)

    # Precomputed AI scores (P(hypnagogic) / P(light)) correlated with labels
    noise = 0.08 * rng.normal(size=n)
    ai_a_vig = np.clip(0.15 + 0.65 * drowsy_frac + noise, 0, 1)
    ai_wake_light = np.clip(0.10 + 0.55 * drowsy_frac + 0.1 * noise, 0, 1)
    ai_a_vig_reve = np.clip(ai_a_vig + 0.05 * rng.normal(size=n), 0, 1)
    ai_wake_light_reve = np.clip(ai_wake_light + 0.05 * rng.normal(size=n), 0, 1)

    # Calibration segment: first 90 samples treated as eyes-closed baseline
    cal_n = 90
    path = out_dir / "demo_session.npz"
    np.savez_compressed(
        path,
        labels=labels,
        cal_n=np.array([cal_n], dtype=np.int32),
        band_atr=atr,
        band_tar=tar,
        band_btr=btr,
        band_alpha=alpha,
        band_delta=delta_abs,  # guard feature value = absolute delta (band math)
        delta_rel=rel["delta_rel"],
        theta_rel=rel["theta_rel"],
        alpha_rel=rel["alpha_rel"],
        beta_rel=rel["beta_rel"],
        delta_abs=delta_abs,
        ai_a_vig=ai_a_vig,
        ai_wake_light=ai_wake_light,
        ai_a_vig_reve=ai_a_vig_reve,
        ai_wake_light_reve=ai_wake_light_reve,
        ai_drowsiness=ai_a_vig,  # alias
    )
    return path


FEATURE_COLUMN = {
    "band.atr": "band_atr",
    "band.tar": "band_tar",
    "band.btr": "band_btr",
    "band.alpha": "band_alpha",
    "band.delta": "band_delta",
    "ai.a_vig": "ai_a_vig",
    "ai.wake_light": "ai_wake_light",
    "ai.a_vig_reve": "ai_a_vig_reve",
    "ai.wake_light_reve": "ai_wake_light_reve",
    "ai.drowsiness": "ai_drowsiness",
}


def load_corpus(path: Path) -> dict[str, Any]:
    # allow_pickle for optional metadata (recording_id, label_names, cal_policy)
    data = np.load(path, allow_pickle=True)
    out: dict[str, Any] = {k: data[k] for k in data.files}
    cal = int(out.get("cal_n", [90])[0])
    out["cal_n"] = cal
    out["labels"] = out.get("labels")
    if "cal_starts" in out or "cal_lens" in out:
        # Fail fast on a malformed per-recording calibration block.
        build_cal_plan(out)
    return out


# --- Calibration plan (global cal_n vs per-recording cal_starts/cal_lens) -----


def corpus_length(corpus: dict[str, Any]) -> int:
    """Row count N of the 1 Hz stream (``delta_rel`` is a required column)."""
    for key in ("delta_rel", "band_atr", "band_delta", "ai_a_vig"):
        if key in corpus and corpus[key] is not None:
            return int(len(corpus[key]))
    return int(corpus["cal_n"])


def unique_in_order(values: np.ndarray) -> list[str]:
    """Unique values in first-appearance order (NOT np.unique's sorted order)."""
    seen: dict[str, None] = {}
    for v in values:
        seen.setdefault(str(v), None)
    return list(seen)


@dataclass
class CalGroup:
    """One calibration baseline and the play rows scored against it."""

    recording_id: str
    cal_idx: np.ndarray  # stream row indices of the baseline block
    play_pos: np.ndarray  # positions into CalPlan.play_idx scored vs this baseline


@dataclass
class CalPlan:
    """Which rows calibrate, which rows are scored, and against which baseline.

    ``per_recording=False`` is the legacy path: one baseline = the first
    ``cal_n`` rows, play = everything after (bit-identical to the old slices).
    """

    play_idx: np.ndarray
    groups: list[CalGroup]
    per_recording: bool
    skipped: list[str] = field(default_factory=list)

    def describe(self) -> dict[str, Any]:
        if not self.per_recording:
            g = self.groups[0]
            return {
                "mode": "global",
                "cal_n": int(g.cal_idx.size),
                "n_play": int(self.play_idx.size),
            }
        return {
            "mode": "per_recording",
            "n_recordings": len(self.groups),
            "cal_rows": int(sum(g.cal_idx.size for g in self.groups)),
            "n_play": int(self.play_idx.size),
            "skipped": list(self.skipped),
        }


def build_cal_plan(corpus: dict[str, Any]) -> CalPlan:
    """Resolve the calibration plan for a corpus.

    Per-recording mode needs ``cal_starts`` + ``cal_lens`` (int, shape ``(R,)``)
    and ``recording_id`` (N,). Entry ``r`` belongs to the r-th unique
    ``recording_id`` in first-appearance order (== builder ``recordings_used``).
    ``cal_starts`` are **absolute stream row indices**; the block
    ``[start, start+len)`` must lie inside that recording's rows. Cal rows are
    never scored. A recording with ``cal_len == 0`` has no baseline and is
    skipped (none of its rows are scored).
    """
    n = corpus_length(corpus)
    has_starts = corpus.get("cal_starts") is not None
    has_lens = corpus.get("cal_lens") is not None
    if not has_starts and not has_lens:
        cal_n = int(corpus["cal_n"])
        play_idx = np.arange(cal_n, n)
        return CalPlan(
            play_idx=play_idx,
            groups=[
                CalGroup(
                    recording_id="*",
                    cal_idx=np.arange(0, min(cal_n, n)),
                    play_pos=np.arange(play_idx.size),
                )
            ],
            per_recording=False,
        )

    if has_starts != has_lens:
        raise ValueError("cal_starts and cal_lens must be provided together")
    if corpus.get("recording_id") is None:
        raise ValueError("cal_starts/cal_lens require a recording_id column")
    rec = np.asarray(corpus["recording_id"]).astype(str)
    if rec.shape != (n,):
        raise ValueError(f"recording_id shape {rec.shape} != ({n},)")
    starts = np.asarray(corpus["cal_starts"]).astype(np.int64).reshape(-1)
    lens = np.asarray(corpus["cal_lens"]).astype(np.int64).reshape(-1)
    rec_ids = unique_in_order(rec)
    if starts.shape != (len(rec_ids),) or lens.shape != (len(rec_ids),):
        raise ValueError(
            f"cal_starts/cal_lens must have shape ({len(rec_ids)},) "
            f"(one per unique recording_id); got {starts.shape} / {lens.shape}"
        )

    is_cal = np.zeros(n, dtype=bool)
    skipped_rows = np.zeros(n, dtype=bool)
    cal_blocks: list[tuple[str, np.ndarray, np.ndarray]] = []
    skipped: list[str] = []
    for rid, s, ln in zip(rec_ids, starts, lens):
        rows = np.flatnonzero(rec == rid)
        if ln < 0:
            raise ValueError(f"{rid}: negative cal_len {ln}")
        if ln == 0:
            skipped.append(f"{rid}:no_cal_block")
            skipped_rows[rows] = True
            continue
        cal_idx = np.arange(s, s + ln)
        if s < 0 or s + ln > n or not np.all(rec[cal_idx] == rid):
            raise ValueError(
                f"{rid}: cal block [{s}, {s + ln}) is not inside that recording's rows"
            )
        is_cal[cal_idx] = True
        cal_blocks.append((rid, cal_idx, rows))

    play_mask = ~is_cal & ~skipped_rows
    play_idx = np.flatnonzero(play_mask)
    # map stream row -> position in play_idx
    pos_of_row = np.full(n, -1, dtype=np.int64)
    pos_of_row[play_idx] = np.arange(play_idx.size)
    groups: list[CalGroup] = []
    for rid, cal_idx, rows in cal_blocks:
        play_rows = rows[play_mask[rows]]
        groups.append(CalGroup(recording_id=rid, cal_idx=cal_idx, play_pos=pos_of_row[play_rows]))
    return CalPlan(play_idx=play_idx, groups=groups, per_recording=True, skipped=skipped)


def play_thresholds(
    series: np.ndarray,
    plan: CalPlan,
    percentile: float,
    *,
    finite_play: np.ndarray | None = None,
) -> tuple[np.ndarray, list[float]]:
    """Per-play-row percentile threshold from each row's own baseline.

    Returns ``(thr_rows, per_group_thresholds)`` where ``thr_rows`` is aligned
    with ``plan.play_idx`` (masked by ``finite_play`` when given). NaN baseline
    samples are dropped; a baseline with no finite samples falls back to that
    group's finite play values (same fallback as the legacy global path).
    """
    s = np.asarray(series, dtype=float)
    play_vals = s[plan.play_idx]
    fin = np.isfinite(play_vals) if finite_play is None else np.asarray(finite_play, dtype=bool)
    thr_rows = np.full(play_vals.size, np.nan)
    per_group: list[float] = []
    for g in plan.groups:
        base = s[g.cal_idx]
        base = base[np.isfinite(base)]
        if base.size == 0:
            gp = g.play_pos[fin[g.play_pos]]
            base = play_vals[gp]
        if base.size == 0:
            per_group.append(float("nan"))
            continue
        t = threshold_at_percentile(base, percentile)
        thr_rows[g.play_pos] = t
        per_group.append(t)
    return thr_rows[fin], per_group


def summarize_threshold(plan: CalPlan, per_group: list[float]) -> float:
    """Single number for reports: the global threshold, or the per-recording median."""
    if not plan.per_recording:
        return per_group[0]
    vals = [t for t in per_group if np.isfinite(t)]
    return float(np.median(vals)) if vals else float("nan")


def feature_series(corpus: dict[str, Any], feature_id: str) -> np.ndarray | None:
    col = FEATURE_COLUMN.get(feature_id)
    if col is None or col not in corpus:
        return None
    return np.asarray(corpus[col], dtype=float)


def latency_for(feature_id: str, features_meta: dict[str, Any]) -> str:
    src = features_meta.get(feature_id, {}).get("source", "")
    if src == "band":
        return "~1s"
    if src == "ai":
        if "reve" in feature_id:
            return "~4s window / 1 Hz tick"
        return "~2s window / 1 Hz tick"
    if src == "device":
        return "device-native"
    return "unknown"


def orphan_features(
    protocols: dict[str, Any], features: dict[str, Any]
) -> set[str]:
    used: set[str] = set()
    for p in protocols.values():
        if p.get("reward"):
            used.add(p["reward"]["feature"])
        if p.get("guard"):
            used.add(p["guard"]["feature"])
    return set(features.keys()) - used


def round4(x: float | None) -> float | None:
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return None
    return round(float(x), 4)
