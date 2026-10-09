"""Fair band-math round: directional AUC, per-recording Sleep-EDF cal, app band port."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

GYM = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(GYM))

from runners.app_bands import app_features, band_powers  # noqa: E402
from runners.build_corpus_sleep_edf import (  # noqa: E402
    add_per_recording_cal,
    per_recording_cal,
)
from runners.fair_round import (  # noqa: E402
    FEATURE_BY_ID,
    main as fair_main,
    score_feature_fair,
)
from runners.helpers import build_cal_plan, roc_auc, roc_auc_up  # noqa: E402


def test_roc_auc_up_keeps_direction():
    y = np.array([0, 0, 0, 1, 1, 1])
    s = np.array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
    assert roc_auc_up(s, y) == pytest.approx(1.0)
    assert roc_auc_up(-s, y) == pytest.approx(0.0)
    assert roc_auc(-s, y) == pytest.approx(1.0)  # sep folds the direction away
    assert roc_auc_up(np.zeros(6), y) == pytest.approx(0.5)
    assert roc_auc_up(np.array([1.0, np.nan, 3.0, 4.0, 5.0, 6.0]), y) == pytest.approx(1.0)
    assert roc_auc_up(s, np.zeros(6, dtype=int)) is None


def test_per_recording_cal_uses_leading_wake_run():
    labels = np.array([0] * 100 + [1] * 50 + [0] * 40 + [1] * 10 + [1] * 60 + [0] * 60)
    rec = np.array(["A"] * 150 + ["B"] * 50 + ["C"] * 120)
    starts, lens, none = per_recording_cal(labels, rec, cal_n=90, min_cal_rows=30)
    assert starts.tolist() == [0, 150, 200]
    assert lens.tolist() == [90, 40, 0]  # A capped at 90; B whole wake run; C starts in N1
    assert none == ["C"]

    arrays = {"labels": labels, "recording_id": rec.astype(object), "delta_rel": np.zeros(labels.size)}
    add_per_recording_cal(arrays, cal_n=90, min_cal_rows=30)
    plan = build_cal_plan({**arrays, "cal_n": int(arrays["cal_n"][0])})
    assert plan.per_recording
    assert plan.skipped == ["C:no_cal_block"]
    # cal rows and the skipped recording are never scored
    assert not np.isin(np.arange(0, 90), plan.play_idx).any()
    assert not np.isin(np.arange(200, 320), plan.play_idx).any()
    assert plan.play_idx.size == (150 - 90) + (50 - 40)


def test_app_bands_match_rust_contract():
    t = np.arange(256) / 256.0
    for hz, band in ((2, 0), (6, 1), (10, 2), (20, 3), (37, 4)):
        p = band_powers(10.0 * np.sin(2 * np.pi * hz * t))
        assert p[band] == pytest.approx(50.0, rel=1e-6)  # A^2/2 in uV^2
    for hz in (4, 8, 13, 30):  # band edges: each bin in exactly one band
        p = band_powers(10.0 * np.sin(2 * np.pi * hz * t))
        assert p.sum() == pytest.approx(50.0, rel=1e-6)
    # gamma stops below the mains notch: 46 Hz is outside every band
    assert band_powers(10.0 * np.sin(2 * np.pi * 46 * t)).sum() < 1e-6

    rng = np.random.default_rng(0)
    X = rng.normal(size=(3, 4, 512))
    X[:, :2] += 20 * np.sin(2 * np.pi * 10 * np.arange(512) / 256.0)
    f = app_features(X)
    assert np.all(f["band.alpha"] > 0.5)
    assert np.allclose(f["band.atr"] * f["band.tar"], 1.0)


def _two_rec_corpus() -> dict:
    rng = np.random.default_rng(1)
    rows, labels, rec = [], [], []
    for r, offset in (("A", 0.0), ("B", 5.0)):  # B sits far above A (subject offset)
        y = np.array([0] * 120 + [1] * 80)
        x = offset + rng.normal(size=y.size) + 1.5 * y  # rises toward label 1
        rows.append(x)
        labels.append(y)
        rec += [r] * y.size
    x = np.concatenate(rows)
    y = np.concatenate(labels).astype(np.int32)
    rel = np.full(x.size, 0.2)
    corpus = {
        "band_tar": x,
        "labels": y,
        "recording_id": np.array(rec, dtype=object),
        "theta_rel": rel,
        "alpha_rel": rel,
        "beta_rel": rel,
        "delta_rel": rel,
    }
    starts, lens, _ = per_recording_cal(y, corpus["recording_id"], cal_n=60)
    corpus.update(cal_starts=starts, cal_lens=lens, cal_n=60)
    return corpus


def test_score_feature_fair_both_directions_per_recording():
    corpus = _two_rec_corpus()
    r = score_feature_fair(FEATURE_BY_ID["band.tar"], corpus)
    assert r["prior_sleep_dir"] == "up" and r["data_dir"] == "up"
    assert r["up"]["per_rec_n"] == 2
    assert r["up"]["per_rec_auc_median"] > 0.8
    assert r["down"]["per_rec_auc_median"] == pytest.approx(1 - r["up"]["per_rec_auc_median"])
    assert r["up"]["guard"][90]["balanced_acc"] > r["down"]["guard"][90]["balanced_acc"]
    # each recording against its own baseline: warn rate on label 0 stays near 1 - p
    assert r["up"]["guard"][90]["warn_rate_label0"] < 0.3
    # derived (theta+alpha)/beta is constant here -> chance
    tab = score_feature_fair(FEATURE_BY_ID["gym.tab"], corpus)
    assert tab["up"]["per_rec_auc_median"] == pytest.approx(0.5)


def test_fair_round_main_writes_aggregates(tmp_path):
    corpus = _two_rec_corpus()
    p = tmp_path / "c.npz"
    np.savez(p, **{k: v for k, v in corpus.items() if k != "cal_n"}, cal_n=np.array([60]))
    out = tmp_path / "out"
    missing = tmp_path / "missing.npz"
    rc = fair_main([
        "--sleep-edf", str(p), "--old-sleep-edf", str(missing), "--lee-eo-ec", str(missing),
        "--lee-artifacts", str(missing), "--universe", str(missing),
        "--catalog", str(missing), "--out-dir", str(out),
    ])
    assert rc == 0
    text = (out / "fair_tables.md").read_text()
    assert "TAR theta/alpha" in text and "per-rec AUC" in text
    assert (out / "fair_board.json").exists()
