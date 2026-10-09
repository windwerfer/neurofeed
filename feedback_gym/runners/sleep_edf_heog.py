#!/usr/bin/env python3
"""Positive control for the slow-eye-movement (SEM) index: TRUE horizontal EOG on Sleep-EDF.

NOT a pad-mixing test. Sleep-EDF has Fpz-Cz / Pz-Oz plus a real horizontal
EOG channel (outer canthi). There is no AF7 - AF8 signal, so this measures the
best case for the SEM idea: does horizontal-EOG low-frequency power (same
definition as neurofeed-gym-corpora ``builders/pad_mix.py`` ``sem_2s`` /
``sem_8s``) separate W from N1 on the gym's Sleep-EDF rows? A Muse AF7 - AF8
bipolar sees a much smaller, noisier version of this signal.

Adds gym-only columns ``heog_sem_2s`` / ``heog_sem_8s`` to the Sleep-EDF NPZ
(row-aligned with the existing columns; the window start comes from the
muse-eeg-heads windows ``starts`` + manifest ``slice_start_sec``), then scores
them with the fair-round rules next to ``ai.a_vig`` and frontal ``band.delta``.

Needs mne (EDF reader)::

    uv run --with numpy --with scipy --with mne --with pyyaml \\
        python runners/sleep_edf_heog.py [--corpus corpora/external/sleep_edf_test.npz]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import numpy as np

GYM_ROOT = Path(__file__).resolve().parent.parent
if str(GYM_ROOT) not in sys.path:
    sys.path.insert(0, str(GYM_ROOT))

from runners.build_corpus_sleep_edf import DEFAULT_WINDOWS, emb_keep_indices  # noqa: E402
from runners.fair_round import FEATURE_BY_ID, score_direction  # noqa: E402
from runners.helpers import load_corpus  # noqa: E402

HEADS_WINDOWS_ROOT = DEFAULT_WINDOWS.parent.parent  # .../muse-eeg-heads-windows
PSG_ROOT = HEADS_WINDOWS_ROOT.parent / "muse-eeg-heads-cache" / "data" / "sleep-edfx-pilot"
WIN_SR = 256.0  # windows ``starts`` are in samples at the resampled 256 Hz
WIN_S = 2.0
LOWFREQ = {"heog_sem_2s": (2.0, 0.5, 2.0), "heog_sem_8s": (8.0, 0.25, 1.0), "heog_fast_8s": (8.0, 1.0, 5.0)}


def _detrend(w: np.ndarray) -> np.ndarray:
    """Remove a least-squares line from each row (numpy only; == scipy detrend 'linear')."""
    n = w.shape[-1]
    t = np.arange(n, dtype=np.float64) - (n - 1) / 2.0
    slope = (w * t).sum(axis=-1, keepdims=True) / float((t * t).sum())
    return w - w.mean(axis=-1, keepdims=True) - slope * t


def lowfreq_power(sig: np.ndarray, sr: float, ends_s: np.ndarray, dur_s: float, lo: float, hi: float) -> np.ndarray:
    """Power in [lo, hi) Hz of the ``dur_s`` seconds ending at each ``ends_s`` (pad_mix.lowfreq_power)."""
    n = int(round(dur_s * sr))
    first = np.round(ends_s * sr).astype(int) - n
    out = np.full(ends_s.size, np.nan)
    ok = (first >= 0) & (first + n <= sig.size)
    if not ok.any():
        return out
    idx = first[ok][:, None] + np.arange(n)[None, :]
    w = _detrend(sig[idx])
    ham = 0.54 - 0.46 * np.cos(2.0 * np.pi * np.arange(n) / n)
    spec = np.fft.rfft(w * ham, axis=-1)
    psd = (spec.real**2 + spec.imag**2) * (2.0 / (sr * float(np.sum(ham * ham))))
    f = np.arange(psd.shape[-1]) * sr / n
    m = (f >= lo) & (f < hi)
    out[ok] = psd[:, m].sum(axis=-1) * (sr / n)
    return out


def heog_columns(corpus: dict[str, Any], windows_dir: Path = DEFAULT_WINDOWS) -> dict[str, np.ndarray]:
    import mne

    rid = np.asarray(corpus["recording_id"]).astype(str)
    labels = np.asarray(corpus["labels"])
    cols = {k: np.full(rid.size, np.nan) for k in LOWFREQ}
    for rec in dict.fromkeys(rid):
        rows = np.where(rid == rec)[0]
        win = np.load(windows_dir / f"{rec}_windows.npz", allow_pickle=True)
        starts = np.asarray(win["starts"])
        idxs = np.arange(starts.size) if starts.size == rows.size else emb_keep_indices(win)
        idxs = idxs[: rows.size]
        if idxs.size != rows.size or not np.array_equal(np.asarray(win["y"])[idxs], labels[rows]):
            raise ValueError(f"{rec}: windows do not line up with corpus rows")
        man = json.loads((HEADS_WINDOWS_ROOT / f"sleep_edf_{rec.lower()}_n1slice_manifest.json").read_text())
        sub = "sleep-cassette" if rec.startswith("SC") else "sleep-telemetry"
        raw = mne.io.read_raw_edf(PSG_ROOT / sub / man["psg_file"], preload=False, verbose="ERROR")
        sr = float(raw.info["sfreq"])
        eog = raw.get_data(picks=["EOG horizontal"])[0] * 1e6
        ends = float(man["slice_start_sec"]) + starts[idxs] / WIN_SR + WIN_S
        for k, (dur, lo, hi) in LOWFREQ.items():
            cols[k][rows] = lowfreq_power(eog, sr, ends, dur, lo, hi)
    return cols


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--corpus", type=Path, default=GYM_ROOT / "corpora" / "external" / "sleep_edf_test.npz")
    ap.add_argument("--out-json", type=Path, default=None)
    ap.add_argument("--no-write", action="store_true", help="score only, do not add the columns to the NPZ")
    a = ap.parse_args(argv)
    corpus = load_corpus(a.corpus)
    if not all(k in corpus for k in LOWFREQ):
        cols = heog_columns(corpus)
        corpus.update(cols)
        if not a.no_write:
            data = dict(np.load(a.corpus, allow_pickle=True))
            data.update(cols)
            np.savez_compressed(a.corpus, **data)
    res: dict[str, Any] = {}
    with np.errstate(divide="ignore", invalid="ignore"):
        ratio = np.asarray(corpus["heog_sem_8s"], dtype=float) / np.asarray(corpus["heog_fast_8s"], dtype=float)
    series = {  # name -> (values, sleep direction)
        "heog_sem_2s (0.5-2 Hz, 2 s) ↑": (corpus["heog_sem_2s"], +1),
        "heog_sem_8s (0.25-1 Hz, 8 s) ↑": (corpus["heog_sem_8s"], +1),
        "heog_fast_8s (1-5 Hz, 8 s) ↓": (corpus["heog_fast_8s"], -1),
        "heog slowness ratio sem_8s / fast_8s ↑": (ratio, +1),
        "ai.a_vig ↑": (corpus["ai_a_vig"], +1),
        "band.delta (Fpz-Cz) ↑": (corpus["band_delta"], +1),
    }
    print("| feature (sleep dir) | per-rec AUC in sleep dir, median [IQR] | recs > 0.5 | BA p90 | warn p90 W / N1 |\n|---|---|---:|---:|---|")
    for name, (s, sdir) in series.items():
        d = score_direction(sdir * np.asarray(s, dtype=float), corpus, +1)
        g = d["guard"][90]
        res[name] = {k: d[k] for k in ("per_rec_auc_median", "per_rec_auc_q25", "per_rec_auc_q75", "per_rec_n", "per_rec_above_half")}
        res[name]["guard_p90"] = g
        print(f"| {name} | {d['per_rec_auc_median']:.3f} [{d['per_rec_auc_q25']:.3f}–{d['per_rec_auc_q75']:.3f}] | "
              f"{d['per_rec_above_half']}/{d['per_rec_n']} | {g['balanced_acc']:.3f} | "
              f"{g['warn_rate_label0']:.2f} / {g['warn_rate_label1']:.2f} |")
    if a.out_json:
        a.out_json.write_text(json.dumps(res, indent=1, default=float))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
