"""Standalone feature scoring + percentile sweeps."""

from __future__ import annotations

from typing import Any

import numpy as np

from runners.helpers import (
    feature_series,
    flip_stability,
    guard_feature_score,
    hit_rate,
    label_align,
    latency_for,
    percentile_warn_parts,
    roc_auc,
    round4,
    threshold_at_percentile,
    uptrain_in_target,
    warn_rate,
)


def _play_slice(corpus: dict[str, Any]) -> tuple[slice, slice]:
    cal_n = int(corpus["cal_n"])
    # infer length from any 1d band array
    for key in ("band_atr", "band_delta", "ai_a_vig"):
        if key in corpus:
            n = len(corpus[key])
            break
    else:
        n = cal_n
    return slice(0, cal_n), slice(cal_n, n)


def score_feature(
    feature_id: str,
    feature_meta: dict[str, Any],
    corpus: dict[str, Any] | None,
    grids: dict[str, Any],
    *,
    is_orphan: bool,
    roles_in_protocols: list[str],
) -> dict[str, Any]:
    source = feature_meta.get("source", "")
    usable = feature_meta.get("usableFor", [])
    latency = latency_for(feature_id, {feature_id: feature_meta})

    base: dict[str, Any] = {
        "id": feature_id,
        "label": feature_meta.get("label", feature_id),
        "source": source,
        "usableFor": usable,
        "orphan": is_orphan,
        "roles_in_protocols": roles_in_protocols,
        "latency": latency,
        "status": "ok",
        "best_p": None,
        "score": None,
        "sep": None,
        "sweep": [],
        "notes": [],
    }

    if source == "device":
        base["status"] = "n/a"
        base["notes"].append("Crown device.* — no Muse EEG corpus; N/A")
        return base

    if corpus is None:
        base["status"] = "n/a"
        base["notes"].append("no corpus")
        return base

    series = feature_series(corpus, feature_id)
    if series is None:
        base["status"] = "needs_pack" if source == "ai" else "unavailable"
        base["notes"].append(
            "AI pack inference unavailable — add precomputed column to corpus"
            if source == "ai"
            else "feature column missing"
        )
        return base

    cal, play = _play_slice(corpus)
    play_vals = np.asarray(series[play], dtype=float)
    baseline = np.asarray(series[cal], dtype=float)
    labels = corpus.get("labels")
    labels_play = None if labels is None else np.asarray(labels)[play]

    # REVE subsample columns may be NaN outside reconstructed indices
    finite_play = np.isfinite(play_vals)
    finite_cal = np.isfinite(baseline)
    if not finite_play.any():
        base["status"] = "needs_pack" if source == "ai" else "unavailable"
        base["notes"].append("feature column all-NaN (e.g. REVE subsample miss)")
        return base
    play_vals_f = play_vals[finite_play]
    baseline_f = baseline[finite_cal] if finite_cal.any() else play_vals_f
    labels_play_f = None if labels_play is None else np.asarray(labels_play)[finite_play]
    sep = roc_auc(play_vals_f, labels_play_f)
    base["sep"] = round4(sep)
    if not bool(np.all(finite_play)):
        base["notes"].append(
            f"NaN-masked scoring: {int(finite_play.sum())}/{int(finite_play.size)} play samples"
        )

    # Primary role for sweep: prefer first usableFor
    role = usable[0] if usable else "reward"
    if "reward" in usable and "guard" not in usable:
        role = "reward"
    elif "guard" in usable and "reward" not in usable:
        role = "guard"
    elif "guard" in usable and feature_id.startswith(("ai.", "band.delta")):
        role = "guard"

    if role == "reward":
        percentiles = list(grids.get("reward_percentiles", list(range(50, 100, 5))))
        primary_key = "hit_rate"
    else:
        percentiles = list(grids.get("guard_percentiles", list(range(50, 100, 5))))
        primary_key = "label_align" if labels_play is not None else "warn_rate"

    prune_cfg = grids.get("prune", {})
    prune_on = bool(prune_cfg.get("enabled", True))
    patience = int(prune_cfg.get("patience", 2))
    delta_ceiling = float(grids.get("defaults", {}).get("guardrail_delta_ceiling", 0.25))
    gw = grids.get("protocol_rollup", {}).get("guard", {})
    sep_w = float(gw.get("sep_weight", 0.6))
    la_w = float(gw.get("label_align_weight", 0.4))
    delta_abs_full = np.asarray(
        corpus.get("delta_abs", corpus.get("band_delta", series)), dtype=float
    )[play]
    delta_abs = delta_abs_full[finite_play]

    sweep_rows: list[dict[str, Any]] = []
    best_p = None
    best_primary = None
    best_la_feature = None
    best_warn_combined = None
    worse_streak = 0
    prev_primary = None

    for p in percentiles:
        thr = threshold_at_percentile(baseline_f, p)
        if role == "reward":
            decisions = uptrain_in_target(play_vals_f, thr)
            hr = hit_rate(decisions)
            stab = flip_stability(decisions)
            primary = hr
            row = {
                "p": p,
                "threshold": round4(thr),
                "hit_rate": round4(hr),
                "stability": round4(stab),
                "primary": round4(primary),
            }
        else:
            band_math = feature_id.startswith("band.")
            warn_feature, warn_rail, warn = percentile_warn_parts(
                band_math=band_math,
                feature_values=play_vals_f,
                delta_abs=delta_abs,
                threshold=thr,
                delta_ceiling=delta_ceiling,
            )
            wr = warn_rate(warn)
            wr_feat = warn_rate(warn_feature)
            wr_rail = warn_rate(warn_rail)
            stab = flip_stability(warn_feature)
            # Score / best_p use warn_feature (not combined rail) when labels exist
            la = label_align(warn_feature, labels_play_f)
            la_combined = label_align(warn, labels_play_f)
            if la is not None:
                primary = la
            else:
                # Softened warn_rate health as primary for best_p without labels
                primary = 1.0 - min(
                    1.0, abs(wr_feat - float(gw.get("target_warn_rate", 0.15))) / 0.25
                )
            row = {
                "p": p,
                "threshold": round4(thr),
                "warn_rate": round4(wr),
                "warn_feature_rate": round4(wr_feat),
                "rail_rate": round4(wr_rail),
                "stability": round4(stab),
                "label_align": round4(la) if la is not None else None,
                "label_align_combined": round4(la_combined)
                if la_combined is not None
                else None,
                "primary": round4(float(primary)),
            }

        sweep_rows.append(row)

        if best_primary is None or float(primary) > best_primary:
            best_primary = float(primary)
            best_p = p
            worse_streak = 0
            if role != "reward":
                best_la_feature = row.get("label_align")
                best_warn_combined = row.get("warn_rate")
        else:
            if prev_primary is not None and float(primary) < prev_primary:
                worse_streak += 1
            else:
                worse_streak = 0
        prev_primary = float(primary)

        if prune_on and worse_streak >= patience and p >= 70:
            # mark pruned tail conceptually; stop extending
            break

    base["sweep"] = sweep_rows
    base["best_p"] = best_p
    if role == "reward":
        base["score"] = round4(best_primary)
    else:
        base["score"] = round4(
            guard_feature_score(
                sep=sep,
                label_align_feature=best_la_feature,
                warn_rate_combined=best_warn_combined,
                sep_weight=sep_w,
                label_align_weight=la_w,
                warn_health_target=float(gw.get("target_warn_rate", 0.15)),
                warn_health_low=float(gw.get("warn_rate_low", 0.01)),
                warn_health_high=float(gw.get("warn_rate_high", 0.55)),
            )
        )
        base["best_label_align"] = round4(best_la_feature) if best_la_feature is not None else None
    base["sweep_role"] = role
    base["primary_metric"] = primary_key
    spark = [r["primary"] for r in sweep_rows if r.get("primary") is not None]
    base["sparkline"] = spark
    return base
