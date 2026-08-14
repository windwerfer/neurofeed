# Feedback Dev Todos

## Current branch: main (Phase I merged, ready for testing)

- [x] Phase 0: Navigation backbone + state machine + stub views
- [x] Phase 1: Rust derived metrics (pulse, movement, peak alpha)
- [x] Phase 2: Recording extension + zstd compression
- [x] Phase 3: Audio playback (just_audio + AudioService)

## Phase 3.5: Dual-layer reward audio
- [x] Target-state predicate: relative band power (alpha_rel > theta_rel), AF7/AF8 average
- [x] Dual-layer engine: background (drone/rain) + bowl reward chime pool (10 players, full-volume start, completion reset)
- [x] Movement gating: accel score > 0.05 resets hold timer and gates chimes (1 s buffer)
- [x] Sound selector (Ambient Drone / Drone Loop / Rain) + on-the-fly switch during feedback
- [ ] v1.1: EEG artifact flag for jaw-clench/blink EMG (accel gating only catches head motion)

## Phase 4: Full session flow
- [x] Auto-start after calibration (ready phase removed): all-green at end of baseline → playing immediately
- [x] Connection check on start — opens connect window if Muse disconnected (calibration + playing)
- [x] Wire FeedbackRecorder into session lifecycle (start on playing, save on end, discard on reset)
- [x] End-of-session → session dashboard navigation (auto pushReplacement)
- [x] Calibration completed event sound (bowl_high confirmation chime)
- [x] Disconnect during playing/paused → interrupted phase: pause, 10 s grace countdown, auto-resume on reconnect, end only if unrecovered
- [x] Persistent bad signal (any channel < 40 for 10 s) → interrupted phase; recovers when signal returns to green

## Phase 5: Session dashboard
- [x] Session reader (`.muse` parsing — now format v4, owned by Rust: `sessionParseBody`; the old Dart `decompressBlock` FFI path was removed in the format-migration commit)
- [x] Bands/motion/pulse graphs from recorded data
- [x] Overview-driven summary detail (400-bucket `SessionOverview` from metadata — no body read) with zoom-synced charts: drag-pan, pinch, ctrl/⌘+scroll zoom, double-tap reset
- [x] Fixed 0–1 y-axis (relative power) + numeric ticks for Bands and Alpha-vs-Theta; auto-scale for movement/HR
- [x] Clickable legend rows toggle each series on/off
- [x] Stats: peak alpha, target time %, stillness %, avg BPM, avg alpha_rel
- [x] Notes text field (persisted in Phase 6 metadata)
- [x] **Notes editable in the history detail**: corner save chevron (only when dirty) + spinner + brief "saved" flash; `PopScope` "Unsaved notes — Save/Stay/Discard" on Back
- [x] Save (green, renames temp → session_<ts>.muse) / Discard (gray, deletes temp); saves via crash-safe `writeFileAtomic`
- [x] Thumbnail generation (RepaintBoundary → PNG next to .muse)

## Phase 6: Feedback history
- [x] Session metadata persistence (JSON alongside .muse)
- [x] History list view with thumbnails, dates, stats
- [x] Tap to re-open dashboard (read-only mode, notes prefilled)
- [x] **Editable notes persisted back into the saved `.muse.feedback`** — crash-safe rewrite (`SessionStore.updateNotes`; FS tmp+rename, SAF `writeFileAtomic` + `recoverDoc`)

## Phase I (merged to main): Volume, recalibrate, adaptive target, persistence
- [x] 5-channel volume control (master / background / feedback / intro / end bell) with live apply + reset
- [x] In-flight recalibrate (refresh icon during playing/paused): re-anchors from last 90 s of clean data, soft low chime; ≥ 60 s + ≥ 30 clean samples guard
- [x] Adaptive lockout guards: ceiling = baselineMean + 1.5 SD, floor = baseline percentile, zero-success circuit breaker, asymmetric steps
- [x] Target settings dialog (gear icon): dynamic-target on/off + gentle↔responsive slider + (i) explainer
- [x] Persistence: volumes, sound, duration, target settings — saved and restored across restarts
- [x] ATR diagnostics logging (`[atr]` every 10 s, adapt events; `[feedback]` recalibrate events)

## Ready for testing (on-device checklist)
- [ ] Calibration flow: voice intro → 90 s baseline → auto-start, threshold visible in nerd stats
- [ ] Reward chimes during feedback; movement (scratch head) gates them
- [ ] Volume dialog: all 5 sliders audible live; reset button restores defaults
- [ ] Target settings: dynamic-target off keeps threshold static; slider changes adaptation speed; (i) explains
- [ ] Recalibrate during playing: chime sounds, threshold + baseline stats update in nerd stats bubble
- [ ] Restart app: volumes, sound, duration, target settings restored
- [ ] Watch `[atr]` logs around the 2–4 min mark: threshold must stay ≤ ceiling (mean + 1.5 SD)
- [ ] Lockout test: if target feels unreachable, threshold should reset via circuit breaker or lower fast (responsive setting)
- [ ] Mid-session Muse drop (power off / walk away): forwarder watchdog emits Disconnected after ~30 s silence → session pauses with grace countdown, auto-reconnect resumes the stream (watch `[muse] forwarder: newer connection` in logcat)
- [ ] Staged REVE calibration (drowsiness protocol): artifacts cue (15 s) → eyes-open (30 s) → eyes-closed (45 s); step name + per-step countdown in the calibrating UI; `V_clear` captured during eyes-open, sleep baseline during eyes-closed (`[guardrail]` logs); alphaTheta intro variant heard + version/kind persisted in metadata

## Next (v1.1 backlog)
- [ ] EEG artifact flag for EMG (jaw clench / blink) into ATR epoch cleaning
- [ ] Percentile selector persistence + defaults per protocol
- [ ] Optional continuous (EMA) adaptation instead of discrete 30 s jumps
- [ ] Multi-protocol presets (alpha/theta targets, band ratios)
- [x] Calibration audio variants: manifest-driven recipes (`calibration.json` v2) — alphaTheta = single baseline with randomized intro clips; drowsiness = staged 3-part REVE sequence (artifacts / eyes-open / eyes-closed) with per-stage metadata phases; clips stream alongside raw EEG (Option B) so collection gates on the silent windows only
