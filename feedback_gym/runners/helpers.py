"""Shared helpers: catalog load, percentile semantics, metrics, corpus I/O."""

from __future__ import annotations

import json
import math
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


def percentile_warn_over(
    *,
    band_math: bool,
    feature_values: np.ndarray,
    delta_abs: np.ndarray,
    threshold: float,
    delta_ceiling: float = 0.25,
) -> np.ndarray:
    """Mirrors guard_lane.percentileWarnOver."""
    feat = np.asarray(feature_values, dtype=float)
    delta = np.asarray(delta_abs, dtype=float)
    if band_math:
        return (feat > threshold) | (feat > delta_ceiling) | (delta > delta_ceiling)
    return (feat > threshold) | (delta > delta_ceiling)


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


def warn_rate_health(
    rate: float, *, target: float = 0.15, low: float = 0.02, high: float = 0.40
) -> float:
    if math.isnan(rate):
        return 0.0
    if rate < low or rate > high:
        return 0.0
    # Triangular peak at target within [low, high]
    if rate <= target:
        return float((rate - low) / (target - low)) if target > low else 1.0
    return float((high - rate) / (high - target)) if high > target else 1.0


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
    return out


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
