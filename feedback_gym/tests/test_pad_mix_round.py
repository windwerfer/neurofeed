"""pad_mix_round: pooling variants, NaN = no warn, EO-matched blinks, stability, end-to-end."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

GYM = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(GYM))

from runners import pad_mix_round as pm  # noqa: E402
from runners.sleep_edf_heog import lowfreq_power  # noqa: E402

RNG = np.random.default_rng(3)
TASKS = ("EB", "BT", "MVO", "MVC")


def _bands_row(n: int, scale: float = 1.0) -> np.ndarray:
    base = np.array([20.0, 8.0, 10.0, 5.0, 1.0])
    return scale * base * np.exp(0.1 * RNG.standard_normal((n, 5)))


def synthetic_lee(n_sub: int = 6, artifact_gain: float = 6.0) -> dict:
    """Lee-like artifacts corpus with pad-mix columns.

    Artifacts add slow power to AF7/AF8/TP9/TP10 and (by construction) NOT to
    the TP9 - TP10 bipolar, so tpbip must look robust and af must not.
    """
    cols: dict[str, list] = {}
    rid, seg, lab = [], [], []
    cal_starts, cal_lens = [], []
    n = 0

    def put(k, v):
        cols.setdefault(k, []).append(v)

    for s in range(n_sub):
        for task in TASKS:
            r = f"lee2026/sub-{s:02d}/{task}"
            parts = (("pre_rest", 0, 50), ("task", 1, 40), ("post_rest", 0, 40))
            cal_starts.append(n)
            cal_lens.append(30)
            for phase, y, m in parts:
                gain = np.ones(5)
                if y == 1:
                    gain[:2] = artifact_gain
                for c in pm.CH:
                    b = _bands_row(m) * gain
                    for i, band in enumerate(pm.BANDS):
                        put(f"ch_{c}_{band}", b[:, i])
                    put(f"ch_{c}_std", np.full(m, 10.0 if y == 0 else 60.0))
                    put(f"ch_{c}_q", np.full(m, 95.0 if y == 0 else 30.0))
                for pre in ("bip", "tpbip"):
                    b = _bands_row(m) * (gain if pre == "bip" else 1.0)
                    for i, band in enumerate(pm.BANDS):
                        put(f"{pre}_{band}", b[:, i])
                for pre in ("tphp", "eogcal", "eogrun", "car"):
                    for t in ("tp9", "tp10"):
                        b = _bands_row(m) * gain
                        for i, band in enumerate(pm.BANDS):
                            put(f"{pre}_{t}_{band}", b[:, i])
                for k in ("sem_2s", "sem_8s", "sem_fast_8s", "veog_2s", "veog_8s"):
                    put(k, np.exp(RNG.standard_normal(m)) * (5.0 if (y and k.startswith("veog")) else 1.0))
                rid += [r] * m
                seg += [f"{task}/{phase}/x"] * m
                lab += [y] * m
                n += m
    out = {k: np.concatenate(v) for k, v in cols.items()}
    out.update(
        labels=np.asarray(lab, dtype=np.int32),
        recording_id=np.asarray(rid, dtype=object),
        segment=np.asarray(seg, dtype=object),
        cal_starts=np.asarray(cal_starts, dtype=np.int32),
        cal_lens=np.asarray(cal_lens, dtype=np.int32),
        cal_n=np.array([30], dtype=np.int32),
        delta_rel=np.full(n, 0.4), theta_rel=np.full(n, 0.2), alpha_rel=np.full(n, 0.2), beta_rel=np.full(n, 0.1),
    )
    return out


def test_af_variant_matches_app_aggregation():
    c = synthetic_lee(n_sub=1)
    f = pm.variant_features(c, "af")
    rel = {k: np.stack([c[f"ch_{k}_{b}"] for b in pm.BANDS], -1) for k in ("af7", "af8")}
    rel = {k: v / v.sum(-1, keepdims=True) for k, v in rel.items()}
    th = 0.5 * (rel["af7"][:, 1] + rel["af8"][:, 1])
    al = 0.5 * (rel["af7"][:, 2] + rel["af8"][:, 2])
    np.testing.assert_allclose(f["tar"], th / al)
    np.testing.assert_allclose(f["delta"], 0.5 * (c["ch_af7_delta"] + c["ch_af8_delta"]))


def test_pooling_rules():
    x = np.array([[1.0, 2.0], [1.2, 2.0], [100.0, 2.0], [1.1, np.nan]])[:, :, None]  # 4 pads, 2 rows
    assert pm._pool(x, "median")[0, 0] == pytest.approx(1.15)
    w = np.array([[1.0, 0.0], [1.0, 0.0], [0.0, 0.0], [1.0, 0.0]])
    out = pm._pool(x, "weighted", w)
    assert out[0, 0] == pytest.approx((1.0 + 1.2 + 1.1) / 3)
    assert np.isnan(out[1, 0])  # no usable pad -> undefined (app skips the sample)


def test_split_takes_theta_from_tp_and_alpha_from_all4():
    c = synthetic_lee(n_sub=1)
    f = pm.variant_features(c, "split")
    tp = pm.variant_features(c, "tp")
    np.testing.assert_allclose(f["rel_theta"], tp["rel_theta"])
    np.testing.assert_allclose(f["delta"], tp["delta"])
    assert not np.allclose(f["tar"], tp["tar"])


def test_undefined_window_never_warns():
    c = synthetic_lee(n_sub=1)
    s = np.asarray(c["ch_af7_delta"], dtype=float).copy()
    s[c["labels"] == 1] = np.nan
    recs = pm.per_recording(s, c)
    assert all(r["warn1"] == 0.0 for r in recs)
    assert all(r["auc"] is None for r in recs)


def test_artifacts_hit_af_not_tpbip_and_eo_matched_blink():
    c = synthetic_lee()
    af = pm.artifact_metrics(pm.variant_features(c, "af")["delta"], c)
    tb = pm.artifact_metrics(pm.variant_features(c, "tpbip")["delta"], c)
    assert af["blink"]["auc_median"] > 0.95 and af["jaw"]["auc_median"] > 0.95
    assert 0.3 < tb["blink"]["auc_median"] < 0.7
    assert af["blink"]["warn_artifact"] > 0.8 > 0.3 > af["blink"]["warn_clean"]
    assert af["blink EO-matched"]["auc_median"] > 0.95 and af["blink EO-matched"]["n"] == 6
    # quality gate: artifact rows have q = 30 -> skipped -> never warn
    gated = pm.artifact_metrics(pm.variant_features(c, "gate4")["delta"], c)
    assert gated["blink"]["warn_artifact"] == 0.0
    assert gated["coverage_clean"] == pytest.approx(1.0)


def test_stability_rho():
    c = synthetic_lee()
    s = np.repeat(np.arange(len(c["cal_starts"]), dtype=float) + 1.0, np.diff(np.r_[c["cal_starts"], len(c["labels"])]))
    st = pm.stability_metrics(s, c)
    assert st["retest_rho"] == pytest.approx(1.0)
    assert st["within_cv"] == pytest.approx(0.0)
    noise = RNG.standard_normal(len(c["labels"]))
    assert abs(pm.stability_metrics(noise, c)["retest_rho"]) < 0.6


def test_main_writes_tables(tmp_path):
    c = synthetic_lee(n_sub=3)
    p = tmp_path / "art.npz"
    np.savez(p, **c)
    out = tmp_path / "out"
    assert pm.main(["--lee-artifacts", str(p), "--lee-eo-ec", str(tmp_path / "none.npz"),
                    "--universe", str(tmp_path / "none.npz"), "--out-dir", str(out)]) == 0
    md = (out / "padmix_tables.md").read_text()
    assert "tpbip · abs delta" in md and "sem_ratio_8s (↑)" in md and "sem_fast_8s (↓)" in md
    assert (out / "padmix_board.json").exists()


def test_main_needs_pad_mix_columns(tmp_path):
    p = tmp_path / "old.npz"
    np.savez(p, labels=np.zeros(5, dtype=np.int32), delta_rel=np.zeros(5), cal_n=np.array([1], dtype=np.int32))
    assert pm.main(["--lee-artifacts", str(p), "--lee-eo-ec", str(p), "--universe", str(p), "--out-dir", str(tmp_path)]) == 2


def test_heog_lowfreq_power_bands():
    sr = 100.0
    t = np.arange(int(60 * sr)) / sr
    slow = 50 * np.sin(2 * np.pi * 0.5 * t)
    fast = 50 * np.sin(2 * np.pi * 3.0 * t)
    ends = np.array([10.0, 30.0, 59.0])
    p_slow = lowfreq_power(slow, sr, ends, 8.0, 0.25, 1.0)
    p_fast_in_slow = lowfreq_power(fast, sr, ends, 8.0, 0.25, 1.0)
    p_fast = lowfreq_power(fast, sr, ends, 8.0, 1.0, 5.0)
    assert np.all(p_slow > 100 * p_fast_in_slow)
    np.testing.assert_allclose(p_fast, 50**2 / 2, rtol=0.1)  # sine power A^2/2
    assert np.isnan(lowfreq_power(slow, sr, np.array([4.0]), 8.0, 0.25, 1.0))[0]
