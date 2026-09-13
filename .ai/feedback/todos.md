# Feedback leftovers

Not the monitor series. Do not mix with connect-simulator-ux or
pipeline-contract Key Decisions.

## Next

- Crown *run* (quality vectors, computed frames, charts device-aware).
- OSC connect / discovery for Crown / Notion.
- Android foreground service so recording survives app background.
- EEG artifact flag for jaw-clench / blink EMG (accel gating only catches head motion).
- Athena raw optical stream — [../TODO/athena-optics-contract.md](../TODO/athena-optics-contract.md).
- Publish `third_party/edf_export` to git+tag after a device export pass.

Historical phase checklists: [../archive/feedback-todos-historical.md](../archive/feedback-todos-historical.md).

## On-device QA (still)

- Calibration → auto-start; reward chimes; movement gates them.
- Five volume sliders live; target settings; in-flight recalibrate.
- Prefs survive restart. `[atr]` threshold stays ≤ ceiling.
- Disconnect ~30 s silence → interrupted + grace; reconnect resumes.
- Staged REVE calibration (artifacts / eyes-open / eyes-closed).
- Binaural + music + guard muffle on a real speaker.
- Streaming to a real LSL / OSC / BrainFlow sink.
- Android **Reduce audio stutter** at the *next* session start.
- Export PDF/PNG/CSV/EDF+ of a short session to a real folder (and SAF).
  See [../export.md](../export.md). Fit/pads: [../headset-fit.md](../headset-fit.md).
