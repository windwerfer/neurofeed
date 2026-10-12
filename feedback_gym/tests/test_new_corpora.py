"""2026-10-12 corpora: manifest presets + label_valid row dropping in load_corpus."""

from __future__ import annotations

import numpy as np

from runners.helpers import build_cal_plan, drop_invalid_label_rows, load_corpus
from runners.run_gym import SIBLING_PRESETS


def test_new_presets_registered():
    for p in ("boas-wake-n1", "ds001787-mw-muse", "ds001787-mw-crown", "rl2021-mw-muse", "muse-sleeponset-labonly"):
        assert p in SIBLING_PRESETS, p
    lab = SIBLING_PRESETS["muse-sleeponset-labonly"]
    assert lab.get("LAB_ONLY") and not lab["path"].startswith("corpora/")


def _corpus():
    n = 12
    rid = np.array(["a"] * 6 + ["b"] * 6, dtype=object)
    valid = np.array([0, 0, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0], dtype=bool)  # recording b: only cal rows survive
    return {
        "delta_rel": np.linspace(0, 1, n), "theta_rel": np.ones(n), "alpha_rel": np.ones(n), "beta_rel": np.ones(n),
        "labels": np.arange(n, dtype=np.int32) % 2, "recording_id": rid, "label_valid": valid,
        "cal_starts": np.array([0, 6], dtype=np.int32), "cal_lens": np.array([2, 2], dtype=np.int32), "cal_n": 2,
        "psd_x": np.ones((n, 45), np.float32),
    }


def test_drop_invalid_label_rows_keeps_cal_and_remaps():
    c = drop_invalid_label_rows(_corpus())
    assert c["rows_dropped_label_invalid"] == 5
    assert len(c["labels"]) == 7 and c["psd_x"].shape == (7, 45)
    assert c["cal_starts"].tolist() == [0, 5] and c["cal_lens"].tolist() == [2, 2]
    plan = build_cal_plan(c)
    assert plan.per_recording and plan.play_idx.tolist() == [2, 3, 4]
    assert "label_valid" not in c


def test_load_corpus_applies_label_valid(tmp_path):
    p = tmp_path / "c.npz"
    np.savez(p, **{k: v for k, v in _corpus().items() if k != "cal_n"}, cal_n=np.array([2], np.int32))
    c = load_corpus(p)
    assert len(c["labels"]) == 7


def test_gating_applies_after_no_gate_load():
    import numpy as np
    from runners.helpers import apply_app_gating
    n = 10
    c = {"delta_rel": np.ones(n), "labels": np.zeros(n), "cal_n": 2, "gating": {"applied": False},
         "ch_af7_q": np.r_[np.full(5, 100.0), np.full(5, 10.0)], "ch_af8_q": np.r_[np.full(5, 100.0), np.full(5, 10.0)]}
    g = apply_app_gating(c)
    assert g["gating"]["applied"] and g["gating"]["dropped_pad"] >= 5
