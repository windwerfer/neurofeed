"""Gym-only spectral-shape features from per-window PSD columns (literature checks).

Contract for PSD columns (written by literature-check builders, gitignored NPZs):

- ``psd_<site>``: float32 ``(N, 45)``, one-sided PSD in uV^2/Hz at 1 Hz bins
  ``f = 1 .. 45`` Hz (``psd_freqs``). Each row is the mean of 1 s periodic-Hamming
  blocks inside the row's window, exactly the app's ``compute_fft_bands`` PSD
  (``runners/app_bands.py``) restricted to bins 1..45. So
  ``band_from_psd(psd, (lo, hi))`` == app band power for ``[lo, hi)``.
- Sites are named after the electrode / derivation (``af7``, ``tp9``, ``fpz_cz``,
  ``pz_oz``, ``fz``, ...).

Features (all per row; NaN where undefined):

- band powers / relative bands on the app edges (delta 1-4, theta 4-8,
  alpha 8-13, beta 13-30, gamma 30-45; relative over 1-45 Hz)
- spectral entropy (normalised Shannon entropy of the PSD over [lo, hi))
- spectral edge frequency SEF_q (frequency below which q of [lo, hi) power lies)
- aperiodic slope: least-squares slope of log10 PSD vs log10 f, either
  2-40 Hz with 7-14 Hz (alpha / sigma peaks) excluded, or 30-45 Hz (Lendner 2020)
- peak alpha frequency: argmax over 7-13 Hz with parabolic refinement, and the
  7-13 Hz centre of gravity
- ratios: engagement beta/(alpha+theta) (Pope 1995), (theta+alpha)/beta,
  theta/beta, alpha/theta.

No scoring here; ``runners/literature_checks.py`` scores.
"""

from __future__ import annotations

from typing import Iterable

import numpy as np

PSD_FREQS = np.arange(1, 46, dtype=np.float64)  # 1 .. 45 Hz, 1 Hz bins
APP_BANDS = {
    "delta": (1.0, 4.0),
    "theta": (4.0, 8.0),
    "alpha": (8.0, 13.0),
    "beta": (13.0, 30.0),
    "gamma": (30.0, 45.0),
}


def hamming_periodic(n: int) -> np.ndarray:
    i = np.arange(n, dtype=np.float64)
    return 0.54 - 0.46 * np.cos(2.0 * np.pi * i / n)


def psd_1hz(x: np.ndarray, sr: float) -> np.ndarray:
    """PSD rows for signals ``x[..., T]`` at sample rate ``sr`` (integer Hz).

    Splits ``T`` into non-overlapping 1 s blocks (``n = sr`` samples, so 1 Hz
    bins), periodic Hamming, one-sided PSD ``2|X|^2 / (sr * sum w^2)``, averaged
    over blocks. Returns ``[..., 45]`` (bins 1..45 Hz). Needs ``sr >= 92``.
    """
    x = np.asarray(x, dtype=np.float64)
    n = int(round(sr))
    if n < 92:
        raise ValueError("need sr >= 92 Hz for bins up to 45 Hz")
    nb = x.shape[-1] // n
    if nb < 1:
        raise ValueError("window shorter than 1 s")
    blocks = x[..., : nb * n].reshape(*x.shape[:-1], nb, n)
    w = hamming_periodic(n)
    spec = np.fft.rfft(blocks * w, axis=-1)
    psd = (spec.real**2 + spec.imag**2) * (2.0 / (sr * float(np.sum(w * w))))
    psd = psd.mean(axis=-2)
    return psd[..., 1:46]


def _mask(lo: float, hi: float) -> np.ndarray:
    return (PSD_FREQS >= lo) & (PSD_FREQS < hi)


def band_from_psd(psd: np.ndarray, band: tuple[float, float]) -> np.ndarray:
    """Band power (uV^2) = sum of 1 Hz bins in ``[lo, hi)`` x 1 Hz."""
    return np.asarray(psd, dtype=np.float64)[..., _mask(*band)].sum(axis=-1)


def bands(psd: np.ndarray) -> dict[str, np.ndarray]:
    return {k: band_from_psd(psd, v) for k, v in APP_BANDS.items()}


def rel_bands(psd: np.ndarray) -> dict[str, np.ndarray]:
    b = bands(psd)
    tot = sum(b.values())
    with np.errstate(divide="ignore", invalid="ignore"):
        return {k: np.where(tot > 0, v / tot, np.nan) for k, v in b.items()}


def spectral_entropy(psd: np.ndarray, lo: float = 1.0, hi: float = 30.0) -> np.ndarray:
    """Normalised Shannon entropy (0 = one bin, 1 = flat) over ``[lo, hi)``."""
    p = np.asarray(psd, dtype=np.float64)[..., _mask(lo, hi)]
    tot = p.sum(axis=-1, keepdims=True)
    with np.errstate(divide="ignore", invalid="ignore"):
        q = np.where(tot > 0, p / tot, np.nan)
        h = -np.nansum(np.where(q > 0, q * np.log(q), 0.0), axis=-1)
    out = h / np.log(p.shape[-1])
    return np.where(tot[..., 0] > 0, out, np.nan)


def sef(psd: np.ndarray, q: float = 0.95, lo: float = 1.0, hi: float = 30.0) -> np.ndarray:
    """Spectral edge frequency: upper edge (Hz) of the bin where cumulative power reaches ``q``."""
    m = _mask(lo, hi)
    p = np.asarray(psd, dtype=np.float64)[..., m]
    f = PSD_FREQS[m]
    c = np.cumsum(p, axis=-1)
    tot = c[..., -1:]
    with np.errstate(divide="ignore", invalid="ignore"):
        frac = np.where(tot > 0, c / tot, np.nan)
    idx = np.argmax(frac >= q, axis=-1)
    out = f[idx] + 0.5  # bin k covers [k - 0.5, k + 0.5)
    return np.where(tot[..., 0] > 0, out, np.nan)


def aperiodic_slope(
    psd: np.ndarray, lo: float = 2.0, hi: float = 40.0, exclude: Iterable[tuple[float, float]] = ((7.0, 14.0),)
) -> np.ndarray:
    """Slope of log10 PSD vs log10 f over ``[lo, hi]`` minus ``exclude`` ranges.

    More negative = steeper = lower arousal (Lendner 2020 use 30-45 Hz).
    """
    m = (PSD_FREQS >= lo) & (PSD_FREQS <= hi)
    for a, b in exclude:
        m &= ~((PSD_FREQS >= a) & (PSD_FREQS <= b))
    x = np.log10(PSD_FREQS[m])
    p = np.asarray(psd, dtype=np.float64)[..., m]
    with np.errstate(divide="ignore", invalid="ignore"):
        y = np.where(p > 0, np.log10(p), np.nan)
    xc = x - x.mean()
    ok = np.isfinite(y).all(axis=-1)
    y0 = np.where(np.isfinite(y), y, 0.0)
    slope = ((y0 - y0.mean(axis=-1, keepdims=True)) * xc).sum(axis=-1) / float((xc * xc).sum())
    return np.where(ok, slope, np.nan)


def peak_alpha(psd: np.ndarray, lo: float = 7.0, hi: float = 13.0) -> dict[str, np.ndarray]:
    """IAF on the aperiodic-corrected spectrum.

    The 1/f trend is removed first (log10 PSD minus the 2-40 Hz fit with 7-14 Hz
    excluded); the peak is the largest *interior local maximum* of the residual in
    [lo, hi] with parabolic refinement (NaN when there is none, e.g. no alpha
    peak in deep sleep). ``cog`` is the centre of gravity of the positive residual
    in [lo, hi]. Without the correction argmax sits on the 7 Hz edge whenever the
    1/f slope dominates (seen on Sleep-EDF).
    """
    p = np.asarray(psd, dtype=np.float64)
    fit_m = (PSD_FREQS >= 2.0) & (PSD_FREQS <= 40.0) & ~((PSD_FREQS >= 7.0) & (PSD_FREQS <= 14.0))
    lx = np.log10(PSD_FREQS)
    with np.errstate(divide="ignore", invalid="ignore"):
        ly = np.where(p > 0, np.log10(p), np.nan)
    x = lx[fit_m]
    y = ly[..., fit_m]
    xm = x.mean()
    slope = ((y - np.nanmean(y, axis=-1, keepdims=True)) * (x - xm)).sum(axis=-1) / float(((x - xm) ** 2).sum())
    icpt = np.nanmean(y, axis=-1) - slope * xm
    resid = ly - (icpt[..., None] + slope[..., None] * lx)
    m = (PSD_FREQS >= lo) & (PSD_FREQS <= hi)
    f = PSD_FREQS[m]
    r = resid[..., m]
    # interior local maxima only
    loc = np.zeros(r.shape, dtype=bool)
    loc[..., 1:-1] = (r[..., 1:-1] > r[..., :-2]) & (r[..., 1:-1] >= r[..., 2:])
    rr = np.where(loc, r, -np.inf)
    k = np.argmax(rr, axis=-1)
    has = np.isfinite(np.take_along_axis(rr, k[..., None], axis=-1)[..., 0])
    km = np.clip(k - 1, 0, f.size - 1)
    kp = np.clip(k + 1, 0, f.size - 1)
    take = lambda idx: np.take_along_axis(r, idx[..., None], axis=-1)[..., 0]  # noqa: E731
    a, b, c = take(km), take(k), take(kp)
    den = a - 2 * b + c
    with np.errstate(divide="ignore", invalid="ignore"):
        delta = np.where(den != 0, 0.5 * (a - c) / den, 0.0)
    paf = np.where(has, f[k] + np.clip(delta, -0.5, 0.5), np.nan)
    pos = np.clip(np.nan_to_num(r, nan=0.0), 0.0, None)
    tot = pos.sum(axis=-1)
    with np.errstate(divide="ignore", invalid="ignore"):
        cog = np.where(tot > 0, (pos * f).sum(axis=-1) / tot, np.nan)
    return {"paf": paf, "cog": cog, "peak_height": np.where(has, b, np.nan)}


def feature_table(psd: np.ndarray) -> dict[str, np.ndarray]:
    """All spectral features for one site's PSD ``(N, 45)``."""
    b = bands(psd)
    r = rel_bands(psd)
    eps = 1e-12
    with np.errstate(divide="ignore", invalid="ignore"):
        out = {
            **{f"rel_{k}": v for k, v in r.items()},
            **{f"log_{k}": np.log10(np.maximum(v, eps)) for k, v in b.items()},
            "engagement": b["beta"] / (b["alpha"] + b["theta"]),
            "tab": (b["theta"] + b["alpha"]) / b["beta"],
            "tbr": b["theta"] / b["beta"],
            "btr": b["beta"] / b["theta"],
            "atr": b["alpha"] / b["theta"],
            "gamma_over_at": b["gamma"] / (b["alpha"] + b["theta"]),
            "rel_sigma": band_from_psd(psd, (12.0, 16.0)) / sum(b.values()),
            "log_sigma": np.log10(np.maximum(band_from_psd(psd, (12.0, 16.0)), eps)),
            # spindle-band share of the local 8-20 Hz neighbourhood (insensitive to delta growth)
            "sigma_local": band_from_psd(psd, (12.0, 16.0)) / np.maximum(band_from_psd(psd, (8.0, 20.0)), eps),
        }
    out["entropy_1_30"] = spectral_entropy(psd, 1.0, 30.0)
    out["entropy_1_45"] = spectral_entropy(psd, 1.0, 45.0)
    out["sef95"] = sef(psd, 0.95, 1.0, 30.0)
    out["sef50"] = sef(psd, 0.50, 1.0, 30.0)
    out["slope_2_40"] = aperiodic_slope(psd, 2.0, 40.0)
    out["slope_30_45"] = aperiodic_slope(psd, 30.0, 45.0, exclude=())
    pa = peak_alpha(psd)
    out["paf"] = pa["paf"]
    out["alpha_cog"] = pa["cog"]
    out["alpha_peak_height"] = pa["peak_height"]
    return out
