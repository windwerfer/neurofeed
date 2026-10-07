"""Simulate a catalog protocol: reward + inhibit AND-gate + guard."""

from __future__ import annotations

from typing import Any

import numpy as np

from runners.helpers import (
    build_cal_plan,
    feature_series,
    hit_rate,
    inhibit_block_rate,
    inhibit_health,
    inhibit_passes,
    label_align,
    percentile_warn_parts,
    protocol_composite,
    round4,
    flip_stability,
    play_thresholds,
    summarize_threshold,
    uptrain_in_target,
    warn_rate,
    warn_rate_health,
)


def simulate_protocol(
    protocol: dict[str, Any],
    corpus: dict[str, Any],
    grids: dict[str, Any],
    *,
    reward_percentile: float | None = None,
    guard_percentile: float | None = None,
) -> dict[str, Any]:
    defaults = grids.get("defaults", {})
    rollup = grids.get("protocol_rollup", {})
    rw = rollup.get("reward", {})
    gw = rollup.get("guard", {})
    iw = rollup.get("inhibit", {})

    r_p = float(
        reward_percentile
        if reward_percentile is not None
        else defaults.get("reward_percentile", 40)
    )
    g_p = float(
        guard_percentile
        if guard_percentile is not None
        else defaults.get("guard_percentile", 75)
    )
    delta_ceiling = float(defaults.get("guardrail_delta_ceiling", 0.25))

    plan = build_cal_plan(corpus)
    play = plan.play_idx
    labels_full = corpus.get("labels")
    labels = None if labels_full is None else np.asarray(labels_full)[play]

    result: dict[str, Any] = {
        "id": protocol["id"],
        "reward_percentile": r_p,
        "guard_percentile": g_p,
        "parts": {},
        "notes": [],
    }
    if plan.per_recording:
        result["calibration"] = plan.describe()

    reward_score = None
    guard_score = None
    inhibit_score = None

    # --- Reward + inhibit ----------------------------------------------------
    reward_cfg = protocol.get("reward")
    if reward_cfg is None:
        result["parts"]["reward"] = None
        result["notes"].append("no reward lane")
    else:
        feat_id = reward_cfg["feature"]
        series = feature_series(corpus, feat_id)
        if series is None:
            result["parts"]["reward"] = {"status": "unavailable", "feature": feat_id}
            result["notes"].append(f"reward feature {feat_id} missing from corpus")
        else:
            play_vals = series[play]
            # all play rows are decided (NaN > thr is False), as before
            thr_rows, thr_groups = play_thresholds(
                series, plan, r_p, finite_play=np.ones(play_vals.size, dtype=bool)
            )
            thr = summarize_threshold(plan, thr_groups)
            above = uptrain_in_target(play_vals, thr_rows)

            delta_rel = np.asarray(corpus["delta_rel"])[play]
            theta_rel = np.asarray(corpus["theta_rel"])[play]
            alpha_rel = np.asarray(corpus["alpha_rel"])[play]
            beta_rel = np.asarray(corpus["beta_rel"])[play]

            inhibit = reward_cfg.get("inhibit") or []
            all_pass, fails = inhibit_passes(
                inhibit, delta_rel, theta_rel, alpha_rel, beta_rel
            )
            in_target = above & all_pass
            hr = hit_rate(in_target)
            stab = flip_stability(in_target)

            inhibit_parts = []
            block_rates = []
            for cond in inhibit:
                tag = "beta" if cond["type"] == "betaCeiling" else "delta"
                br = inhibit_block_rate(above, fails.get(tag, np.zeros_like(above)))
                h = inhibit_health(br, float(iw.get("target_block", 0.25)))
                inhibit_parts.append(
                    {
                        "type": cond["type"],
                        "max": cond.get("max"),
                        "inhibit_block": round4(br),
                        "health": round4(h),
                    }
                )
                block_rates.append(br)

            if inhibit:
                inhibit_score = float(np.mean([inhibit_health(b, float(iw.get("target_block", 0.25))) for b in block_rates]))
            else:
                inhibit_score = 1.0

            reward_score = float(
                float(rw.get("hit_rate", 0.7)) * hr
                + float(rw.get("stability", 0.3)) * stab
            )
            result["parts"]["reward"] = {
                "feature": feat_id,
                "policy": reward_cfg.get("policy", "percentileUptrain"),
                "threshold": round4(thr),
                "hit_rate": round4(hr),
                "stability": round4(stab),
                "score": round4(reward_score),
                "n_play": int(play_vals.size),
            }
            if plan.per_recording:
                result["parts"]["reward"]["thresholds_per_recording"] = {
                    g.recording_id: round4(t) for g, t in zip(plan.groups, thr_groups)
                }
            result["parts"]["inhibit"] = {
                "items": inhibit_parts,
                "score": round4(inhibit_score),
            }

    if reward_cfg is None:
        result["parts"]["inhibit"] = None
        inhibit_score = None

    # --- Guard ---------------------------------------------------------------
    guard_cfg = protocol.get("guard")
    if guard_cfg is None:
        result["parts"]["guard"] = None
        result["notes"].append("no guard lane")
    else:
        feat_id = guard_cfg["feature"]
        series = feature_series(corpus, feat_id)
        if series is None:
            result["parts"]["guard"] = {"status": "unavailable", "feature": feat_id}
            result["notes"].append(f"guard feature {feat_id} missing from corpus")
        else:
            band_math = feat_id.startswith("band.")
            play_vals = np.asarray(series[play], dtype=float)
            finite = np.isfinite(play_vals)
            if not finite.any():
                result["parts"]["guard"] = {
                    "status": "unavailable",
                    "feature": feat_id,
                    "notes": "all-NaN feature column",
                }
                result["notes"].append(f"guard feature {feat_id} all-NaN")
            else:
                play_f = play_vals[finite]
                labels_f = None if labels is None else np.asarray(labels)[finite]
                thr_rows, thr_groups = play_thresholds(
                    series, plan, g_p, finite_play=finite
                )
                thr = summarize_threshold(plan, thr_groups)
                delta_abs = np.asarray(
                    corpus.get("delta_abs", corpus["band_delta"]), dtype=float
                )[play][finite]
                warn_feature, warn_rail, warn = percentile_warn_parts(
                    band_math=band_math,
                    feature_values=play_f,
                    delta_abs=delta_abs,
                    threshold=thr_rows,
                    delta_ceiling=delta_ceiling,
                )
                wr = warn_rate(warn)
                wr_feat = warn_rate(warn_feature)
                wr_rail = warn_rate(warn_rail)
                stab = flip_stability(warn_feature)
                la = label_align(warn_feature, labels_f)
                la_combined = label_align(warn, labels_f)
                if la is not None:
                    guard_score = la
                else:
                    guard_score = warn_rate_health(
                        wr_feat,
                        target=float(gw.get("target_warn_rate", 0.15)),
                        low=float(gw.get("warn_rate_low", 0.01)),
                        high=float(gw.get("warn_rate_high", 0.55)),
                    )
                result["parts"]["guard"] = {
                    "feature": feat_id,
                    "policy": guard_cfg.get("policy", "percentileWarn"),
                    "band_math": band_math,
                    "threshold": round4(thr),
                    "warn_rate": round4(wr),
                    "warn_feature_rate": round4(wr_feat),
                    "rail_rate": round4(wr_rail),
                    "stability": round4(stab),
                    "label_align": round4(la) if la is not None else None,
                    "label_align_combined": round4(la_combined)
                    if la_combined is not None
                    else None,
                    "score": round4(guard_score),
                }
                if plan.per_recording:
                    result["parts"]["guard"]["thresholds_per_recording"] = {
                        g.recording_id: round4(t) for g, t in zip(plan.groups, thr_groups)
                    }

    final = protocol_composite(
        reward_score=reward_score,
        guard_score=guard_score,
        inhibit_score=inhibit_score if reward_cfg else None,
        weights=rollup,
    )
    # recordOnly / empty: composite None → 0 display with note
    result["final"] = round4(final) if final is not None else None
    if protocol["id"] == "recordOnly":
        result["notes"].append("recordOnly — no lanes; composite N/A")
    return result
