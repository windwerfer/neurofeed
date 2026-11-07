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
