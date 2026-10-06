"""Sibling corpora wiring: per-recording calibration, presets, multi-corpus board."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pytest

GYM = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(GYM))

from runners import run_gym  # noqa: E402
from runners.helpers import (  # noqa: E402
    build_cal_plan,
    generate_synthetic_corpus,
    load_corpus,
    load_grids,
    threshold_at_percentile,
)
from runners.score_feature import score_feature  # noqa: E402
from runners.simulate_protocol import simulate_protocol  # noqa: E402

AI_GUARD = {"id": "aiGuard", "guard": {"feature": "ai.a_vig", "policy": "percentileWarn"}}
ATR_REWARD = {
    "id": "atrReward",
    "reward": {"feature": "band.atr", "policy": "percentileUptrain", "inhibit": []},
}
BAND_COLS = ("band_atr", "band_tar", "band_btr", "band_alpha", "band_delta")


def _band_only_npz(path: Path, n: int = 300, seed: int = 3, **extra) -> Path:
    """Sibling-style NPZ (diggus schema): band/rel columns, labels, no ai_*."""
    rng = np.random.default_rng(seed)
    labels = np.array([0] * (n // 2) + [1] * (n - n // 2), dtype=np.int32)
    rel = rng.dirichlet([3, 2, 3, 2, 1], size=n).T
    arrays = {
        "delta_rel": rel[0],
        "theta_rel": rel[1],
        "alpha_rel": rel[2] + 0.05 * labels,
        "beta_rel": rel[3],
        "band_atr": rel[2] / rel[1],
        "band_tar": rel[1] / rel[2],
        "band_btr": rel[3] / rel[1],
        "band_alpha": rel[2],
        "band_delta": 0.1 + 0.05 * rng.random(n),
        "delta_abs": 0.1 + 0.05 * rng.random(n),
        "labels": labels,
        "cal_n": np.array([60], dtype=np.int32),
        "recording_id": np.array(["r0"] * n, dtype=object),
        "label_names": np.array(["eyes_open", "eyes_closed"]),
        "cal_policy": np.array("test: first 60 rows"),
        "corpus_id": np.array("lee2026_muse2_eo_ec"),
        "recordings_used": np.array(["r0"], dtype=object),
        "recordings_skipped": np.array([], dtype=object),
    }
    arrays.update(extra)
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(path, **arrays)
    return path


def _two_baseline_corpus(path: Path, *, with_cal_starts: bool = True) -> Path:
    """Two recordings whose baselines differ by ~10x.

    Each recording: 20 cal rows (label 0) then 40 play rows (20 label 0, 20 label 1).
    Rec 'zeta' (first in stream, so np.unique order would differ) lives around 1,
    rec 'alpha' around 10. Only per-recording thresholds separate both.
    """
    cal_a = np.linspace(0.0, 1.0, 20)
    play_a = np.r_[np.full(20, 0.5), np.full(20, 2.0)]
    cal_b = np.linspace(10.0, 11.0, 20)
    play_b = np.r_[np.full(20, 10.5), np.full(20, 12.0)]
    vals = np.r_[cal_a, play_a, cal_b, play_b]
    lab_rec = np.r_[np.zeros(20), np.zeros(20), np.ones(20)].astype(np.int32)
    labels = np.r_[lab_rec, lab_rec]
    n = vals.size
    rec = np.array(["zeta"] * 60 + ["alpha"] * 60, dtype=object)
    flat = np.full(n, 0.25)
    arrays = {
        "delta_rel": flat,
        "theta_rel": flat,
        "alpha_rel": flat,
        "beta_rel": np.full(n, 0.1),
        "band_atr": vals,
        "band_delta": np.full(n, 0.05),
        "delta_abs": np.full(n, 0.05),
        "ai_a_vig": vals,
        "labels": labels,
        "cal_n": np.array([20], dtype=np.int32),
        "recording_id": rec,
    }
    if with_cal_starts:
        arrays["cal_starts"] = np.array([0, 60], dtype=np.int32)
        arrays["cal_lens"] = np.array([20, 20], dtype=np.int32)
    np.savez_compressed(path, **arrays)
    return path


# --- per-recording calibration ------------------------------------------------


def test_per_recording_cal_gives_own_thresholds(tmp_path):
    grids = load_grids()
    per = load_corpus(_two_baseline_corpus(tmp_path / "per.npz"))
    glob = load_corpus(_two_baseline_corpus(tmp_path / "glob.npz", with_cal_starts=False))

    plan = build_cal_plan(per)
    assert plan.per_recording
    assert [g.recording_id for g in plan.groups] == ["zeta", "alpha"]  # first-appearance order
    assert plan.play_idx.size == 80  # both cal blocks excluded
    assert not np.isin(np.r_[np.arange(0, 20), np.arange(60, 80)], plan.play_idx).any()
    assert build_cal_plan(glob).play_idx.size == 100  # legacy: only first cal_n rows dropped

    res_per = simulate_protocol(AI_GUARD, per, grids)
    res_glob = simulate_protocol(AI_GUARD, glob, grids)
    thr = res_per["parts"]["guard"]["thresholds_per_recording"]
    exp_a = threshold_at_percentile(np.linspace(0.0, 1.0, 20), 75)
    exp_b = threshold_at_percentile(np.linspace(10.0, 11.0, 20), 75)
    assert thr["zeta"] == pytest.approx(exp_a, abs=1e-4)
    assert thr["alpha"] == pytest.approx(exp_b, abs=1e-4)
    assert res_glob["parts"]["guard"]["threshold"] == pytest.approx(exp_a, abs=1e-4)
    assert thr["alpha"] != pytest.approx(res_glob["parts"]["guard"]["threshold"])
    assert res_per["calibration"]["mode"] == "per_recording"
    assert "calibration" not in res_glob
    # own baselines separate both recordings perfectly; the global one cannot
    assert res_per["parts"]["guard"]["label_align"] == pytest.approx(1.0)
    assert res_glob["parts"]["guard"]["label_align"] < 0.8

    # reward lane @ p75: per-recording, only the label-1 half is above its own threshold
    rr = simulate_protocol(ATR_REWARD, per, grids, reward_percentile=75)
    assert rr["parts"]["reward"]["hit_rate"] == pytest.approx(0.5)
    assert rr["parts"]["reward"]["n_play"] == 80
    assert set(rr["parts"]["reward"]["thresholds_per_recording"]) == {"zeta", "alpha"}

    # feature board uses the same plan
    meta = {"label": "A-vig", "source": "ai", "usableFor": ["guard"]}
    f_per = score_feature("ai.a_vig", meta, per, grids, is_orphan=False, roles_in_protocols=[])
    f_glob = score_feature("ai.a_vig", meta, glob, grids, is_orphan=False, roles_in_protocols=[])
    assert f_per["best_label_align"] == pytest.approx(1.0)
    assert f_per["best_label_align"] > f_glob["best_label_align"]
    assert f_per["calibration"]["n_recordings"] == 2


def test_cal_block_must_sit_inside_its_recording(tmp_path):
    path = _two_baseline_corpus(tmp_path / "bad.npz")
    d = dict(np.load(path, allow_pickle=True))
    d["cal_starts"] = np.array([0, 50], dtype=np.int32)  # 'alpha' block starts in 'zeta'
    np.savez_compressed(tmp_path / "bad2.npz", **d)
    with pytest.raises(ValueError, match="alpha"):
        load_corpus(tmp_path / "bad2.npz")
    d["cal_starts"] = np.array([0], dtype=np.int32)
    d["cal_lens"] = np.array([20], dtype=np.int32)
    np.savez_compressed(tmp_path / "bad3.npz", **d)
    with pytest.raises(ValueError, match="one per unique recording_id"):
        load_corpus(tmp_path / "bad3.npz")


def test_zero_cal_len_skips_recording(tmp_path):
    path = _two_baseline_corpus(tmp_path / "c.npz")
    d = dict(np.load(path, allow_pickle=True))
    d["cal_lens"] = np.array([20, 0], dtype=np.int32)
    np.savez_compressed(tmp_path / "c2.npz", **d)
    plan = build_cal_plan(load_corpus(tmp_path / "c2.npz"))
    assert plan.play_idx.size == 40  # only zeta's play rows
    assert plan.skipped == ["alpha:no_cal_block"]


# --- back-compat ---------------------------------------------------------------

# Captured from origin/main (pre per-recording code) on the tracked synthetic demo.
LEGACY_FINALS = {"drowsiness": 0.6523, "concentration": 0.5817, "alertnessOpen": 0.5849, "guardrailOnly": 0.85}
LEGACY_FEATURES = {
    "band.atr": (0.1902, 0.9987, 50),
    "band.delta": (0.9743, 1.0, 95),
    "ai.a_vig": (0.9913, 0.9997, 95),
    "ai.a_vig_reve": (0.9893, 0.9997, 95),
}
LEGACY_PROTOCOLS = {
    "drowsiness": {
        "reward": {"feature": "band.atr", "policy": "percentileUptrain", "inhibit": []},
        "guard": {"feature": "band.delta", "policy": "percentileWarn"},
    },
    "concentration": {
        "reward": {
            "feature": "band.alpha",
            "policy": "percentileUptrain",
            "inhibit": [{"type": "betaCeiling", "max": 0.25}],
        },
        "guard": {"feature": "band.delta", "policy": "percentileWarn"},
    },
    "alertnessOpen": {
        "reward": {"feature": "band.btr", "policy": "percentileUptrain", "inhibit": []},
        "guard": None,
    },
    "guardrailOnly": {"reward": None, "guard": {"feature": "band.delta", "policy": "percentileWarn"}},
}
LEGACY_META = {
    "band.atr": {"source": "band", "usableFor": ["reward"]},
    "band.delta": {"source": "band", "usableFor": ["guard"]},
    "ai.a_vig": {"source": "ai", "usableFor": ["guard"]},
    "ai.a_vig_reve": {"source": "ai", "usableFor": ["guard"]},
}


def test_no_cal_starts_matches_legacy_golden():
    corpus = load_corpus(GYM / "corpora" / "synthetic" / "demo_session.npz")
    assert "cal_starts" not in corpus
    grids = load_grids()
    for pid, spec in LEGACY_PROTOCOLS.items():
        res = simulate_protocol({"id": pid, **spec}, corpus, grids)
        assert res["final"] == LEGACY_FINALS[pid], pid
        assert "calibration" not in res
    for fid, (score, sep, best_p) in LEGACY_FEATURES.items():
        out = score_feature(fid, LEGACY_META[fid], corpus, grids, is_orphan=False, roles_in_protocols=[])
        assert (out["score"], out["sep"], out["best_p"]) == (score, sep, best_p), fid


def test_single_recording_cal_block_equals_global_cal_n(tmp_path):
    """cal_starts=[0], cal_lens=[cal_n] on one recording == legacy first-cal_n path."""
    src = generate_synthetic_corpus(tmp_path / "g", n=400, seed=5)
    legacy = load_corpus(src)
    d = dict(np.load(src, allow_pickle=True))
    n = d["band_atr"].size
    d["recording_id"] = np.array(["only"] * n, dtype=object)
    d["cal_starts"] = np.array([0], dtype=np.int32)
    d["cal_lens"] = np.array([int(d["cal_n"][0])], dtype=np.int32)
    np.savez_compressed(tmp_path / "per.npz", **d)
    per = load_corpus(tmp_path / "per.npz")
    grids = load_grids()
    for pid, spec in LEGACY_PROTOCOLS.items():
        a = simulate_protocol({"id": pid, **spec}, legacy, grids)
        b = simulate_protocol({"id": pid, **spec}, per, grids)
        assert a["final"] == b["final"], pid
    for fid, meta in LEGACY_META.items():
        a = score_feature(fid, meta, legacy, grids, is_orphan=False, roles_in_protocols=[])
        b = score_feature(fid, meta, per, grids, is_orphan=False, roles_in_protocols=[])
        assert a["sweep"] == b["sweep"], fid


# --- presets / corpus root -------------------------------------------------------


def test_sibling_presets_registered_from_manifest():
    for name, rel in {
        "lee2026-eo-ec": "corpora/external/lee2026_eo_ec.npz",
        "universe-stress": "corpora/external/universe_stress.npz",
        "alkabbany-stress": "corpora/external/alkabbany_stress.npz",
    }.items():
        entry = run_gym.SIBLING_PRESETS[name]
        assert run_gym.PRESETS[name] == rel
        assert entry["use_status"] == "findings-only"
        assert entry["license"]
        assert entry["source_repo"] == "windwerfer/neurofeed-gym-corpora"


def test_missing_sibling_npz_prints_builder_command(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(run_gym, "GYM_ROOT", tmp_path / "gym")
    root = tmp_path / "corpora-repo"
    (root / "builders").mkdir(parents=True)
    rc = run_gym.main(["--preset", "lee2026-eo-ec", "--corpus-root", str(root)])
    err = capsys.readouterr().err
    assert rc == run_gym.EXIT_MISSING_CORPUS != 0
    out = (tmp_path / "gym" / "corpora" / "external" / "lee2026_eo_ec.npz").resolve()
    assert f"python3 {root.resolve() / 'builders' / 'build_lee2026.py'} --out {out}" in err
    assert "Not falling back to the synthetic corpus" in err
    assert not (tmp_path / "gym" / "results").exists()  # nothing scored

    # multi mode: one missing corpus aborts the whole board up front
    rc = run_gym.main(["--presets", "synthetic,alkabbany-stress", "--corpus-root", str(root)])
    err = capsys.readouterr().err
    assert rc == run_gym.EXIT_MISSING_CORPUS
    assert "build_alkabbany.py --out" in err
    assert not (tmp_path / "gym" / "results").exists()


def test_default_corpus_root_env_override(monkeypatch, tmp_path):
    monkeypatch.setenv(run_gym.CORPUS_ROOT_ENV, str(tmp_path))
    assert run_gym.default_corpus_root() == tmp_path


# --- multi-corpus board --------------------------------------------------------


def test_merge_boards_marks_na():
    run_a = {
        "run_id": "A",
        "features": [
            {"id": "band.atr", "status": "ok", "score": 0.8, "sep": 0.6, "best_p": 50},
            {"id": "ai.a_vig", "status": "ok", "score": 0.78, "sep": 0.85, "best_p": 95},
        ],
        "protocols": [
            {"id": "p1", "final": 0.7, "parts": {"reward": {"score": 0.8}, "inhibit": {"score": 1.0}, "guard": {"score": 0.43}}},
        ],
    }
    run_b = {
        "run_id": "B",
        "features": [
            {"id": "band.atr", "status": "ok", "score": 0.6, "sep": 0.7, "best_p": 55},
            {"id": "ai.a_vig", "status": "needs_pack", "score": None, "notes": ["AI pack inference unavailable"]},
        ],
        "protocols": [
            {"id": "p1", "final": 0.9, "parts": {"reward": {"score": 0.9}, "inhibit": {"score": 1.0}, "guard": {"status": "unavailable", "feature": "ai.a_vig"}}},
            {"id": "p2", "final": None, "parts": {"reward": None, "inhibit": None, "guard": None}},
        ],
    }
    board = run_gym.merge_boards([("a", run_a), ("b", run_b)])
    feats = {f["id"]: f["by_corpus"] for f in board["features"]}
    assert feats["band.atr"]["b"] == {"score": 0.6, "sep": 0.7, "best_p": 55, "status": "ok"}
    assert feats["ai.a_vig"]["a"]["score"] == 0.78
    assert feats["ai.a_vig"]["b"]["na"] is True and feats["ai.a_vig"]["b"]["status"] == "needs_pack"
    protos = {p["id"]: p["by_corpus"] for p in board["protocols"]}
    assert protos["p1"]["b"]["guard"] == "N/A"
    assert protos["p1"]["a"]["guard"] == 0.43
    assert protos["p2"]["a"]["status"] == "absent"  # protocol missing from run a
    assert protos["p2"]["b"]["na"] is True
    md = run_gym.render_multi_stats(board, run_id="X_multi", timestamp="t")
    assert "| ai.a_vig | 0.780 · sep 0.850 · p95 | N/A (needs_pack) |" in md
    assert "g N/A" in md


def test_presets_cli_writes_per_corpus_runs_and_board(tmp_path, monkeypatch):
    gym = tmp_path / "gym"
    monkeypatch.setattr(run_gym, "GYM_ROOT", gym)
    _band_only_npz(gym / "corpora" / "external" / "lee2026_eo_ec.npz")
    rc = run_gym.main(["--presets", "synthetic,lee2026-eo-ec"])
    assert rc == 0
    runs = sorted(p.name for p in (gym / "results").iterdir() if p.is_dir())
    assert len(runs) == 3
    assert any(r.endswith("_synthetic") for r in runs)
    assert any(r.endswith("_lee2026-eo-ec") for r in runs)
    multi = next(gym / "results" / r for r in runs if r.endswith("_multi"))
    board = json.loads((multi / "multi_board.json").read_text())
    assert board["labels"] == ["synthetic", "lee2026-eo-ec"]
    feats = {f["id"]: f["by_corpus"] for f in board["features"]}
    assert feats["ai.a_vig"]["synthetic"]["status"] == "ok"
    assert feats["ai.a_vig"]["lee2026-eo-ec"]["na"] is True  # no AI emb on sibling corpora
    assert feats["band.atr"]["lee2026-eo-ec"]["status"] == "ok"
    lee = next(c for c in board["corpora"] if c["label"] == "lee2026-eo-ec")
    assert lee["sibling"]["use_status"] == "findings-only"
    assert lee["corpus_meta"]["label_names"] == ["eyes_open", "eyes_closed"]
    md = (gym / "MULTI_CORPUS_STATS.md").read_text()
    assert "lee2026-eo-ec" in md and "N/A" in md
    # living single-run outputs untouched in multi mode
    assert not (gym / "PROTOCOL_STATS.md").exists()
    assert not (gym / "ui" / "data" / "latest.json").exists()
