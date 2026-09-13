# Headset fit

Four status-bar marks `/ ‾ ‾ \` are **TP9 · AF7 · AF8 · TP10** (left ear,
left forehead, right forehead, right ear). Crown graphs can show 8 panes;
the bar stays 4 dots.

| Color | Score | Meaning |
|-------|-------|---------|
| Green | ≥ 80 | Usable. Band features skip pads below 80. |
| Amber | 40–79 | Noisy / poor contact. |
| Red | < 40 | Critical. Playing pauses only when **all gate pads** (default AF7/AF8) stay critical for 10 s — it never auto-ends. |

Score is EEG std over 1 s plus a 50/60 Hz line-noise penalty. Very flat
(`std < 1`) or huge (`std > 100`) reads as 0 (off-head or saturated).

**Fit:** rear pads on the mastoid (hair out), front pads on bare forehead,
band snug. Wet the pads if they bounce between amber and red. Walk away
from a wall wart if everything is amber — that is usually mains, not
placement.

**Classic vs Athena** (both are Muse, 4 EEG pads @ 256 Hz): Classic has
3-ch PPG (IR+red → pulse / SpO₂). Athena multiplexes extra optical
channels that this app does **not** show — they are squeezed into the
Classic PPG type or dropped. See [muse-rs.md](muse-rs.md). Battery % is
`bp` from the headset, not the fuel-gauge voltage.

Before calibration, gate pads must sit green for 3 s. After baseline, no
re-lock.
