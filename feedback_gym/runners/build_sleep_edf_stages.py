#!/usr/bin/env python3
"""Sleep-EDF ALL-STAGE spectral corpus for literature anchors (gym-only, gitignored).

The fair-round Sleep-EDF corpus (``build_corpus_sleep_edf.py``) keeps only W and
N1 windows in a slice around the first N1, so it cannot test the textbook
"entropy / SEF lower and aperiodic slope steeper in N1/N2 than in wake" anchors.
This builder reads the raw PSG EDF + hypnogram directly (MNE) and emits one row
per 30 s scored epoch, every stage, with app-style PSD columns
(``runners/spectral.py`` contract) for both EEG derivations.

Rows / columns (NPZ, ``corpora/external/sleep_edf_stages.npz``):

- ``stage`` int8: 0 W, 1 N1, 2 N2, 3 N3 (R&K S3+S4), 4 REM. Movement / ``?`` dropped.
- ``psd_fpz_cz``, ``psd_pz_oz``: float32 (N, 45), uV^2/Hz, 1..45 Hz (100 Hz native
  sampling, 1 s periodic-Hamming blocks averaged over the 30 s epoch; no resampling).
- ``eog_lf``: horizontal-EOG 1-3 Hz power (uV^2) per epoch (eye-movement activity).
- ``emg_env``: mean submental EMG envelope (SC files: 1 Hz channel), NaN if absent.
- ``t_rel_onset_s``: epoch start minus the first non-W epoch (sleep onset).
- ``w_context``: ``pre_onset`` (W in the 15 min before sleep onset),
  ``early`` (W 15-30 min before), ``waso`` (W after onset), ``-`` for sleep stages.
- gym-schema columns so ``load_corpus`` works: app-edge relative bands of Fpz-Cz
  (``delta_rel`` ...), ``labels`` (0 W, 1 any sleep stage), ``recording_id``,
  per-recording ``cal_starts`` / ``cal_lens`` (leading W, <= 20 rows = 10 min).

Window kept per recording: 30 min before sleep onset to the last sleep epoch
(the 22 h Sleep-EDF cassette files otherwise carry hours of daytime wake).

Usage::

    uv run --with numpy --with mne python runners/build_sleep_edf_stages.py \
        [--raw-dir /workspace/muse-eeg-heads/datasets/vigilance_sleep_edf/raw] [--max-recordings N]

License: Sleep-EDF Expanded (PhysioNet), Open Data Commons Attribution v1.0.
Findings-only: the NPZ is gitignored; only aggregates leave the box.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import numpy as np

GYM_ROOT = Path(__file__).resolve().parent.parent
if str(GYM_ROOT) not in sys.path:
    sys.path.insert(0, str(GYM_ROOT))

from runners.spectral import band_from_psd, APP_BANDS, psd_1hz  # noqa: E402

DEFAULT_RAW = Path("/workspace/muse-eeg-heads/datasets/vigilance_sleep_edf/raw")
DEFAULT_OUT = GYM_ROOT / "corpora/external/sleep_edf_stages.npz"
STAGE_MAP = {
    "Sleep stage W": 0,
    "Sleep stage 1": 1,
    "Sleep stage 2": 2,
    "Sleep stage 3": 3,
    "Sleep stage 4": 3,
    "Sleep stage R": 4,
}
EPOCH_S = 30
PRE_ONSET_S = 30 * 60
CAL_MAX = 20  # 10 min of leading W; keeps the 15 min pre-onset window scoreable


def epoch_stages(onsets: np.ndarray, durations: np.ndarray, desc: list[str], n_epochs: int) -> np.ndarray:
    """Hypnogram annotations -> per-30 s-epoch stage codes (-1 = unscored / movement)."""
    st = np.full(n_epochs, -1, dtype=np.int8)
    for o, d, s in zip(onsets, durations, desc):
        code = STAGE_MAP.get(s, -1)
        a = int(round(o / EPOCH_S))
        b = int(round((o + d) / EPOCH_S))
        st[max(a, 0) : min(b, n_epochs)] = code
    return st


def w_context(stage: np.ndarray, t_rel: np.ndarray) -> np.ndarray:
    ctx = np.full(stage.size, "-", dtype=object)
    w = stage == 0
    ctx[w & (t_rel < 0) & (t_rel >= -15 * 60)] = "pre_onset"
    ctx[w & (t_rel < -15 * 60)] = "early"
    ctx[w & (t_rel >= 0)] = "waso"
    return ctx


def leading_cal(stage: np.ndarray, cal_max: int = CAL_MAX, min_rows: int = 5) -> int:
    n = 0
    while n < stage.size and stage[n] == 0:
        n += 1
    return min(n, cal_max) if n >= min_rows else 0


def process_recording(psg: Path, hyp: Path) -> dict[str, np.ndarray] | None:
    import mne  # noqa: PLC0415

    raw = mne.io.read_raw_edf(psg, verbose="error")
    ann = mne.read_annotations(hyp)
    sr = raw.info["sfreq"]
    if int(round(sr)) != 100:
        return None
    n_ep = int(raw.n_times // (EPOCH_S * sr))
    st = epoch_stages(ann.onset, ann.duration, list(ann.description), n_ep)
    sleep = np.flatnonzero(st > 0)
    if sleep.size == 0:
        return None
    first, last = int(sleep[0]), int(sleep[-1])
    lo = max(0, first - PRE_ONSET_S // EPOCH_S)
    keep = np.arange(lo, last + 1)
    keep = keep[st[keep] >= 0]
    picks = {"fpz_cz": "EEG Fpz-Cz", "pz_oz": "EEG Pz-Oz", "eog": "EOG horizontal"}
    data = raw.get_data(picks=list(picks.values()), start=int(lo * EPOCH_S * sr),
                        stop=int((last + 1) * EPOCH_S * sr)) * 1e6  # V -> uV
    nper = int(EPOCH_S * sr)
    ep = data[:, : (last + 1 - lo) * nper].reshape(3, last + 1 - lo, nper)
    rows = keep - lo
    psd = psd_1hz(ep[:, rows, :], sr)  # (3, n, 45)
    out = {
        "stage": st[keep].astype(np.int8),
        "psd_fpz_cz": psd[0].astype(np.float32),
        "psd_pz_oz": psd[1].astype(np.float32),
        "eog_lf": band_from_psd(psd[2], (1.0, 4.0)),
        "t_rel_onset_s": ((keep - first) * EPOCH_S).astype(np.float64),
    }
    if "EMG submental" in raw.ch_names:
        e = raw.get_data(picks=["EMG submental"]) * 1e6
        esr = raw._raw_extras[0]["n_samps"][raw.ch_names.index("EMG submental")] / raw._raw_extras[0]["record_length"][0]
        esr = float(esr)
        per = int(round(EPOCH_S * sr))
        # get_data resamples every channel to the max rate; average per epoch
        ee = e[0, : n_ep * per].reshape(n_ep, per)
        out["emg_env"] = np.abs(ee[keep]).mean(axis=1)
        out["_emg_native_hz"] = np.array([esr])
    else:
        out["emg_env"] = np.full(keep.size, np.nan)
    return out


def find_pairs(raw_dir: Path) -> list[tuple[str, Path, Path]]:
    psg = sorted(raw_dir.glob("*-PSG.edf"))
    hyps = {p.name[:6]: p for p in raw_dir.glob("*-Hypnogram.edf")}
    out = []
    for p in psg:
        rid = p.name[:6]
        if rid in hyps:
            out.append((rid, p, hyps[rid]))
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw-dir", type=Path, default=DEFAULT_RAW)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--max-recordings", type=int, default=0)
    ap.add_argument("--only", default="", help="regex on recording id (e.g. '^SC4|^ST7')")
    a = ap.parse_args(argv)

    pairs = find_pairs(a.raw_dir)
    if a.only:
        pairs = [p for p in pairs if re.search(a.only, p[0])]
    if a.max_recordings:
        pairs = pairs[: a.max_recordings]
    cols: dict[str, list[np.ndarray]] = {}
    used, skipped = [], []
    for rid, psg, hyp in pairs:
        try:
            r = process_recording(psg, hyp)
        except Exception as e:  # noqa: BLE001
            skipped.append(f"{rid}:{type(e).__name__}")
            continue
        if r is None:
            skipped.append(f"{rid}:no_sleep_or_rate")
            continue
        r.pop("_emg_native_hz", None)
        n = r["stage"].size
        r["recording_id"] = np.full(n, rid, dtype=object)
        r["w_context"] = w_context(r["stage"], r["t_rel_onset_s"])
        for k, v in r.items():
            cols.setdefault(k, []).append(v)
        used.append(rid)
        print(rid, n, np.bincount(r["stage"], minlength=5).tolist(), flush=True)
    arr = {k: np.concatenate(v) for k, v in cols.items()}
    arr["recording_id"] = arr["recording_id"].astype(object)
    arr["w_context"] = arr["w_context"].astype(object)
    # gym-schema columns (Fpz-Cz, app edges) so load_corpus / build_cal_plan work
    psd = arr["psd_fpz_cz"].astype(np.float64)
    b = {k: band_from_psd(psd, v) for k, v in APP_BANDS.items()}
    tot = sum(b.values())
    for k in ("delta", "theta", "alpha", "beta"):
        arr[f"{k}_rel"] = np.where(tot > 0, b[k] / tot, 0.0)
    arr["labels"] = (arr["stage"] > 0).astype(np.int32)
    rid = arr["recording_id"]
    starts, lens = [], []
    for r in used:
        idx = np.flatnonzero(rid == r)
        starts.append(int(idx[0]))
        lens.append(leading_cal(arr["stage"][idx]))
    arr["cal_starts"] = np.asarray(starts, dtype=np.int32)
    arr["cal_lens"] = np.asarray(lens, dtype=np.int32)
    arr["cal_n"] = np.array([CAL_MAX], dtype=np.int32)
    arr["psd_freqs"] = np.arange(1, 46, dtype=np.float64)
    arr["label_names"] = np.array(["wake", "sleep_any"])
    arr["stage_names"] = np.array(["W", "N1", "N2", "N3", "REM"])
    arr["corpus_id"] = np.array("sleep_edf_stages")
    arr["cal_policy"] = np.array("per recording: leading W epochs (30 s rows), <= 20 rows")
    arr["recordings_used"] = np.array(used, dtype=object)
    arr["recordings_skipped"] = np.array(skipped, dtype=object)
    a.out.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(a.out, **arr)
    print(f"wrote {a.out}: {arr['stage'].size} epochs, {len(used)} recordings, skipped {skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
