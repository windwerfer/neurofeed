"""Unit tests for core scorers on synthetic series."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

GYM = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(GYM))

from runners.helpers import (  # noqa: E402
    generate_synthetic_corpus,
    hit_rate,
    inhibit_block_rate,
    inhibit_passes,
    label_align,
    load_corpus,
    load_grids,
    percentile_warn_over,
    roc_auc,
    threshold_at_percentile,
    uptrain_in_target,
    warn_rate,
)
from runners.score_feature import score_feature  # noqa: E402
from runners.simulate_protocol import simulate_protocol  # noqa: E402


def test_threshold_at_percentile_matches_dart_index():
    baseline = np.array([0.0, 1.0, 2.0, 3.0, 4.0])
    # p50 → idx = round(0.5*4)=2 → 2.0
    assert threshold_at_percentile(baseline, 50) == 2.0
    # p0 → 0, p100 → 4
    assert threshold_at_percentile(baseline, 0) == 0.0
    assert threshold_at_percentile(baseline, 100) == 4.0
    # p75 → round(0.75*4)=3 → 3.0
    assert threshold_at_percentile(baseline, 75) == 3.0


def test_hit_rate_known():
    d = np.array([True, True, False, False])
    assert hit_rate(d) == pytest.approx(0.5)


def test_inhibit_block_and_and_gate():
    n = 10
    above = np.ones(n, dtype=bool)
    beta = np.array([0.1, 0.1, 0.4, 0.4, 0.1, 0.1, 0.4, 0.4, 0.1, 0.1])
    delta = np.full(n, 0.2)
    alpha = np.full(n, 0.3)
    theta = np.full(n, 0.2)
    inhibit = [{"type": "betaCeiling", "max": 0.25}]
    all_pass, fails = inhibit_passes(inhibit, delta, theta, alpha, beta)
    assert int(np.sum(~all_pass)) == 4
    br = inhibit_block_rate(above, fails["beta"])
    assert br == pytest.approx(0.4)


def test_warn_rate_and_label_align():
    warn = np.array([True, True, False, False, True, False])
    labels = np.array([1, 1, 0, 0, 0, 1])
    assert warn_rate(warn) == pytest.approx(0.5)
    # TP=2 (idx0,1), FN=1 (idx5), FP=1 (idx4), TN=2 (idx2,3)
    # TPR=2/3, FPR=1/3 → align = 0.5*(2/3)+0.5*(2/3)=2/3
    assert label_align(warn, labels) == pytest.approx(2 / 3)


def test_percentile_warn_band_math_uses_ceiling():
    feat = np.array([0.1, 0.3, 0.1])
    delta = np.array([0.1, 0.1, 0.1])
    # threshold 0.2; second sample over thr; ceiling 0.25 not hit by feat alone except #1
    over = percentile_warn_over(
        band_math=True,
        feature_values=feat,
        delta_abs=delta,
        threshold=0.2,
        delta_ceiling=0.25,
    )
    assert list(over) == [False, True, False]
    # absolute delta rail
    over2 = percentile_warn_over(
        band_math=True,
        feature_values=np.array([0.1]),
        delta_abs=np.array([0.3]),
        threshold=0.5,
        delta_ceiling=0.25,
    )
    assert bool(over2[0]) is True


def test_best_p_on_monotonic_reward_sweep(tmp_path):
    # Construct corpus where higher threshold → lower hit_rate → best at lowest p
    path = generate_synthetic_corpus(tmp_path, n=400, seed=7)
    corpus = load_corpus(path)
    grids = load_grids()
    meta = {
        "label": "ATR",
        "source": "band",
        "usableFor": ["reward"],
    }
    out = score_feature(
        "band.atr",
        meta,
        corpus,
        grids,
        is_orphan=False,
        roles_in_protocols=["reward@drowsiness"],
    )
    assert out["status"] == "ok"
    assert out["best_p"] is not None
    assert 50 <= out["best_p"] <= 95
    assert len(out["sweep"]) >= 3
    # hit_rate should generally not increase as p rises
    hrs = [r["hit_rate"] for r in out["sweep"]]
    assert hrs[0] >= hrs[-1] - 1e-9


def test_simulate_protocol_concentration_has_inhibit(tmp_path):
    path = generate_synthetic_corpus(tmp_path, n=500, seed=1)
    corpus = load_corpus(path)
    grids = load_grids()
    protocol = {
        "id": "concentration",
        "reward": {
            "feature": "band.alpha",
            "policy": "percentileUptrain",
            "inhibit": [{"type": "betaCeiling", "max": 0.25}],
        },
        "guard": {
            "feature": "band.delta",
            "policy": "percentileWarn",
        },
    }
    res = simulate_protocol(protocol, corpus, grids)
    assert res["final"] is not None
    assert res["parts"]["reward"]["hit_rate"] is not None
    assert res["parts"]["inhibit"]["items"]
    assert res["parts"]["inhibit"]["items"][0]["inhibit_block"] is not None
    assert res["parts"]["guard"]["warn_rate"] is not None


def test_device_feature_is_na():
    grids = load_grids()
    out = score_feature(
        "device.focus",
        {"label": "Focus", "source": "device", "usableFor": ["reward", "guard"]},
        corpus=None,
        grids=grids,
        is_orphan=True,
        roles_in_protocols=[],
    )
    assert out["status"] == "n/a"
    assert out["best_p"] is None


def test_roc_auc_perfect():
    scores = np.array([0.1, 0.2, 0.8, 0.9])
    labels = np.array([0, 0, 1, 1])
    assert roc_auc(scores, labels) == pytest.approx(1.0)


def test_uptrain_strict_greater():
    assert list(uptrain_in_target(np.array([1.0, 2.0, 3.0]), 2.0)) == [
        False,
        False,
        True,
    ]


def test_percentile_warn_parts_split():
    from runners.helpers import percentile_warn_parts

    feat = np.array([0.1, 0.3, 0.1])
    delta = np.array([0.4, 0.1, 0.1])  # first sample trips rail
    wf, wr, w = percentile_warn_parts(
        band_math=False,
        feature_values=feat,
        delta_abs=delta,
        threshold=0.2,
        delta_ceiling=0.25,
    )
    assert list(wf) == [False, True, False]
    assert list(wr) == [True, False, False]
    assert list(w) == [True, True, False]


def test_guard_score_ignores_always_on_delta_rail(tmp_path):
    """High-sep series + constant delta>ceiling still scores well via warn_feature."""
    from runners.helpers import generate_synthetic_corpus, load_corpus, load_grids
    from runners.score_feature import score_feature
    from runners.simulate_protocol import simulate_protocol

    path = generate_synthetic_corpus(tmp_path, n=400, seed=11)
    corpus = load_corpus(path)
    # Force absolute delta rail always-on (Sleep-EDF-like scale)
    n = len(corpus["ai_a_vig"])
    corpus["delta_abs"] = np.full(n, 50.0)
    grids = load_grids()
    meta = {"label": "A-vig", "source": "ai", "usableFor": ["guard"]}
    out = score_feature(
        "ai.a_vig",
        meta,
        corpus,
        grids,
        is_orphan=True,
        roles_in_protocols=[],
    )
    assert out["status"] == "ok"
    assert out["sep"] is not None and out["sep"] > 0.7
    # Combined warn would be ~always on → label_align≈0.5; feature path must beat that
    assert out["score"] is not None and out["score"] > 0.65
    assert out["best_label_align"] is not None and out["best_label_align"] > 0.55
    # Sweep still reports combined warn_rate / rail_rate
    assert out["sweep"]
    assert out["sweep"][0].get("rail_rate") == 1.0
    assert out["sweep"][0].get("warn_rate") == 1.0
    assert out["sweep"][0].get("warn_feature_rate") is not None

    # Protocol guard also prefers warn_feature label_align and reports rail
    protocol = {
        "id": "guardrailOnly",
        "guard": {"feature": "ai.a_vig", "policy": "percentileWarn"},
    }
    res = simulate_protocol(protocol, corpus, grids)
    g = res["parts"]["guard"]
    assert g["rail_rate"] == 1.0
    assert g["warn_rate"] == 1.0
    assert g["label_align"] is not None and g["label_align"] > 0.55
    assert g["score"] == g["label_align"]
