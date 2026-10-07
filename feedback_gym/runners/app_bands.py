"""Gym-only port of the app's CURRENT band math (rust/src/api/muse.rs + features.rs).

Why this exists: every gym corpus (Sleep-EDF builder here, Lee / UNIVERSE in
neurofeed-gym-corpora) computes band columns with muse-eeg-heads
``band_math/features/flutter_bands.py``. That file mirrors an older muse.rs:
rectangular window, ``|X|^2 / n^2`` scale, inclusive bins ``round(lo)..round(hi)``
(so the 4 / 8 / 13 / 30 Hz bins are counted in two bands) and gamma 30-50 Hz.
Since 2026-09-28 the app uses (``compute_fft_bands``):

- periodic Hamming window ``0.54 - 0.46 cos(2 pi i / n)``
- one-sided PSD ``2 |X_k|^2 / (fs * sum w^2)`` in uV^2/Hz, band power = PSD
  summed over the band's bins x 1 Hz bin width (bins ``1 .. n/2 - 1``)
- half-open bands ``[lo, hi)``: delta 1-4, theta 4-8, alpha 8-13, beta 13-30,
  gamma 30-45 (every 1 Hz bin in exactly one band; gamma stops below mains)
- ``features.rs``: ratios from per-pad relative bands averaged over the
  usable pads; ``band.delta`` = mean absolute delta over pads.

Not replicated: the live conditioner (0.5 Hz high-pass + mains notch) and
pad-quality gating. Offline corpora are already filtered by their builders.

This module is used only to measure how much the stale mirror changes the
gym's band numbers (FAIR_BANDMATH.md). It never ships in the app.
"""

from __future__ import annotations

import numpy as np

SR_HZ = 256.0
FFT_N = 256
BANDS_HZ = ((1.0, 4.0), (4.0, 8.0), (8.0, 13.0), (13.0, 30.0), (30.0, 45.0))


def hamming(n: int = FFT_N) -> np.ndarray:
    i = np.arange(n, dtype=np.float64)
    return 0.54 - 0.46 * np.cos(2.0 * np.pi * i / n)


def band_powers(x: np.ndarray, sr: float = SR_HZ) -> np.ndarray:
    """Absolute band powers ``[..., 5]`` (uV^2) for blocks ``[..., n]`` (n = 256)."""
    x = np.asarray(x, dtype=np.float64)
    n = x.shape[-1]
    w = hamming(n)
    psd_scale = 2.0 / (sr * float(np.sum(w * w)))
    spec = np.fft.rfft(x * w, axis=-1)
    psd = (spec.real**2 + spec.imag**2) * psd_scale
    hz_per_bin = sr / n
    k = np.arange(psd.shape[-1])
    f = k * hz_per_bin
    valid = (k >= 1) & (k < n // 2)
    out = []
    for lo, hi in BANDS_HZ:
        m = valid & (f >= lo) & (f < hi)
        out.append(psd[..., m].sum(axis=-1) * hz_per_bin)
    return np.stack(out, axis=-1)


def window_bands(X: np.ndarray) -> np.ndarray:
    """``(N, C, T)`` windows -> ``(N, C, 5)`` bands, averaged over 1 s blocks."""
    X = np.asarray(X, dtype=np.float64)
    n, c, t = X.shape
    nb = max(1, t // FFT_N)
    blocks = X[:, :, : nb * FFT_N].reshape(n, c, nb, FFT_N)
    return band_powers(blocks).mean(axis=2)


def app_features(X: np.ndarray, pads: tuple[int, ...] = (0, 1)) -> dict[str, np.ndarray]:
    """App feature scalars + relative bands for ``(N, C, T)`` windows on ``pads``."""
    b = window_bands(np.asarray(X)[:, list(pads), :])  # (N, P, 5)
    tot = b.sum(axis=-1, keepdims=True)
    with np.errstate(divide="ignore", invalid="ignore"):
        rel = np.where(tot > 0, b / tot, np.nan)  # per-pad relative
    rel_avg = np.nanmean(rel, axis=1)  # features.rs: average usable pads
    t, a, be = rel_avg[:, 1], rel_avg[:, 2], rel_avg[:, 3]
    with np.errstate(divide="ignore", invalid="ignore"):
        atr = np.where(t > 0, a / t, np.nan)
        tar = np.where(a > 0, t / a, np.nan)
        btr = np.where(t > 0, be / t, np.nan)
    return {
        "band.atr": atr,
        "band.tar": tar,
        "band.btr": btr,
        "band.alpha": a,
        "band.delta": b[:, :, 0].mean(axis=1),
        "rel_delta": rel_avg[:, 0],
        "rel_theta": t,
        "rel_alpha": a,
        "rel_beta": be,
        "abs_delta": b[:, :, 0].mean(axis=1),
    }
