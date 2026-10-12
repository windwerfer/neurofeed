#!/usr/bin/env python3
"""Literature claims -> feedback_gym tests (LITERATURE_CHECKS.md).

Each ``Check`` turns one graded literature claim into a within-unit contrast on a
gym corpus: rows of condition 0 vs condition 1 inside the same recording /
subject, one feature, an expected direction fixed **before** scoring
(+1: higher in condition 1, -1: lower, 0: literature expects no difference).

Per unit (recording, or subject when sessions are pooled) we compute the
directional AUC P(feature | cond 1 > feature | cond 0) on the unit's rows
(features z-scored within each recording first, so pooling sessions removes
session offsets). Reported: median per-unit AUC in the expected direction
(``auc_exp`` = AUC if expected +1, 1 - AUC if -1), IQR, the fraction of units
whose AUC points the expected way, a two-sided sign test over units, pooled
AUC, and a verdict:

- ``confirmed``: sign test p < 0.05 in the expected direction and median
  ``auc_exp`` >= 0.55
- ``contradicted``: sign test p < 0.05 in the opposite direction
- ``weak``: expected direction (median auc_exp > 0.5, frac > 0.5) but not significant
- ``null``: neither (for expected-0 claims ``null`` = consistent with the claim)

Corpora (all gitignored NPZs under ``corpora/external/``; aggregates only leave):

- ``sleep_edf_stages.npz`` (``runners/build_sleep_edf_stages.py``): all stages,
  30 s epochs, PSD for Fpz-Cz / Pz-Oz.
- ``lee2026_eo_ec.npz``, ``lee2026_artifacts.npz``, ``universe_stress.npz``
  (neurofeed-gym-corpora builders; ``--pad-mix`` columns ``ch_<pad>_<band>`` +
  ``ch_<pad>_q``): Muse features per pad, ungated and app-gated (pads with app
  quality >= 80, as the app does live; ``pad_mix_round.Q_USABLE``).
- ``ds001787_mw_{muse,crown}.npz``, ``ds003969_medthink_{muse,crown}.npz``
  (neurofeed-gym-corpora ``builders/build_openneuro_meditation.py``): PSD per site.
- ``universe_hrv.npz`` (optional, ``builders/build_universe_hrv.py``): E4 PPG HRV.

Usage::

    cd feedback_gym && python3 runners/literature_checks.py [--out-dir results/<ts>_litcheck]
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

import numpy as np

GYM_ROOT = Path(__file__).resolve().parent.parent
if str(GYM_ROOT) not in sys.path:
    sys.path.insert(0, str(GYM_ROOT))

from runners.helpers import build_cal_plan, roc_auc_up  # noqa: E402
from runners.spectral import feature_table  # noqa: E402

Q_USABLE = 80.0  # app pad-quality gate (pad_mix_round.Q_USABLE)
MUSE_PADS = ("af7", "af8", "tp9", "tp10")
BANDS5 = ("delta", "theta", "alpha", "beta", "gamma")
MIN_ROWS = 8  # per condition per unit


# --- statistics ---------------------------------------------------------------------


def sign_test_p(k: int, n: int) -> float:
    """Two-sided exact binomial (p = 0.5) for k successes of n."""
    if n == 0:
        return 1.0
    lo = min(k, n - k)
    tail = sum(math.comb(n, i) for i in range(lo + 1)) / 2.0**n
    return min(1.0, 2.0 * tail)


def robust_z(x: np.ndarray, groups: np.ndarray) -> np.ndarray:
    """Median/IQR z-score of ``x`` within each group (NaN-safe)."""
    out = np.full(x.shape, np.nan)
    for g in np.unique(groups):
        m = groups == g
        v = x[m]
        f = np.isfinite(v)
        if f.sum() < 4:
            continue
        med = np.median(v[f])
        q75, q25 = np.percentile(v[f], [75, 25])
        s = q75 - q25
        if not s > 0:
            s = np.std(v[f]) or 1.0
        out[m] = (v - med) / s
    return out


def contrast_stats(
    x: np.ndarray, rec: np.ndarray, unit: np.ndarray, m0: np.ndarray, m1: np.ndarray, expected: int
) -> dict[str, Any]:
    """Within-unit directional AUCs + sign test. ``expected`` in {+1, -1, 0}."""
    x = np.asarray(x, dtype=float)
    z = robust_z(x, rec)
    aucs: dict[str, float] = {}
    deltas: list[float] = []
    cover = []
    for u in np.unique(unit[m0 | m1]):
        mu = unit == u
        a0 = mu & m0 & np.isfinite(z)
        a1 = mu & m1 & np.isfinite(z)
        cover.append((a0.sum() + a1.sum()) / max(1, (mu & (m0 | m1)).sum()))
        if a0.sum() < MIN_ROWS or a1.sum() < MIN_ROWS:
            continue
        s = np.concatenate([z[a0], z[a1]])
        y = np.concatenate([np.zeros(a0.sum(), int), np.ones(a1.sum(), int)])
        a = roc_auc_up(s, y)
        if a is None:
            continue
        aucs[str(u)] = a
        deltas.append(float(np.median(z[a1]) - np.median(z[a0])))
    v = np.array(list(aucs.values()))
    n = int(v.size)
    out: dict[str, Any] = {"n_units": n, "coverage": float(np.mean(cover)) if cover else None}
    if n == 0:
        out.update(verdict="untestable")
        return out
    up = int((v > 0.5).sum())
    down = int((v < 0.5).sum())
    p = sign_test_p(up, up + down)
    sgn = expected if expected != 0 else (1 if np.median(v) >= 0.5 else -1)
    auc_exp = v if sgn > 0 else 1.0 - v
    frac = float((auc_exp > 0.5).mean())
    # pooled (rows from all units, within-recording z) AUC
    mm = (m0 | m1) & np.isfinite(z)
    pooled = roc_auc_up(z[mm], m1[mm].astype(int))
    out.update(
        auc_median=float(np.median(v)),
        auc_q25=float(np.percentile(v, 25)),
        auc_q75=float(np.percentile(v, 75)),
        auc_exp_median=float(np.median(auc_exp)),
        frac_expected=frac,
        units_up=up,
        units_down=down,
        sign_p=p,
        pooled_auc=pooled,
        median_dz=float(np.median(deltas)),
    )
    med_exp = float(np.median(auc_exp))
    if expected == 0:
        out["verdict"] = "null" if p >= 0.05 else ("effect_up" if up > down else "effect_down")
    else:
        if p < 0.05 and med_exp >= 0.55 and frac > 0.5:
            out["verdict"] = "confirmed"
        elif p < 0.05 and frac < 0.5:
            out["verdict"] = "contradicted"
        elif med_exp > 0.5 and frac > 0.5:
            out["verdict"] = "weak"
        else:
            out["verdict"] = "null"
    return out


# --- feature resolution -------------------------------------------------------------


class Corpus:
    """A loaded NPZ + cached derived features."""

    def __init__(self, name: str, path: Path):
        self.name = name
        self.path = path
        z = np.load(path, allow_pickle=True)
        self.d: dict[str, Any] = {k: z[k] for k in z.files}
        self._psd_cache: dict[str, dict[str, np.ndarray]] = {}
        self.n = len(self.d["labels"])
        play = np.ones(self.n, dtype=bool)
        if "cal_starts" in self.d:
            try:
                plan = build_cal_plan({**self.d, "cal_n": int(np.asarray(self.d.get("cal_n", [90]))[0])})
                play = np.zeros(self.n, dtype=bool)
                play[plan.play_idx] = True
            except Exception:  # noqa: BLE001
                pass
        self.play = play  # cal rows are never scored
        self.rec = np.asarray(self.d["recording_id"]).astype(str)

    def col(self, key: str) -> np.ndarray:
        return np.asarray(self.d[key])

    def has(self, key: str) -> bool:
        return key in self.d

    def psd_features(self, site: str) -> dict[str, np.ndarray]:
        if site not in self._psd_cache:
            self._psd_cache[site] = feature_table(np.asarray(self.d[f"psd_{site}"], dtype=np.float64))
        return self._psd_cache[site]

    def feature(self, spec: str) -> np.ndarray | None:
        """``psd:<site>:<feat>``, ``mu:<pads>:<feat>[:gate]`` (Muse per-pad bands), ``col:<key>``."""
        kind, rest = spec.split(":", 1)
        if kind == "col":
            return np.asarray(self.d[rest], dtype=float) if rest in self.d else None
        if kind == "psd":
            site, feat = rest.split(":", 1)
            if f"psd_{site}" not in self.d:
                return None
            if "+" in feat:  # mean of two sites handled by caller
                return None
            return self.psd_features(site).get(feat)
        if kind == "psd2":  # psd2:<siteA>,<siteB>:<feat> = mean over sites
            sites, feat = rest.split(":", 1)
            vals = [self.feature(f"psd:{s}:{feat}") for s in sites.split(",")]
            if any(v is None for v in vals):
                return None
            return np.nanmean(np.stack(vals), axis=0)
        if kind == "mu":
            parts = rest.split(":")
            pads, feat = parts[0], parts[1]
            gate = len(parts) > 2 and parts[2] == "gate"
            return muse_feature(self.d, pads, feat, gate)
        raise KeyError(spec)


def _pad_bands(d: dict[str, Any], pad: str) -> np.ndarray | None:
    keys = [f"ch_{pad}_{b}" for b in BANDS5]
    if not all(k in d for k in keys):
        return None
    return np.stack([np.asarray(d[k], dtype=float) for k in keys], axis=-1)


def _ratio_feats(b: np.ndarray, rel: np.ndarray) -> dict[str, np.ndarray]:
    eps = 1e-12
    with np.errstate(divide="ignore", invalid="ignore"):
        return {
            **{f"rel_{n}": rel[:, i] for i, n in enumerate(BANDS5)},
            **{f"log_{n}": np.log10(np.maximum(b[:, i], eps)) for i, n in enumerate(BANDS5)},
            "atr": rel[:, 2] / rel[:, 1],
            "tar": rel[:, 1] / rel[:, 2],
            "btr": rel[:, 3] / rel[:, 1],
            "tbr": rel[:, 1] / rel[:, 3],
            "tab": (rel[:, 1] + rel[:, 2]) / rel[:, 3],
            "engagement": rel[:, 3] / (rel[:, 2] + rel[:, 1]),
            "gamma_over_at": rel[:, 4] / (rel[:, 2] + rel[:, 1]),
        }


def muse_feature(d: dict[str, Any], pads: str, feat: str, gate: bool) -> np.ndarray | None:
    """Per-pad Muse features from ``ch_<pad>_<band>`` (flutter math, gamma 30-50).

    ``pads``: ``af7``, ``af`` (AF7+AF8), ``tp`` (TP9+TP10), ``all4``. Multi-pad =
    mean of per-pad relative bands (app features.rs) and of absolute bands.
    ``gate``: drop pads with app quality < 80 per row (NaN when no pad left),
    which is what the app does live.
    """
    names = {"af": ("af7", "af8"), "tp": ("tp9", "tp10"), "all4": MUSE_PADS}.get(pads, (pads,))
    B, R, W = [], [], []
    for p in names:
        b = _pad_bands(d, p)
        if b is None:
            return None
        tot = b.sum(axis=-1, keepdims=True)
        with np.errstate(divide="ignore", invalid="ignore"):
            r = np.where(tot > 0, b / tot, np.nan)
        w = np.ones(b.shape[0])
        if gate:
            q = d.get(f"ch_{p}_q")
            if q is None:
                return None
            w = (np.asarray(q, dtype=float) >= Q_USABLE).astype(float)
        B.append(b)
        R.append(r)
        W.append(w)
    W_ = np.stack(W)[..., None]
    den = W_.sum(axis=0)
    with np.errstate(divide="ignore", invalid="ignore"):
        b = np.where(den > 0, (np.stack(B) * W_).sum(axis=0) / den, np.nan)
        r = np.where(den > 0, (np.nan_to_num(np.stack(R)) * W_).sum(axis=0) / den, np.nan)
    return _ratio_feats(b, r).get(feat)


# --- contrasts ----------------------------------------------------------------------

Contrast = Callable[[Corpus], tuple[np.ndarray, np.ndarray, np.ndarray]]  # m0, m1, unit


def _sleep(c0: tuple[int, ...], c1: tuple[int, ...], wctx: tuple[str, ...] | None = None) -> Contrast:
    def f(c: Corpus):
        st = c.col("stage").astype(int)
        m0 = np.isin(st, c0)
        if wctx is not None and 0 in c0:
            m0 &= np.isin(c.col("w_context").astype(str), wctx) | (st != 0)
        m1 = np.isin(st, c1)
        return m0, m1, c.rec

    return f


def _sleep_loweog(c0, c1, wctx=None):
    """Like _sleep but keeps only epochs whose horizontal-EOG 1-4 Hz power is below the
    recording's median wake EOG power (removes eye-movement-dominated epochs)."""
    base = _sleep(c0, c1, wctx)

    def f(c: Corpus):
        m0, m1, u = base(c)
        eog = c.col("eog_lf").astype(float)
        st = c.col("stage").astype(int)
        ok = np.zeros(c.n, dtype=bool)
        for r in np.unique(c.rec):
            idx = c.rec == r
            w = idx & (st == 0)
            if w.sum() < 5:
                continue
            ok[idx] = eog[idx] <= np.nanmedian(eog[w])
        return m0 & ok, m1 & ok, u

    return f


def _label(sub: Callable[[Corpus], np.ndarray] | None = None, unit: str = "rec") -> Contrast:
    def f(c: Corpus):
        y = c.col("labels").astype(int)
        keep = c.play.copy()
        if sub is not None:
            keep &= sub(c)
        u = c.rec if unit == "rec" else np.array([r.rsplit("/", 1)[0] if "/ses-" in r else r for r in c.rec])
        return keep & (y == 0), keep & (y == 1), u

    return f


def _segments(s0: tuple[str, ...], s1: tuple[str, ...], sub: Callable[[Corpus], np.ndarray] | None = None) -> Contrast:
    def f(c: Corpus):
        seg = c.col("segment").astype(str)
        keep = c.play.copy()
        if sub is not None:
            keep &= sub(c)
        m0 = keep & np.array([any(s.endswith(x) or s.startswith(x) or f"/{x}" in s for x in s0) for s in seg])
        m1 = keep & np.array([any(s.endswith(x) or s.startswith(x) or f"/{x}" in s for x in s1) for s in seg])
        return m0, m1, c.rec

    return f


def _group(*g: str) -> Callable[[Corpus], np.ndarray]:
    return lambda c: np.isin(c.col("group").astype(str), g)


def _task(t: str) -> Callable[[Corpus], np.ndarray]:
    return lambda c: np.array([r.endswith("/" + t) for r in c.rec])


def _ds003969_think_vs_med(blocks0: tuple[str, ...], blocks1: tuple[str, ...], groups: tuple[str, ...] | None = None) -> Contrast:
    def f(c: Corpus):
        seg = np.array([s.split("/")[0] for s in c.col("segment").astype(str)])
        keep = c.play.copy()
        if groups is not None:
            keep &= np.isin(c.col("group").astype(str), groups)
        return keep & np.isin(seg, blocks0), keep & np.isin(seg, blocks1), c.rec

    return f


# --- checks registry ----------------------------------------------------------------


@dataclass
class Check:
    id: str
    claim: str
    source: str  # literature key(s) + grade
    grade: str  # Strong / Moderate / Weak-Mixed / Contradicted
    kind: str  # anchor / claim / null
    corpus: str
    contrast_note: str
    contrast: Contrast
    feature: str
    expected: int
    lanes: str = ""
    dt: str = "D"  # D = detection evidence; T = training efficacy
    tags: tuple[str, ...] = field(default_factory=tuple)


S_W, S_N1, S_N2, S_N3, S_R = 0, 1, 2, 3, 4
PRE = ("pre_onset",)


def registry() -> list[Check]:
    C: list[Check] = []
    add = C.append
    # ---------------- Sleep-EDF anchors (W vs sleep) ------------------------------------
    for site, sname in (("pz_oz", "Pz-Oz (posterior)"), ("fpz_cz", "Fpz-Cz (frontal, Muse-like)")):
        add(Check(f"sleep.alpha_drop.{site}", "Alpha share drops at sleep onset (EC wake -> N1)", "AASM; Hori1994 [Strong]", "Strong",
                  "anchor", "sleep_edf_stages", "W (15 min before onset) vs N1", _sleep((S_W,), (S_N1,), PRE),
                  f"psd:{site}:rel_alpha", -1, "sleepGuard, restAwake", tags=(sname,)))
        add(Check(f"sleep.alpha_drop_allW.{site}", "Alpha share drops at sleep onset (all wake)", "AASM [Strong]; EO caveat Torsvall1987", "Strong",
                  "anchor", "sleep_edf_stages", "all W vs N1", _sleep((S_W,), (S_N1,)),
                  f"psd:{site}:rel_alpha", -1, "sleepGuard", tags=(sname,)))
        add(Check(f"sleep.theta_up.{site}", "Relative theta rises at sleep onset", "AASM [Strong]; Strijkstra2003 [Moderate]", "Strong",
                  "anchor", "sleep_edf_stages", "W (pre-onset) vs N1", _sleep((S_W,), (S_N1,), PRE),
                  f"psd:{site}:rel_theta", +1, "sleepGuard, alertOpen", tags=(sname,)))
        for feat, lab, exp in (("entropy_1_30", "Spectral entropy (1-30 Hz) lower", -1),
                               ("sef95", "SEF95 (1-30 Hz) lower", -1),
                               ("slope_2_40", "Aperiodic slope 2-40 Hz steeper", -1),
                               ("slope_30_45", "Aperiodic slope 30-45 Hz steeper (Lendner)", -1)):
            for c1, cn in ((S_N1, "N1"), (S_N2, "N2")):
                add(Check(f"sleep.{feat}.{cn}.{site}", f"{lab} in {cn} than wake",
                          "Rampil1998/Viertio2004 (anaesthesia) [Strong]" if feat != "slope_2_40" and "slope" not in feat else "Lendner2020 [Moderate]",
                          "Strong" if "slope" not in feat else "Moderate", "anchor", "sleep_edf_stages", f"W (pre-onset) vs {cn}",
                          _sleep((S_W,), (c1,), PRE), f"psd:{site}:{feat}", exp, "alertness / new arousal lane", tags=(sname,)))
        add(Check(f"sleep.delta_N3.{site}", "Relative delta highest in N3 (vs N2)", "AASM [Strong]", "Strong", "anchor", "sleep_edf_stages",
                  "N2 vs N3", _sleep((S_N2,), (S_N3,)), f"psd:{site}:rel_delta", +1, "sanity", tags=(sname,)))
        add(Check(f"sleep.sigma_N2.{site}", "Sigma (12-16 Hz, spindles) share up in N2 vs N1", "AASM [Strong]", "Strong", "anchor",
                  "sleep_edf_stages", "N1 vs N2", _sleep((S_N1,), (S_N2,)), f"psd:{site}:rel_sigma", +1, "N2 guard", tags=(sname,)))
        add(Check(f"sleep.sigma_local_N2.{site}", "Sigma (12-16 Hz) share of 8-20 Hz up in N2 vs N1 (delta-insensitive)", "AASM; De Gennaro2003 [Strong]", "Strong", "anchor",
                  "sleep_edf_stages", "N1 vs N2", _sleep((S_N1,), (S_N2,)), f"psd:{site}:sigma_local", +1, "N2 guard", tags=(sname,)))
        add(Check(f"sleep.log_sigma_N2.{site}", "Absolute sigma (12-16 Hz) power up in N2 vs N1", "AASM; De Gennaro2003 [Strong]", "Strong", "anchor",
                  "sleep_edf_stages", "N1 vs N2", _sleep((S_N1,), (S_N2,)), f"psd:{site}:log_sigma", +1, "N2 guard", tags=(sname,)))
        for feat, lab, exp, src, grade, lane in (
            ("btr", "Beta/theta (BTR) falls toward N1", -1, "derived from AASM theta + vigilance beta [Moderate]", "Moderate", "alertOpen/alertClosed"),
            ("engagement", "Engagement index beta/(alpha+theta) falls toward N1", -1, "Pope1995; Freeman1999 [Moderate] (EO tasks)", "Moderate", "alert lanes"),
            ("tab", "(theta+alpha)/beta rises toward N1", +1, "Jap2009; Eoh2005 [Moderate] (EO driving)", "Moderate", "drowsiness"),
            ("atr", "ATR (alpha/theta) falls toward N1", -1, "AASM via alpha/theta [Strong for parts]", "Strong", "restAwake"),
            ("paf", "Peak alpha frequency slows toward N1", -1, "Klimesch1999; Strijkstra2003 (slowing) [Moderate]", "Moderate", "PAF lane"),
        ):
            add(Check(f"sleep.{feat}.{site}", lab, src, grade, "claim", "sleep_edf_stages", "W (pre-onset) vs N1",
                      _sleep((S_W,), (S_N1,), PRE), f"psd:{site}:{feat}", exp, lane, tags=(sname,)))
    # eyes context: frontal rel alpha, early W (likely EO, lights on) vs N1 -> Torsvall: alpha may RISE vs EO wake
    add(Check("sleep.alpha_EOcontext.pz_oz", "Alpha vs EO-likely wake (30-15 min before onset): drop smaller / reversed",
              "Torsvall1987; Akerstedt1990 [Moderate]", "Moderate", "anchor", "sleep_edf_stages", "W (30-15 min pre-onset) vs N1",
              _sleep((S_W,), (S_N1,), ("early",)), "psd:pz_oz:rel_alpha", -1, "eye-state awareness", tags=("Pz-Oz",)))
    # gym-health: frontal alpha contradiction -> is it eye movement? keep low-EOG epochs only
    for site in ("fpz_cz", "pz_oz"):
        add(Check(f"sleep.alpha_drop_lowEOG.{site}", "Alpha share drops at sleep onset (low-EOG epochs only)", "AASM; Hori1994 [Strong]", "Strong",
                  "anchor", "sleep_edf_stages", "W (pre-onset) vs N1, both with HEOG 1-4 Hz <= rec median wake", _sleep_loweog((S_W,), (S_N1,), PRE),
                  f"psd:{site}:rel_alpha", -1, "gym health", tags=(site,)))
        add(Check(f"sleep.log_alpha_drop.{site}", "Absolute alpha power drops at sleep onset", "AASM; Hori1994 [Strong]", "Strong",
                  "anchor", "sleep_edf_stages", "W (pre-onset) vs N1", _sleep((S_W,), (S_N1,), PRE),
                  f"psd:{site}:log_alpha", -1, "gym health", tags=(site,)))
    # ---------------- Lee 2026 Muse 2 ---------------------------------------------------
    for pads in ("af", "tp", "all4"):
        for gate in ("", ":gate"):
            add(Check(f"lee.ec_alpha.{pads}{gate.replace(':', '.')}", "Alpha share up with eyes closed (Berger)", "Barry2007 [Strong]", "Strong",
                      "anchor", "lee2026_eo_ec", "EO rest vs EC rest", _label(), f"mu:{pads}:rel_alpha{gate}", +1, "restAwake, openMonitor",
                      tags=(pads, "gated" if gate else "ungated")))
            add(Check(f"lee.ec_atr.{pads}{gate.replace(':', '.')}", "ATR up with eyes closed", "Barry2007 (parts) [Strong]", "Strong",
                      "anchor", "lee2026_eo_ec", "EO vs EC", _label(), f"mu:{pads}:atr{gate}", +1, "restAwake", tags=(pads, "gated" if gate else "ungated")))
            add(Check(f"lee.ec_btr.{pads}{gate.replace(':', '.')}", "BTR not an eye-state marker (no strong EO/EC change expected)", "OURS prior; no lit claim", "-",
                      "null", "lee2026_eo_ec", "EO vs EC", _label(), f"mu:{pads}:btr{gate}", 0, "alert lanes", tags=(pads, "gated" if gate else "ungated")))
    for task, seg1, lab in (("BT", "task/jaw", "jaw clench"), ("EB", "task/blink", "blinks"), ("MVO", "task/head_turn_eo", "head turns EO")):
        for pads in ("af", "tp"):
            for gate in ("", ":gate"):
                tg = (pads, "gated" if gate else "ungated")
                add(Check(f"lee.{task}.gamma.{pads}{gate.replace(':', '.')}", f"Gamma (30-50 Hz) share up with {lab}",
                          "Goncharova2003; Whitham2007 [Strong]" if task == "BT" else "EMG physiology (control)", "Strong" if task == "BT" else "-",
                          "anchor" if task == "BT" else "claim", "lee2026_artifacts", f"clean rest vs {lab}", _label(_task(task)),
                          f"mu:{pads}:rel_gamma{gate}", +1 if task == "BT" else 0, "EMG guard", tags=tg))
                add(Check(f"lee.{task}.delta.{pads}{gate.replace(':', '.')}", f"Abs delta up with {lab}", "artifact physiology [Strong for EB/MV]",
                          "Strong" if task != "BT" else "-", "anchor" if task != "BT" else "claim", "lee2026_artifacts", f"clean rest vs {lab}",
                          _label(_task(task)), f"mu:{pads}:log_delta{gate}", +1 if task != "BT" else 0, "artifact guard", tags=tg))
    # ---------------- UNIVERSE workload (hard vs easy, within session) ------------------
    for task in ("arithmetix", "n_back", "stroop", "sudoku"):
        for feat, exp, src, grade in (("rel_theta", +1, "Chikhi2022 frontal theta g=0.68 [Moderate]", "Moderate"),
                                      ("rel_alpha", -1, "Chikhi2022 alpha g=-0.25 [Moderate]", "Moderate"),
                                      ("engagement", +1, "Pope1995 [Moderate]", "Moderate")):
            for gate in ("", ":gate"):
                add(Check(f"universe.{task}.{feat}{gate.replace(':', '.')}", f"Workload: {feat} {'up' if exp > 0 else 'down'} in hard vs easy {task}",
                          src, grade, "anchor" if feat == "rel_theta" else "claim", "universe_stress", f"{task}_easy vs {task}_hard",
                          _segments((f"{task}_easy",), (f"{task}_hard",)), f"mu:af:{feat}{gate}", exp, "concentrate / workload",
                          tags=("af", "gated" if gate else "ungated")))
    for feat, exp in (("rel_alpha", -1), ("rel_beta", +1)):
        add(Check(f"universe.stress.{feat}", f"Stress/arousal: {feat} {'down' if exp < 0 else 'up'} in hard tasks vs relax video",
                  "Katmah2021 [Weak/Mixed]", "Weak/Mixed", "claim", "universe_stress", "relaxation_video vs all *_hard",
                  _segments(("relaxation_video",), ("_hard",)), f"mu:af:{feat}:gate", exp, "restAwake (relax)", tags=("af", "gated")))
    add(Check("universe_hrv.rmssd", "HRV (RMSSD) lower under task load/stress than relax", "Kim2018 [Moderate-Strong]", "Moderate-Strong", "claim",
              "universe_hrv", "relaxation_video vs all *_hard", _segments(("relaxation_video",), ("_hard",)), "col:rmssd_ms", -1, "HRV lane (Muse PPG)"))
    add(Check("universe_hrv.hr", "Heart rate higher under task load than relax", "Kim2018 [Moderate]", "Moderate", "claim",
              "universe_hrv", "relaxation_video vs all *_hard", _segments(("relaxation_video",), ("_hard",)), "col:hr_bpm", +1, "HRV lane (Muse PPG)"))
    # ---------------- ds001787: focus (0) vs mind wandering (1), unit = subject ----------
    for var, sites in (("muse", (("lab_fz", "Fz avg-ref (lab)"), ("lab_pz", "Pz (lab)"), ("lab_oz", "Oz (lab)"), ("af7", "AF7"), ("af8", "AF8"), ("tp9", "TP9<-P9"), ("tp10", "TP10<-P10"))),
                       ("crown", (("f5", "F5"), ("f6", "F6"), ("c3", "C3"), ("c4", "C4"), ("po3", "PO3"), ("po4", "PO4")))):
        corpus = f"ds001787_mw_{var}"
        for site, sname in sites:
            for grp, gname in ((("expert",), "experts"), (("novice",), "novices")):
                tg = (sname, gname)
                if site in ("lab_fz", "f5", "f6", "af7", "af8"):
                    add(Check(f"mw.fmtheta.{site}.{gname}", f"Frontal(-midline) theta lower in MW than focus ({gname})",
                              "Brandmeyer2016 [Moderate; experts only]", "Moderate", "claim", corpus, "focus vs MW probe (10 s)",
                              _label(_group(*grp), unit="subject"), f"psd:{site}:log_theta", -1 if gname == "experts" else 0,
                              "concentrate (Crown F5/F6)", tags=tg))
                    add(Check(f"mw.tbr.{site}.{gname}", f"Frontal theta/beta higher in MW ({gname})", "vanSon2019a/b [Moderate]", "Moderate", "claim",
                              corpus, "focus vs MW", _label(_group(*grp), unit="subject"), f"psd:{site}:tbr", +1, "alert lanes (BTR inverse)", tags=tg))
                add(Check(f"mw.alpha_RL.{site}.{gname}", f"Alpha higher in MW than focus ({gname}; Rodriguez-Larios)", "RodriguezLarios2021 [novices; Mixed]",
                          "Contradicted/Mixed", "claim", corpus, "focus vs MW", _label(_group(*grp), unit="subject"), f"psd:{site}:log_alpha",
                          +1 if gname == "novices" else 0, "openMonitor/concentrate alpha", tags=tg))
                add(Check(f"mw.alpha_rel.{site}.{gname}", f"Alpha share in MW vs focus ({gname}; Braboszcz2011 expects down)", "Braboszcz2011 [Mixed]",
                          "Contradicted/Mixed", "claim", corpus, "focus vs MW", _label(_group(*grp), unit="subject"), f"psd:{site}:rel_alpha", -1,
                          "openMonitor/concentrate alpha", tags=tg))
                if site in ("c3", "c4", "tp9", "tp10"):
                    pass
            if site in ("c3", "c4"):
                add(Check(f"mw.soma_alpha.{site}.experts", "Somatosensory alpha higher in meditation than MW (experts)", "Brandmeyer2016 [Moderate]",
                          "Moderate", "claim", corpus, "focus vs MW", _label(_group("expert"), unit="subject"), f"psd:{site}:log_alpha", -1,
                          "concentrate (Crown C3/C4)", tags=(sname, "experts")))
        for site in ("lab_fz", "af7", "f5") if var == "muse" else ("f5", "f6"):
            if f"psd" and site in dict(sites):
                add(Check(f"mw.delta_theta_up.{site}.all", "MW = lower alertness: theta share up in MW (all)", "Braboszcz2011 [Moderate]", "Moderate",
                          "claim", corpus, "focus vs MW", _label(unit="subject"), f"psd:{site}:rel_theta", +1, "alert lanes", tags=(dict(sites)[site], "all")))
        for site in ("lab_oz", "lab_pz") if var == "muse" else ("po3", "po4"):
            add(Check(f"mw.slope.{site}.all", "Aperiodic slope in MW vs focus (no directional prior)", "RodriguezLarios2021 (med vs rest) [Weak]", "Weak",
                      "null", corpus, "focus vs MW", _label(unit="subject"), f"psd:{site}:slope_2_40", 0, "1/f lane", tags=(dict(sites)[site], "all")))
            add(Check(f"mw.engagement.{site}.all", "Engagement index lower in MW", "Pope1995 (EO tasks) [Moderate]; MW untested", "Weak",
                      "claim", corpus, "focus vs MW", _label(unit="subject"), f"psd:{site}:engagement", -1, "alert lanes", tags=(dict(sites)[site], "all")))
        add(Check(f"mw.tired_q3.{var}", "Tiredness (Q3) higher at MW probes", "Braboszcz2011 (MW = low alertness) [Moderate]", "Moderate", "claim",
                  corpus, "focus vs MW (self-report Q3)", _label(unit="subject"), "col:q3_tired", +1, "behavioural sanity", tags=("self-report",)))
    # ---------------- ds003969: thinking (0) vs meditation (1), EC -----------------------
    for var, sites in (("muse", ("lab_oz", "lab_fz", "af7", "tp9")), ("crown", ("po3", "po4", "f5", "c3"))):
        corpus = f"ds003969_medthink_{var}"
        for site in sites:
            for feat in ("log_alpha", "log_theta", "rel_alpha", "log_gamma", "slope_2_40", "paf"):
                add(Check(f"medthink.{feat}.{site}", f"Meditation vs instructed thinking: no within-group {feat} state effect",
                          "Braboszcz2017 (same data; no state effect) [Moderate]", "Moderate", "null", corpus, "think2 vs med2 (last 10 min each)",
                          _ds003969_think_vs_med(("think2",), ("med2",)), f"psd:{site}:{feat}", 0, "openMonitor / restAwake", tags=(site,)))
        for feat in ("slope_2_40", "paf", "log_alpha"):
            site = sites[0]
            add(Check(f"medthink.meditators.{feat}.{site}", f"Meditators: {feat} in meditation vs thinking (RL2021: steeper slope, lower IAF/alpha in meditation vs rest)",
                      "RodriguezLarios2021 [Weak-Moderate; control = rest, not thinking]", "Weak", "claim", corpus, "think2 vs med2, meditators",
                      _ds003969_think_vs_med(("think2",), ("med2",), ("htr", "vip", "sny", "tm")), f"psd:{site}:{feat}", -1, "PAF / 1/f lanes", tags=(site, "meditators")))
        add(Check(f"medthink.ppg_rmssd.{var}", "HRV (RMSSD) higher in meditation than thinking", "Kim2018 (stress) / meditation HRV [Weak for this contrast]", "Weak",
                  "claim", corpus, "think (both) vs med (both)", _ds003969_think_vs_med(("think1", "think2"), ("med1breath", "med2")), "col:ppg_rmssd_ms", +1, "HRV lane"))
        add(Check(f"medthink.ppg_hr.{var}", "Heart rate lower in meditation than thinking", "relaxation physiology [Weak for this contrast]", "Weak",
                  "claim", corpus, "think (both) vs med (both)", _ds003969_think_vs_med(("think1", "think2"), ("med1breath", "med2")), "col:ppg_hr_bpm", -1, "HRV lane"))
        add(Check(f"medthink.breath_vs_med.gamma.{var}", "Breath focus vs tradition meditation (no prior)", "Braboszcz2017 (high gamma 60-110 lower in med for HTR/SNY)", "Weak",
                  "null", corpus, "med1breath vs med2", _ds003969_think_vs_med(("med1breath",), ("med2",)), f"psd:{sites[0]}:log_gamma", 0, "-", tags=(sites[0],)))
    return C


# --- between-subject check (trait) ---------------------------------------------------


def trait_check(c: Corpus, site: str, feat: str, g1: tuple[str, ...], g0: tuple[str, ...]) -> dict[str, Any]:
    """Subject-median feature, AUC group g1 > g0 (Mann-Whitney)."""
    x = c.feature(f"psd:{site}:{feat}")
    grp = c.col("group").astype(str)
    seg = np.array([s.split("/")[0] for s in c.col("segment").astype(str)])
    m = c.play & np.isin(seg, ("med2",)) & np.isfinite(x)
    subs = np.unique(c.rec[m])
    v, y = [], []
    for s in subs:
        ms = m & (c.rec == s)
        g = grp[ms][0]
        if g in g1 or g in g0:
            v.append(float(np.median(x[ms])))
            y.append(1 if g in g1 else 0)
    a = roc_auc_up(np.array(v), np.array(y)) if len(set(y)) == 2 else None
    return {"n1": int(sum(y)), "n0": int(len(y) - sum(y)), "auc": a}


# --- runner -------------------------------------------------------------------------

CORPUS_FILES = {
    "sleep_edf_stages": "sleep_edf_stages.npz",
    "lee2026_eo_ec": "lee2026_eo_ec.npz",
    "lee2026_artifacts": "lee2026_artifacts.npz",
    "universe_stress": "universe_stress.npz",
    "universe_hrv": "universe_hrv.npz",
    "ds001787_mw_muse": "ds001787_mw_muse.npz",
    "ds001787_mw_crown": "ds001787_mw_crown.npz",
    "ds003969_medthink_muse": "ds003969_medthink_muse.npz",
    "ds003969_medthink_crown": "ds003969_medthink_crown.npz",
}


# corpus -> source dataset (accession, license, gym-only vs lab-only); see
# neurofeed-gym-corpora PROVENANCE.md for full citations.
DATASETS = {
    "sleep_edf_stages": "Sleep-EDF Expanded SC (PhysioNet 1.0.0, ODC-By-1.0) [gym]",
    "lee2026_eo_ec": "Lee 2026 Muse2 artifacts (figshare, CC-BY-4.0) [gym]",
    "lee2026_artifacts": "Lee 2026 Muse2 artifacts (figshare, CC-BY-4.0) [gym]",
    "universe_stress": "UNIVERSE (Zenodo 10371068, CC-BY-4.0) [gym]",
    "universe_hrv": "UNIVERSE E4 BVP (Zenodo 10371068, CC-BY-4.0) [gym]",
    "ds001787_mw_muse": "OpenNeuro ds001787 v1.1.1 (CC0) [gym]",
    "ds001787_mw_crown": "OpenNeuro ds001787 v1.1.1 (CC0) [gym]",
    "ds003969_medthink_muse": "OpenNeuro ds003969 v1.0.0 (CC0) [gym]",
    "ds003969_medthink_crown": "OpenNeuro ds003969 v1.0.0 (CC0) [gym]",
}


def run_checks(corpora: dict[str, Corpus], checks: list[Check]) -> list[dict[str, Any]]:
    rows = []
    for ch in checks:
        row = {k: getattr(ch, k) for k in ("id", "claim", "source", "grade", "kind", "corpus", "contrast_note", "feature", "expected", "lanes", "dt")}
        row["tags"] = list(ch.tags)
        row["dataset"] = DATASETS.get(ch.corpus, "?")
        c = corpora.get(ch.corpus)
        if c is None:
            row.update(verdict="untestable", reason="corpus not built")
            rows.append(row)
            continue
        x = c.feature(ch.feature)
        if x is None:
            row.update(verdict="untestable", reason="feature not available on this corpus")
            rows.append(row)
            continue
        m0, m1, unit = ch.contrast(c)
        m0 = m0 & c.play
        m1 = m1 & c.play
        row.update(contrast_stats(np.asarray(x, float), c.rec, np.asarray(unit).astype(str), m0, m1, ch.expected))
        rows.append(row)
    return rows


def _f(x: Any, nd: int = 2) -> str:
    if x is None or (isinstance(x, float) and not np.isfinite(x)):
        return "—"
    if isinstance(x, float):
        return f"{x:.{nd}f}"
    return str(x)


def _exp(e: int) -> str:
    return {1: "↑", -1: "↓", 0: "≈ (none)"}[e]


def table(rows: list[dict[str, Any]]) -> str:
    out = ["| id | claim | source [grade] | dataset | corpus · contrast | feature | tags | expected | per-unit AUC (cond1>cond0) median [IQR] | auc_exp | units exp/total | sign p | verdict |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if r.get("verdict") == "untestable":
            out.append(f"| {r['id']} | {r['claim']} | {r['source']} | {DATASETS.get(r['corpus'], '?')} | {r['corpus']} · {r['contrast_note']} | `{r['feature']}` | {', '.join(r['tags'])} | {_exp(r['expected'])} | — | — | — | — | untestable ({r.get('reason', 'n<1')}) |")
            continue
        n = r["n_units"]
        ne = int(round(r["frac_expected"] * n))
        out.append(
            f"| {r['id']} | {r['claim']} | {r['source']} | {DATASETS.get(r['corpus'], '?')} | {r['corpus']} · {r['contrast_note']} | `{r['feature']}` | {', '.join(r['tags'])} | {_exp(r['expected'])} | "
            f"{_f(r['auc_median'])} [{_f(r['auc_q25'])}–{_f(r['auc_q75'])}] | {_f(r['auc_exp_median'])} | {ne}/{n} | {_f(r['sign_p'], 3)} | **{r['verdict']}** |"
        )
    return "\n".join(out) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--corpus-dir", type=Path, default=GYM_ROOT / "corpora" / "external")
    ap.add_argument("--out-dir", type=Path, default=None)
    ap.add_argument("--only", default="", help="substring filter on check ids")
    a = ap.parse_args(argv)
    corpora = {k: Corpus(k, a.corpus_dir / f) for k, f in CORPUS_FILES.items() if (a.corpus_dir / f).exists()}
    checks = [c for c in registry() if a.only in c.id]
    rows = run_checks(corpora, checks)
    trait = {}
    for k in ("ds003969_medthink_muse", "ds003969_medthink_crown"):
        if k in corpora:
            site = "lab_oz" if k.endswith("muse") else "po3"
            trait[k] = {
                "vip_vs_others_log_alpha": trait_check(corpora[k], site, "log_alpha", ("vip",), ("ctr", "htr", "sny")),
                "vip_vs_ctr_log_alpha": trait_check(corpora[k], site, "log_alpha", ("vip",), ("ctr",)),
            }
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = a.out_dir or (GYM_ROOT / "results" / f"{ts}_litcheck")
    out.mkdir(parents=True, exist_ok=True)

    def clean(o: Any) -> Any:
        if isinstance(o, dict):
            return {str(k): clean(v) for k, v in o.items()}
        if isinstance(o, (list, tuple)):
            return [clean(v) for v in o]
        if isinstance(o, (float, np.floating)):
            return None if not np.isfinite(o) else round(float(o), 4)
        if isinstance(o, np.integer):
            return int(o)
        return o

    board = {"generated_utc": datetime.now(timezone.utc).isoformat(), "corpora": {k: {"rows": c.n, "units": int(np.unique(c.rec).size)} for k, c in corpora.items()},
             "checks": rows, "trait": trait}
    (out / "litcheck.json").write_text(json.dumps(clean(board), indent=1), encoding="utf-8")
    md = [f"# literature checks ({ts})\n\n"]
    for corp in CORPUS_FILES:
        rs = [r for r in rows if r["corpus"] == corp]
        if rs:
            md.append(f"## {corp}\n\n" + table(rs) + "\n")
    if trait:
        md.append("## trait (between-subject, ds003969 med2)\n\n```\n" + json.dumps(clean(trait), indent=1) + "\n```\n")
    (out / "litcheck_tables.md").write_text("".join(md), encoding="utf-8")
    counts: dict[str, int] = {}
    for r in rows:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    print(out, counts)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
