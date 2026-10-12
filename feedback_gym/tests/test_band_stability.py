"""Experimental bandStability: gym mirror of the app RatioEngine stability mode."""

from __future__ import annotations

import numpy as np
import pytest

from runners.helpers import (
    CalGroup,
    CalPlan,
    coefficient_of_variation,
    generate_synthetic_corpus,
    load_catalog,
    load_corpus,
    load_grids,
    rolling_cvs,
    stability_in_target,
    stability_ratio_rows,
)
from runners.simulate_protocol import simulate_protocol


def test_cv_matches_app_definition():
    # population SD / |mean| (app coefficientOfVariation)
    assert coefficient_of_variation(np.array([1.0, 3.0])) == pytest.approx(0.5)
    assert np.isnan(coefficient_of_variation(np.array([1.0])))
    assert np.isnan(coefficient_of_variation(np.array([1.0, -1.0])))


def test_rolling_cvs_full_windows_and_short_fallback():
    v = np.array([1.0, 3.0, 1.0, 3.0])
    assert rolling_cvs(v, 2).tolist() == pytest.approx([0.5, 0.5, 0.5])
    # fewer values than the window: one CV over all of them
    assert rolling_cvs(np.array([1.0, 3.0]), 10).tolist() == pytest.approx([0.5])
    # window 1 is computed over 2 samples (a CV needs >= 2)
    assert rolling_cvs(v, 1).size == 3


def _plan(n_cal: int, n: int) -> CalPlan:
    play = np.arange(n_cal, n)
    return CalPlan(
        play_idx=play,
        groups=[CalGroup("*", np.arange(n_cal), np.arange(play.size))],
        per_recording=False,
    )


def test_steadier_play_is_in_target_noisier_is_not():
    rng = np.random.default_rng(0)
    cal = 0.3 + 0.06 * rng.standard_normal(60)  # baseline fluctuation
    steady = 0.3 + 0.02 * rng.standard_normal(60)
    noisy = 0.3 + 0.12 * rng.standard_normal(60)
    series = np.concatenate([cal, steady, noisy])
    plan = _plan(60, series.size)
    r, base = stability_ratio_rows(series, plan, 10)
    assert base[0] == pytest.approx(np.median(rolling_cvs(cal, 10)), rel=0.05)
    # warm-up: first 9 play rows undecided
    assert np.isnan(r[:9]).all() and np.isfinite(r[9])
    hit = stability_in_target(r, 0.10)
    assert hit[15:60].mean() > 0.9
    assert hit[75:].mean() < 0.1
    # NaN never counts as in target
    assert not hit[:9].any()


def test_catalog_band_stability_simulates(tmp_path):
    protocols, features = load_catalog()
    proto = protocols["bandStability"]
    assert proto["reward"]["policy"] == "stabilityDowntrain"
    assert proto["reward"]["feature"] == "band.alpha"
    assert proto["guard"]["feature"] == "ai.a_vig"
    assert "deltaRail" not in proto["guard"]
    for fid in ("band.theta", "band.beta"):
        assert "reward" in features[fid]["usableFor"]
    corpus = load_corpus(generate_synthetic_corpus(tmp_path, n=500, seed=4))
    grids = load_grids()
    res = simulate_protocol(proto, corpus, grids)
    rw = res["parts"]["reward"]
    assert rw["policy"] == "stabilityDowntrain"
    assert rw["window_seconds"] == 10 and rw["threshold"] == 0.9
    assert rw["n_decided"] > 0 and 0.0 <= rw["hit_rate"] <= 1.0
    assert res["final"] is not None
    # band choice + settings are mirrored
    res_b = simulate_protocol(
        proto,
        corpus,
        grids,
        stability_band="band.beta",
        stability_window=5,
        stability_difficulty=0.3,
    )
    rb = res_b["parts"]["reward"]
    assert rb["feature"] == "band.beta"
    assert rb["window_seconds"] == 5 and rb["threshold"] == 0.7
    # harder target → fewer rewarded seconds (same band)
    hard = simulate_protocol(proto, corpus, grids, stability_difficulty=0.5)
    assert hard["parts"]["reward"]["hit_rate"] <= rw["hit_rate"]
