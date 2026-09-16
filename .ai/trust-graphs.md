# Live reward / guard / inhibit trust graphs

| Field | Value |
|---|---|
| **Status** | Implemented |
| **Date** | 2026-09-14 |
| **Chrome names** | [ui-map.md](ui-map.md) |
| **Series history** | [archive/trust-graphs.md](archive/trust-graphs.md), [archive/handoff-trust-graphs.md](archive/handoff-trust-graphs.md) (PR 1 + PR 2). Inhibit pane is a follow-up on the same branch. |

Do not reopen pipeline-contract Key Decisions, Crown Start, Connect UX, v5
header, monitor GraphShell/Inspect, RatioEngine 80/40, `guardrailDeltaCeiling`
0.25, catalog protocols. Do not reuse `TimeSeriesPane` / `BandCache` /
`ViewportController`.

---

## What it is

During play/pause the session shows glanceable **reward**, optional
**inhibit**, and **guard** graphs so the user can see: should I hear a
sound, is inhibit blocking, is the sample dirty, which guard tripwire is
up.

Chips: `[ Reward ] [ Guard ] [ More ]` (`TrustChipRow`). Graphs + More
only while **playing** and **paused**. Calibration hides graphs/More;
chips may still show. `recordOnly` hides the row.

Viewport: **Follow only**, default **75 s**, pinch-X and Ctrl+scroll
**15–300 s**, 1 s Follow lead. Shared window. Not persisted. No Inspect.

Code: `lib/src/feedback/trust/`.

---

## Reward pane

Y = 0–100 percentile of this session’s reward pile. Label catalog
`shortLabel` (`ATR` / `TAR` / `BTR` / `α`). Horizontal line at the live
release percentile.

| Sample | Stroke | Background |
|---|---|---|
| Clean | solid, series color | gray **wash** only while inhibit is out (any reward Y) |
| Dirty | dotted, hold last clean Y | none |

Gray wash is **only** for inhibit-out. Not below-the-line without a
failed inhibit. Not dirty. Reward stroke is **never** gray.

Dirty run labels (`pads` / `movement`, or `jaw`/`blink` if ≥ 2 s) stay
on the reward pane. `beta high` / `delta high` live on the inhibit pane.

More: strip + Now rail + Hold. Verdict `Held back` is still
above-the-line **and** inhibit fail. Priority: noisy > held back > below
> in zone.

---

## Inhibit panes

Shown under Reward when the protocol has inhibit (`betaCeiling` /
`deltaCeiling`). Hidden if Reward is off or `inhibit: []`. Same
Follow window as Reward. **One pane per ceiling** (`trustInhibitSpecs`):
0, 1, or 2. Reward ATR pane is always shown while Reward is on.

Each pane is one series (β purple, δ cyan — `bandColors`):

- Ceiling **line** in the series color (pass zone is `[0, ceiling]`).
- Light fill from 0 to that ceiling.
- Overshoot (Y > ceiling) in a hue-keeping blend toward `error`. Labels
  `beta high` / `delta high` at zone-exit.

Dirty: dotted, hold last clean relative Y. Not overshoot, not a wash.

Y domain is relative power, padded so the pane’s ceiling is not
squashed (`inhibitAxisMax`).

Files: `trust_inhibit.dart` (specs, colors, run split),
`InhibitTrustPane` in `trust_pane.dart`.

---

## Guard

One pane per distinct warn signal (`trustGuardPaneSpecs`). Guard on
always has at least the percentile warn pane. Band-math (`band.delta`)
is one signal — warn only. AI (`ai.drowsiness`) scores sleep-dir and
still rails on always-on frontal δ — two panes (percentile warn + native
δ ceiling 0–0.5 / line 0.25). Held-back / inhibit wash does **not**
apply. One More block under the pane(s).

---

## Do not

- Peek detector / Inspect / GraphShell chrome on these panes.
- Gray-out of below-the-line reward without inhibit-out.
- Gray reward stroke.
- Dual-Y one-pane guard; extra ceiling tick on the percentile pane.
- A third chip for inhibit (it belongs to Reward).
- `TimeSeriesPane` / `BandCache` as the session plot.
