#!/usr/bin/env python3
"""Build feedback_gym NPZ from Sleep-EDF vigilance windows + CBraMod emb_cache.

Uses linear heads from neurofeed assets (no encoder forward / no torch).
Optionally merges REVE subsample emb_cache (512-d) into ai_*_reve columns
(NaN-padded onto the CBraMod-aligned stream; Diggus: not fair vs full encode).
Band columns via muse-eeg-heads band_math.features.flutter_bands.

Labels: windows `y` (0=drowsy/wake-ish binary negative, 1=hypnagogic) —
same as emb `y_a`. Documented in NPZ `label_names` and README.

Windows are aligned to emb_cache via the same light QC + wake/light stage
keep mask used when embeddings were built (mismatched raw lengths are normal).

Calibration (default ``--cal-mode per-recording``): each recording gets its
own baseline = its leading wake (label 0) run, capped at ``cal_n`` rows
(default 90 rows = 45 s at the 0.5 s window hop, the app's single-baseline
length). Written as ``cal_starts`` / ``cal_lens``; cal rows are never scored.
A recording that starts in N1 (fewer than ``min_cal_rows`` leading wake rows)
gets ``cal_len 0`` and is not scored. ``--cal-mode global`` restores the old
behaviour (first ``cal_n`` rows of the concatenated stream = one recording's
baseline for all 20 recordings). ``--from-npz`` adds per-recording cal to an
existing NPZ without the windows.

Gym-only extra columns (``--extra-columns``, default on), for the fair
band-math audit (FAIR_BANDMATH.md); the app is unchanged:

- ``app_*``: the app's current band math (``runners/app_bands.py``: Hamming,
  PSD, half-open bands, gamma 30-45) on the same AF7/AF8 (= Fpz-Cz) pads.
- ``post_*``: flutter_bands math on the TP9/TP10 slots, which hold the Pz-Oz
  posterior proxy here. Sleep-EDF has no Muse electrodes; this shows how much
  of band math's sleep-onset gap is the frontal-only derivation.
"""

from __future__ import annotations

import argparse
import json
import sys
import warnings
from pathlib import Path
from typing import Any

import numpy as np

GYM_ROOT = Path(__file__).resolve().parent.parent
if str(GYM_ROOT) not in sys.path:  # `python3 runners/build_corpus_sleep_edf.py`
    sys.path.insert(0, str(GYM_ROOT))
REPO_ROOT = GYM_ROOT.parent

DEFAULT_WINDOWS = Path(
    "/workspace/muse-eeg-heads/kaggle_datasets/muse-eeg-heads-windows"
    "/vigilance_sleep_edf/windows"
)
DEFAULT_SPLITS = Path(
    "/workspace/muse-eeg-heads/kaggle_datasets/muse-eeg-heads-windows"
    "/vigilance_sleep_edf/splits/test_subjects.json"
)
DEFAULT_EMB = Path(
    "/workspace/muse-eeg-heads/exports/head_c_full_corpus/emb_cache"
)
DEFAULT_HEAD_A = (
    REPO_ROOT / "assets/packs/cbramod-a-vig-full/heads/head_a_vig_linear.f32bin"
)
DEFAULT_HEAD_C = (
    REPO_ROOT
    / "assets/packs/cbramod-a-vig-full/heads/head_c_wake_light_linear.f32bin"
)
DEFAULT_OUT = GYM_ROOT / "corpora/external/sleep_edf_test.npz"
DEFAULT_REVE_EMB = Path(
    "/workspace/muse-eeg-heads/exports/reve_sleep_heads_local/emb_cache"
)
DEFAULT_REVE_HEAD_A = (
    REPO_ROOT
    / "assets/packs/reve-a-vig-subsample/heads/head_a_vig_reve_linear.f32bin"
)
DEFAULT_REVE_HEAD_C = (
    REPO_ROOT
    / "assets/packs/reve-head-c-wake-light-subsample/heads/"
    "head_c_wake_light_reve_linear.f32bin"
)
DEFAULT_REVE_POLICY = Path(
    "/workspace/muse-eeg-heads/kaggle_datasets/muse-eeg-heads-windows"
    "/vigilance_sleep_edf/splits/split_policy.json"
)
DEFAULT_REVE_SPLITS_DIR = Path(
    "/workspace/muse-eeg-heads/kaggle_datasets/muse-eeg-heads-windows"
    "/vigilance_sleep_edf/splits"
)
DEFAULT_REVE_WINDOWS = DEFAULT_WINDOWS
MIN_CAL_ROWS = 30  # 15 s at 0.5 s hop; fewer leading wake rows -> no baseline
REVE_SEED = 42  # must match muse-eeg-heads train_heads_reve_sleep_local.SEED
BAND_MATH_CANDIDATES = [
    Path("/workspace/muse-eeg-heads/band_math"),
    REPO_ROOT.parent / "muse-eeg-heads" / "band_math",
]


def load_linear_head(path: Path) -> tuple[np.ndarray, np.ndarray]:
    """Load f32bin head: W(2,D) row-major then bias(2).

    CBraMod D=200 → 402 floats; REVE D=512 → 1026 floats.
    Layout confirmed by class separation on Sleep-EDF emb_cache (W as (2,D)
    separates; (D,2) does not).
    """
    raw = np.fromfile(path, dtype=np.float32)
    if raw.size < 4 or (raw.size - 2) % 2 != 0:
        raise ValueError(f"unexpected f32bin size {raw.size} in {path}")
    dim = (raw.size - 2) // 2
    W = raw[: 2 * dim].reshape(2, dim)
    b = raw[2 * dim :].astype(np.float64)
    return W.astype(np.float64), b


def softmax_p_class1(emb: np.ndarray, W: np.ndarray, b: np.ndarray) -> np.ndarray:
    """P(class=1) from logits = emb @ W.T + b (2-class softmax)."""
    emb = np.asarray(emb, dtype=np.float64)
    logits = emb @ W.T + b  # (N, 2)
    logits = logits - logits.max(axis=1, keepdims=True)
    ex = np.exp(logits)
    return (ex[:, 1] / ex.sum(axis=1)).astype(np.float64)



# Match muse-eeg-heads train_heads_expanded_sleep_corpus emb_cache filters
_FLAT_STD = 0.1
_PEAK_ABS = 350.0
_HEAD_A_LABELS = ("drowsy", "hypnagogic")
_HEAD_C_ACTIVE = ("wake", "light")


def qc_pass_mask(X: np.ndarray) -> np.ndarray:
    std = X.std(axis=-1)
    peak = np.max(np.abs(X), axis=-1)
    flat = (std < _FLAT_STD).any(axis=-1)
    hot = (peak > _PEAK_ABS).any(axis=-1)
    return ~(flat | hot)


def emb_keep_indices(win: Any) -> np.ndarray:
    """Replay emb_cache keep mask so windows align with emb rows."""
    X = np.asarray(win["X"])
    y_raw = np.asarray(win["y"], dtype=np.int64)
    label_names = [str(x) for x in np.asarray(win["label_names"]).tolist()]
    stage_coarse = np.asarray(win["stage_coarse"], dtype=object)
    name_to_vig = {n: _HEAD_A_LABELS.index(n) for n in label_names if n in _HEAD_A_LABELS}
    y_a = np.full(len(y_raw), -1, dtype=np.int64)
    for old_i, name in enumerate(label_names):
        if name in name_to_vig:
            y_a[y_raw == old_i] = name_to_vig[name]
    table = {n: i for i, n in enumerate(_HEAD_C_ACTIVE)}
    keep_c = np.array([str(c) in table for c in stage_coarse], dtype=bool)
    keep = qc_pass_mask(X) & (y_a >= 0) & keep_c
    return np.where(keep)[0]

def import_flutter_bands():
    """Import compute_window_features_fast from sibling muse-eeg-heads."""
    tried: list[str] = []
    for root in BAND_MATH_CANDIDATES:
        tried.append(str(root))
        if not root.is_dir():
            continue
        if str(root) not in sys.path:
            sys.path.insert(0, str(root))
        try:
            from features.flutter_bands import (  # type: ignore
                compute_window_features_fast,
            )

            return compute_window_features_fast
        except ImportError:
            continue
    raise ImportError(
        "Could not import band_math.features.flutter_bands. "
        "Expected muse-eeg-heads sibling at one of:\n  - "
        + "\n  - ".join(tried)
        + "\nInstall/clone muse-eeg-heads next to neurofeed, or pass paths that "
        "already include precomputed band columns (not supported yet)."
    )


def _load_test_recordings(splits_path: Path) -> list[str]:
    data = json.loads(splits_path.read_text(encoding="utf-8"))
    recs = data.get("recordings")
    if not recs:
        raise ValueError(f"no recordings in {splits_path}")
    return list(recs)


def _reve_cap_idxs(y: np.ndarray, per_class: int, rng: np.random.Generator) -> np.ndarray:
    """Replay muse-eeg-heads train_heads_reve_sleep_local.cap_idxs."""
    if per_class <= 0:
        return np.arange(len(y), dtype=np.int64)
    picks = []
    for c in np.unique(y):
        cand = np.where(y == c)[0]
        n = min(per_class, len(cand))
        if n:
            picks.append(rng.choice(cand, size=n, replace=False))
    if not picks:
        return np.zeros(0, dtype=np.int64)
    out = np.concatenate(picks)
    rng.shuffle(out)
    return out


def replay_reve_subsample_locals(
    *,
    windows_dir: Path,
    policy_path: Path,
    splits_dir: Path,
    per_class_cap: int = 80,
    seed: int = REVE_SEED,
) -> dict[str, np.ndarray]:
    """Map recording_id → local indices into the QC keep set (REVE emb row order).

    Advances RNG over **all** policy recordings in sorted order (same as the
    REVE encode script) so test-set indices match the on-disk emb_cache.
    """
    if not policy_path.exists() or not splits_dir.exists():
        return {}
    policy = json.loads(policy_path.read_text(encoding="utf-8"))
    split_map: dict[str, str] = {}
    for sp in ("train", "val", "test"):
        sp_path = splits_dir / f"{sp}_subjects.json"
        if not sp_path.exists():
            continue
        for sid in json.loads(sp_path.read_text(encoding="utf-8"))["subjects"]:
            split_map[sid] = sp

    def subject_of(rid: str) -> str:
        recs = policy.get("recordings", {})
        if rid in recs:
            return recs[rid]["subject_id"]
        return rid if rid.startswith("SN") else rid[:5]

    rng = np.random.default_rng(seed)
    out: dict[str, np.ndarray] = {}
    rids = sorted(policy.get("recordings", {}).keys())
    for rid in rids:
        sid = subject_of(rid)
        if split_map.get(sid) is None:
            continue
        win_path = windows_dir / f"{rid}_windows.npz"
        if not win_path.exists():
            continue
        win = np.load(win_path, allow_pickle=True)
        try:
            idxs_keep = emb_keep_indices(win)
        except Exception:
            continue
        if len(idxs_keep) == 0:
            continue
        y_raw = np.asarray(win["y"], dtype=np.int64)
        label_names = [str(x) for x in np.asarray(win["label_names"]).tolist()]
        name_to = {n: _HEAD_A_LABELS.index(n) for n in label_names if n in _HEAD_A_LABELS}
        y_a = np.full(len(y_raw), -1, dtype=np.int64)
        for old_i, name in enumerate(label_names):
            if name in name_to:
                y_a[y_raw == old_i] = name_to[name]
        local = _reve_cap_idxs(y_a[idxs_keep], per_class_cap, rng)
        out[rid] = local.astype(np.int64)
    return out


def per_recording_cal(
    labels: np.ndarray,
    recording_id: np.ndarray,
    *,
    cal_n: int = 90,
    min_cal_rows: int = MIN_CAL_ROWS,
) -> tuple[np.ndarray, np.ndarray, list[str]]:
    """``cal_starts`` / ``cal_lens`` from each recording's leading wake run.

    One entry per unique ``recording_id`` in first-appearance order (gym
    contract). Baseline = the first ``min(cal_n, leading label-0 rows)`` rows;
    fewer than ``min_cal_rows`` leading wake rows -> ``cal_len 0`` (recording
    not scored). Returns ``(starts, lens, no_baseline_ids)``.
    """
    y = np.asarray(labels).astype(int)
    rec = np.asarray(recording_id).astype(str)
    seen: dict[str, None] = {}
    for r in rec:
        seen.setdefault(r, None)
    starts, lens, none = [], [], []
    for r in seen:
        rows = np.flatnonzero(rec == r)
        yy = y[rows]
        lead = int(np.argmax(yy != 0)) if (yy != 0).any() else int(yy.size)
        n_cal = min(int(cal_n), lead)
        if n_cal < min_cal_rows:
            n_cal = 0
            none.append(r)
        starts.append(int(rows[0]))
        lens.append(n_cal)
    return np.asarray(starts, dtype=np.int32), np.asarray(lens, dtype=np.int32), none


def add_per_recording_cal(
    arrays: dict[str, Any], *, cal_n: int = 90, min_cal_rows: int = MIN_CAL_ROWS
) -> list[str]:
    """Write ``cal_starts`` / ``cal_lens`` / ``cal_policy`` into ``arrays`` in place."""
    starts, lens, none = per_recording_cal(
        arrays["labels"], arrays["recording_id"], cal_n=cal_n, min_cal_rows=min_cal_rows
    )
    arrays["cal_starts"] = starts
    arrays["cal_lens"] = lens
    first = int(lens[0]) if lens.size and lens[0] > 0 else int(cal_n)
    arrays["cal_n"] = np.array([first], dtype=np.int32)
    arrays["cal_policy"] = np.array(
        f"per recording: leading wake (label 0) run, <= {int(cal_n)} rows "
        f"(0.5 s hop); < {int(min_cal_rows)} leading wake rows -> cal_len 0 "
        "(recording not scored)"
    )
    return none


def build_corpus(
    *,
    windows_dir: Path = DEFAULT_WINDOWS,
    splits_path: Path = DEFAULT_SPLITS,
    emb_dir: Path = DEFAULT_EMB,
    head_a_path: Path = DEFAULT_HEAD_A,
    head_c_path: Path = DEFAULT_HEAD_C,
    out_path: Path = DEFAULT_OUT,
    max_windows_per_rec: int | None = None,
    cal_n: int = 90,
    recordings: list[str] | None = None,
    reve_emb_dir: Path | None = DEFAULT_REVE_EMB,
    reve_head_a_path: Path | None = DEFAULT_REVE_HEAD_A,
    reve_head_c_path: Path | None = DEFAULT_REVE_HEAD_C,
    reve_policy_path: Path = DEFAULT_REVE_POLICY,
    reve_splits_dir: Path = DEFAULT_REVE_SPLITS_DIR,
    cal_mode: str = "per-recording",
    min_cal_rows: int = MIN_CAL_ROWS,
    extra_columns: bool = True,
) -> dict[str, Any]:
    """Build and write gym NPZ. Returns summary dict."""
    if cal_mode not in ("per-recording", "global"):
        raise ValueError(f"cal_mode must be per-recording or global, got {cal_mode!r}")
    compute_feats = import_flutter_bands()
    W_a, b_a = load_linear_head(head_a_path)
    W_c, b_c = load_linear_head(head_c_path)

    reve_enabled = False
    W_ra = b_ra = W_rc = b_rc = None
    reve_locals: dict[str, np.ndarray] = {}
    if (
        reve_emb_dir is not None
        and Path(reve_emb_dir).is_dir()
        and reve_head_a_path is not None
        and Path(reve_head_a_path).is_file()
    ):
        W_ra, b_ra = load_linear_head(Path(reve_head_a_path))
        if reve_head_c_path is not None and Path(reve_head_c_path).is_file():
            W_rc, b_rc = load_linear_head(Path(reve_head_c_path))
        reve_locals = replay_reve_subsample_locals(
            windows_dir=windows_dir,
            policy_path=reve_policy_path,
            splits_dir=reve_splits_dir,
        )
        reve_enabled = True

    if recordings is None:
        recordings = _load_test_recordings(splits_path)

    chunks: dict[str, list[np.ndarray]] = {
        "labels": [],
        "band_atr": [],
        "band_tar": [],
        "band_btr": [],
        "band_alpha": [],
        "band_delta": [],
        "delta_rel": [],
        "theta_rel": [],
        "alpha_rel": [],
        "beta_rel": [],
        "delta_abs": [],
        "ai_a_vig": [],
        "ai_wake_light": [],
        "ai_drowsiness": [],
        "recording_id": [],
    }
    if reve_enabled:
        chunks["ai_a_vig_reve"] = []
        chunks["ai_wake_light_reve"] = []
    reve_filled = 0
    reve_nan = 0
    skipped: list[str] = []
    used: list[str] = []
    n_total = 0

    for rec in recordings:
        win_path = windows_dir / f"{rec}_windows.npz"
        emb_path = emb_dir / f"{rec}_emb.npz"
        if not win_path.exists():
            warnings.warn(f"skip {rec}: missing windows {win_path}")
            skipped.append(rec)
            continue
        if not emb_path.exists():
            warnings.warn(f"skip {rec}: missing emb {emb_path}")
            skipped.append(rec)
            continue

        win = np.load(win_path, allow_pickle=True)
        emb_npz = np.load(emb_path)
        X_all = np.asarray(win["X"])
        y_all = np.asarray(win["y"], dtype=np.int32)
        emb = np.asarray(emb_npz["emb"], dtype=np.float64)

        if emb.ndim != 2 or emb.shape[1] != 200:
            warnings.warn(f"skip {rec}: emb shape {emb.shape} (want N,200)")
            skipped.append(rec)
            continue

        # Align windows to emb_cache rows (QC + stage keep); equal length → identity
        if emb.shape[0] == X_all.shape[0]:
            idxs = np.arange(X_all.shape[0])
        else:
            try:
                idxs = emb_keep_indices(win)
            except Exception as exc:  # noqa: BLE001
                warnings.warn(f"skip {rec}: align failed ({exc})")
                skipped.append(rec)
                continue
            if len(idxs) != emb.shape[0]:
                warnings.warn(
                    f"skip {rec}: aligned N={len(idxs)} != emb N={emb.shape[0]}"
                )
                skipped.append(rec)
                continue
            # sanity: labels should match emb y_a when present
            if "y_a" in emb_npz.files:
                if not np.array_equal(y_all[idxs], emb_npz["y_a"]):
                    warnings.warn(
                        f"skip {rec}: aligned y != emb y_a (index mismatch)"
                    )
                    skipped.append(rec)
                    continue

        X = X_all[idxs]
        y = y_all[idxs]
        n = X.shape[0]
        if max_windows_per_rec is not None and n > max_windows_per_rec:
            X = X[:max_windows_per_rec]
            y = y[:max_windows_per_rec]
            emb = emb[:max_windows_per_rec]
            n = max_windows_per_rec

        feats = compute_feats(X)
        p_a = softmax_p_class1(emb, W_a, b_a)
        p_c = softmax_p_class1(emb, W_c, b_c)

        chunks["labels"].append(y)
        chunks["band_atr"].append(np.asarray(feats["band.atr"], dtype=np.float64))
        chunks["band_tar"].append(np.asarray(feats["band.tar"], dtype=np.float64))
        chunks["band_btr"].append(np.asarray(feats["band.btr"], dtype=np.float64))
        chunks["band_alpha"].append(np.asarray(feats["band.alpha"], dtype=np.float64))
        # band.delta feature value = absolute delta (matches synthetic / Dart)
        chunks["band_delta"].append(np.asarray(feats["band.delta"], dtype=np.float64))
        chunks["delta_rel"].append(np.asarray(feats["rel_delta"], dtype=np.float64))
        chunks["theta_rel"].append(np.asarray(feats["rel_theta"], dtype=np.float64))
        chunks["alpha_rel"].append(np.asarray(feats["rel_alpha"], dtype=np.float64))
        chunks["beta_rel"].append(np.asarray(feats["rel_beta"], dtype=np.float64))
        chunks["delta_abs"].append(np.asarray(feats["abs_delta"], dtype=np.float64))
        chunks["ai_a_vig"].append(p_a)
        chunks["ai_wake_light"].append(p_c)
        chunks["ai_drowsiness"].append(p_a)  # alias of a_vig
        chunks["recording_id"].append(np.full(n, rec, dtype=object))

        if extra_columns:
            from runners.app_bands import app_features

            app = app_features(X, pads=(0, 1))
            post = compute_feats(np.ascontiguousarray(X[:, 2:4, :]))
            for key, src in (
                ("band_atr", "band.atr"),
                ("band_tar", "band.tar"),
                ("band_btr", "band.btr"),
                ("band_alpha", "band.alpha"),
                ("band_delta", "band.delta"),
                ("delta_rel", "rel_delta"),
                ("theta_rel", "rel_theta"),
                ("alpha_rel", "rel_alpha"),
                ("beta_rel", "rel_beta"),
            ):
                chunks.setdefault(f"app_{key}", []).append(
                    np.asarray(app[src], dtype=np.float64)
                )
                if src in post:
                    chunks.setdefault(f"post_{key}", []).append(
                        np.asarray(post[src], dtype=np.float64)
                    )

        if reve_enabled:
            col_a = np.full(n, np.nan, dtype=np.float64)
            col_c = np.full(n, np.nan, dtype=np.float64)
            reve_path = Path(reve_emb_dir) / f"{rec}_emb.npz"
            local = reve_locals.get(rec)
            if reve_path.exists() and local is not None and W_ra is not None:
                rz = np.load(reve_path)
                remb = np.asarray(rz["emb"], dtype=np.float64)
                if remb.ndim == 2 and remb.shape[0] == len(local) and remb.shape[1] == W_ra.shape[1]:
                    p_ra = softmax_p_class1(remb, W_ra, b_ra)
                    p_rc = (
                        softmax_p_class1(remb, W_rc, b_rc)
                        if W_rc is not None
                        else np.full(len(local), np.nan)
                    )
                    for i, pos in enumerate(local):
                        if 0 <= int(pos) < n:
                            col_a[int(pos)] = p_ra[i]
                            col_c[int(pos)] = p_rc[i]
                    reve_filled += int(np.isfinite(col_a).sum())
                    reve_nan += int((~np.isfinite(col_a)).sum())
                else:
                    warnings.warn(
                        f"REVE skip {rec}: emb shape {remb.shape} vs local {len(local)} "
                        f"dim {None if W_ra is None else W_ra.shape[1]}"
                    )
                    reve_nan += n
            else:
                reve_nan += n
            chunks["ai_a_vig_reve"].append(col_a)
            chunks["ai_wake_light_reve"].append(col_c)

        used.append(rec)
        n_total += n

    if n_total == 0:
        raise RuntimeError(
            "no recordings built; check windows/emb paths and skips: "
            + ", ".join(skipped)
        )

    cal_n_eff = min(int(cal_n), n_total)
    arrays: dict[str, Any] = {
        "cal_n": np.array([cal_n_eff], dtype=np.int32),
        "label_names": np.array(["drowsy", "hypnagogic"]),
        "cal_policy": np.array(
            "stream_head_first_cal_n; Sleep-EDF often starts wake/low-y"
        ),
        "corpus_id": np.array("sleep_edf_test"),
        "recordings_used": np.array(used, dtype=object),
        "recordings_skipped": np.array(skipped, dtype=object),
    }
    for key, parts in chunks.items():
        if key == "recording_id":
            arrays[key] = np.concatenate(parts)
        elif key == "labels":
            arrays[key] = np.concatenate(parts).astype(np.int32)
        else:
            arrays[key] = np.concatenate(parts).astype(np.float64)

    no_baseline: list[str] = []
    if cal_mode == "per-recording":
        no_baseline = add_per_recording_cal(arrays, cal_n=cal_n, min_cal_rows=min_cal_rows)

    # REVE: subsample-aligned into NaN-padded columns when emb+heads present
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(out_path, **arrays)

    # Quick sep sanity for heads
    labels = arrays["labels"]
    sep_a = float(
        arrays["ai_a_vig"][labels == 1].mean() - arrays["ai_a_vig"][labels == 0].mean()
    ) if (labels == 1).any() and (labels == 0).any() else float("nan")
    sep_c = float(
        arrays["ai_wake_light"][labels == 1].mean()
        - arrays["ai_wake_light"][labels == 0].mean()
    ) if (labels == 1).any() and (labels == 0).any() else float("nan")

    summary = {
        "out": str(out_path),
        "n": n_total,
        "cal_n": cal_n_eff,
        "cal_mode": cal_mode,
        "recordings_without_baseline": no_baseline,
        "recordings_used": used,
        "recordings_skipped": skipped,
        "ai_a_vig_mean_sep": sep_a,
        "ai_wake_light_mean_sep": sep_c,
        "reve_enabled": reve_enabled,
        "reve_finite": reve_filled,
        "reve_nan": reve_nan,
        "bytes": out_path.stat().st_size,
        "notes": (
            "REVE sleep emb is a per-class subsample (≤80/class/rec, seed=42); "
            "scores are NaN-padded onto the CBraMod-aligned stream."
            if reve_enabled
            else "REVE columns omitted (emb/heads missing)."
        ),
    }
    if reve_enabled and "ai_a_vig_reve" in arrays:
        rv = arrays["ai_a_vig_reve"]
        mask = np.isfinite(rv)
        if mask.any() and (labels[mask] == 1).any() and (labels[mask] == 0).any():
            summary["ai_a_vig_reve_mean_sep"] = float(
                rv[mask & (labels == 1)].mean() - rv[mask & (labels == 0)].mean()
            )
    return summary


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--windows-dir", type=Path, default=DEFAULT_WINDOWS)
    p.add_argument("--splits", type=Path, default=DEFAULT_SPLITS)
    p.add_argument("--emb-dir", type=Path, default=DEFAULT_EMB)
    p.add_argument("--head-a", type=Path, default=DEFAULT_HEAD_A)
    p.add_argument("--head-c", type=Path, default=DEFAULT_HEAD_C)
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p.add_argument(
        "--max-windows-per-rec",
        type=int,
        default=None,
        help="cap windows per recording (faster CI); default = full test",
    )
    p.add_argument("--cal-n", type=int, default=90)
    p.add_argument("--reve-emb-dir", type=Path, default=DEFAULT_REVE_EMB)
    p.add_argument("--reve-head-a", type=Path, default=DEFAULT_REVE_HEAD_A)
    p.add_argument("--reve-head-c", type=Path, default=DEFAULT_REVE_HEAD_C)
    p.add_argument(
        "--cal-mode",
        choices=("per-recording", "global"),
        default="per-recording",
        help="per-recording (default): leading wake run of each recording, <= --cal-n rows; "
        "global: first --cal-n rows of the whole stream (legacy)",
    )
    p.add_argument("--min-cal-rows", type=int, default=MIN_CAL_ROWS)
    p.add_argument(
        "--no-extra-columns",
        action="store_true",
        help="skip gym-only app_* / post_* band columns",
    )
    p.add_argument(
        "--from-npz",
        type=Path,
        default=None,
        help="post-process an existing NPZ: add per-recording cal_starts/cal_lens, write --out",
    )
    p.add_argument(
        "--no-reve",
        action="store_true",
        help="skip optional REVE emb_cache merge",
    )
    args = p.parse_args(argv)

    if args.from_npz is not None:
        data = np.load(args.from_npz, allow_pickle=True)
        arrays = {k: data[k] for k in data.files}
        none = add_per_recording_cal(arrays, cal_n=args.cal_n, min_cal_rows=args.min_cal_rows)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(args.out, **arrays)
        print(json.dumps({"out": str(args.out), "recordings_without_baseline": none,
                          "cal_lens": arrays["cal_lens"].tolist()}, indent=2))
        return 0

    summary = build_corpus(
        windows_dir=args.windows_dir,
        splits_path=args.splits,
        emb_dir=args.emb_dir,
        head_a_path=args.head_a,
        head_c_path=args.head_c,
        out_path=args.out,
        max_windows_per_rec=args.max_windows_per_rec,
        cal_n=args.cal_n,
        reve_emb_dir=None if args.no_reve else args.reve_emb_dir,
        reve_head_a_path=None if args.no_reve else args.reve_head_a,
        reve_head_c_path=None if args.no_reve else args.reve_head_c,
        cal_mode=args.cal_mode,
        min_cal_rows=args.min_cal_rows,
        extra_columns=not args.no_extra_columns,
    )
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
