"""Unit tests for linear-head softmax and Sleep-EDF corpus builder (tiny fixture)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pytest

GYM = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(GYM))

from runners.build_corpus_sleep_edf import (  # noqa: E402
    build_corpus,
    load_linear_head,
    softmax_p_class1,
)
from runners.helpers import FEATURE_COLUMN, load_corpus  # noqa: E402


def test_softmax_p_class1_two_class():
    # emb that maps cleanly: class1 preferred when emb aligns with W[1]
    W = np.array([[1.0, 0.0], [0.0, 1.0]], dtype=np.float64)
    b = np.zeros(2)
    emb = np.array([[10.0, 0.0], [0.0, 10.0], [0.0, 0.0]])
    p = softmax_p_class1(emb, W, b)
    assert p[0] < 1e-4  # favors class0
    assert p[1] > 1.0 - 1e-4  # favors class1
    assert p[2] == pytest.approx(0.5, abs=1e-6)


def test_pack_head_a_layout_separates_when_available():
    head = (
        GYM.parent
        / "assets/packs/cbramod-a-vig-full/heads/head_a_vig_linear.f32bin"
    )
    emb_path = Path(
        "/workspace/muse-eeg-heads/exports/head_c_full_corpus/emb_cache/SC4001_emb.npz"
    )
    if not head.exists() or not emb_path.exists():
        pytest.skip("pack head or emb_cache not on this box")
    W, b = load_linear_head(head)
    assert W.shape == (2, 200)
    data = np.load(emb_path)
    emb, y = data["emb"], data["y_a"]
    p = softmax_p_class1(emb, W, b)
    assert p[y == 1].mean() > p[y == 0].mean() + 0.2


def test_build_corpus_tiny_fixture(tmp_path, monkeypatch):
    """Synthetic windows+emb+flutter shim → valid gym NPZ schema."""
    # Minimal flutter_bands stub so we do not require muse-eeg-heads for unit test
    band_root = tmp_path / "band_math"
    feat_dir = band_root / "features"
    feat_dir.mkdir(parents=True)
    (feat_dir / "__init__.py").write_text("")
    (band_root / "__init__.py").write_text("")
    (feat_dir / "flutter_bands.py").write_text(
        "import numpy as np\n"
        "def compute_window_features_fast(X):\n"
        "    n = X.shape[0]\n"
        "    return {\n"
        "        'band.atr': np.linspace(0.5, 1.5, n),\n"
        "        'band.tar': np.linspace(1.5, 0.5, n),\n"
        "        'band.btr': np.full(n, 0.8),\n"
        "        'band.alpha': np.linspace(0.3, 0.2, n),\n"
        "        'band.delta': np.linspace(0.05, 0.3, n),\n"
        "        'rel_delta': np.linspace(0.1, 0.4, n),\n"
        "        'rel_theta': np.full(n, 0.2),\n"
        "        'rel_alpha': np.linspace(0.4, 0.2, n),\n"
        "        'rel_beta': np.full(n, 0.2),\n"
        "        'abs_delta': np.linspace(0.05, 0.3, n),\n"
        "    }\n"
    )
    monkeypatch.setattr(
        "runners.build_corpus_sleep_edf.BAND_MATH_CANDIDATES",
        [band_root],
    )

    windows_dir = tmp_path / "windows"
    emb_dir = tmp_path / "emb"
    windows_dir.mkdir()
    emb_dir.mkdir()
    n = 40
    rng = np.random.default_rng(0)
    X = rng.normal(size=(n, 4, 512)).astype(np.float32)
    y = np.array([0] * 20 + [1] * 20, dtype=np.int64)
    emb = rng.normal(size=(n, 200)).astype(np.float32)
    # Make class1 emb align with a simple head direction for sep check
    emb[y == 1, 0] += 3.0
    np.savez(windows_dir / "REC1_windows.npz", X=X, y=y, label_names=np.array(["drowsy", "hypnagogic"]))
    np.savez(emb_dir / "REC1_emb.npz", emb=emb, y_a=y, y_c=y)

    # Tiny head: class1 weight on dim 0
    W = np.zeros((2, 200), dtype=np.float32)
    W[0, 0] = -1.0
    W[1, 0] = 1.0
    b = np.zeros(2, dtype=np.float32)
    head_a = tmp_path / "head_a.f32bin"
    head_c = tmp_path / "head_c.f32bin"
    np.concatenate([W.reshape(-1), b]).astype(np.float32).tofile(head_a)
    np.concatenate([W.reshape(-1), b]).astype(np.float32).tofile(head_c)

    splits = tmp_path / "splits.json"
    splits.write_text(json.dumps({"recordings": ["REC1"]}))

    out = tmp_path / "out.npz"
    summary = build_corpus(
        windows_dir=windows_dir,
        splits_path=splits,
        emb_dir=emb_dir,
        head_a_path=head_a,
        head_c_path=head_c,
        out_path=out,
        cal_n=10,
        reve_emb_dir=None,  # isolate fixture from box REVE caches
    )
    assert summary["n"] == 40
    assert summary["recordings_skipped"] == []
    assert out.exists()

    corpus = load_corpus(out)
    assert corpus["cal_n"] == 10
    assert len(corpus["labels"]) == 40
    for fid, col in FEATURE_COLUMN.items():
        if "reve" in fid:
            # Tiny fixture has no REVE emb → columns omitted (or NaN if forced)
            if col in corpus:
                assert len(corpus[col]) == 40
        else:
            assert col in corpus, fid
            assert len(corpus[col]) == 40
    # Head should separate on our planted signal
    assert corpus["ai_a_vig"][corpus["labels"] == 1].mean() > corpus["ai_a_vig"][
        corpus["labels"] == 0
    ].mean()
