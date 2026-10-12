import numpy as np

from runners.stability_round import auc, epochs, per_rec, sign_p


def test_auc_and_sign():
    assert auc([2, 3], [0, 1]) == 1.0 and auc([1], [1]) == 0.5
    assert sign_p([1] * 10) < 0.01 and sign_p([1, -1]) == 1.0


def test_epochs_variability_detects_noisy_mw():
    rng = np.random.default_rng(0)
    n_pr, L = 8, 10
    rows = n_pr * L * 2
    rid = np.repeat(["a", "b"], n_pr * L)
    pid = np.tile(np.repeat(np.arange(n_pr), L), 2)
    y = (pid % 2).astype(int)
    alpha = rng.normal(0.3, np.where(y == 1, 0.1, 0.01))
    c = {"recording_id": rid, "probe_id": pid, "labels": y, "group": np.repeat(["expert", "novice"], n_pr * L),
         "alpha_rel": alpha, "drowsy": np.zeros(rows)}
    eps = epochs(c)
    assert len(eps) == 2 * n_pr
    r = per_rec(eps, "sd:alpha_rel", lambda e: e["y"] == 1)
    assert r["median"] == 1.0
