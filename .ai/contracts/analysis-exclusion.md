# Contract: analysis channel exclusion (2026-11-07)

1. **Global, not a view filter.** An excluded channel is left out of feedback
   inputs, every derived graph/aggregate (Bands, PSD, Histogram/Spectrogram
   endpoints, features) and AI model input. Per-graph channel selection
   (`monitor.display`, `monitor.raw`, `monitor.psd`) is a separate display
   choice; derived graphs use *selection ∩ eligible*.
2. **Never empty → all.** If the eligible selection is empty, the graph or
   endpoint says so ("no eligible electrode selected"); no zeros, no fallback.
3. **Raw fidelity.** The signal ring, `raw.get`, recordings, exports and
   streaming keep every channel. Raw EEG shows excluded channels, marked.
4. **Explicit API.** `analysis.exclude` requires `confirm=true`; display
   commands can never exclude. The UI asks first (short text, unchecked
   "Remember for this device"); Cancel changes nothing. Re-include is
   immediate (`analysis.include`) and forgets a remembered exclusion.
5. **Scope.** Session exclusions reset on disconnect or device switch (a lost
   link that reconnects in place keeps them). Remembered exclusions are keyed
   by stable device id **and** channel name (never index); restored on
   connect with a visible notice; simulators have stable ids (`sim:muse`…).
6. **Feedback.** Target pads minus excluded; ≥ 1 left → the engine averages
   those; none left → never green, pause/calibration wait names
   "AF7 (excluded from analysis)". AI: an excluded model input channel blocks
   scoring with `blocked_reason` (schema unchanged).
7. **Hint, never action.** A dismissible, non-modal top-bar hint only when for
   60 s: ≥ 2 eligible pads ≥ 80 (the app's usable gate), one eligible pad
   < 50, fresh quality, a movement sensor reading ≤ 0.05 g. Missing/stale
   quality or movement, motion, or any break resets the timer; once per
   channel per connection. Tapping opens the Device dialog highlighting the
   control. It never excludes, opens, or dims anything by itself. Wording is
   about contact quality only.

## Artifact gates and protocol audit (2026-11-07)

- Excluded electrodes are never fed to the blink / jaw-clench / eye
  detectors (`Artifacts.excluded`, synced from the session each packet
  batch; their gamma is dropped). Movement (accelerometer) is unaffected.
  Raw ring, recording and per-channel flags keep the excluded channel.
- Histogram and Spectrogram UI views honor exclusion: excluded channels get
  no histogram card; an excluded spectrogram channel shows "no eligible
  electrode" (never another channel).
- Protocol audit: every feedback feature (atr, tar, btr, alpha, theta,
  beta, inhibits, stability) is a mean of relative band power over the
  usable target pads; no protocol requires a pad *pair* (no asymmetry
  feature). With one target pad excluded the engine uses the remaining
  target pad — the same rule as a pad with bad quality. Excluding the whole
  target pair never substitutes other electrodes: feedback reports the pads
  as "(excluded from analysis)" and waits (tested on Crown PO3/PO4).
