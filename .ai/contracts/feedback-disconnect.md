# Feedback session disconnect

| Field | Value |
|---|---|
| Status | **Frozen.** Law for a live feedback session. Implemented 2026-11-19 (`nf_core::feedback`, `apps/neurofeed-egui/src/ui/session_guard.rs`). |
| Date | 2026-11-19 (owner). Replaces the 2026-10-12 version and the 2026-10-29 "ends after a 10 s grace" rule in `docs/decisions.md`. |
| Scope | Feedback session in any active phase: `fit_check`, `calibrating`, `playing`, `paused`. |
| Not this | Record / Stop recordings outside a feedback session. Bad-signal wait ([pipeline-contract.md](pipeline-contract.md) gate pads). Annotation vocabulary ([fileformat_v6.md](fileformat_v6.md)). |

**Never auto-stop a session.** A session ends only after a warning that the
user confirms, or when the user ends it, or when its time is up.

---

## Law

1. **User Disconnect warns first.** Disconnect during a session shows a
   confirmation that the session will end. Cancel (the default) changes
   nothing. Confirm ends the session normally (summary, saved recording) and
   then disconnects the device. Programmatic: `device.disconnect` is refused
   during a session unless `end_session: true`.
2. **A lost link pauses.** Headset off, out of range, BLE drop, silent data
   (no data for 1.5 s): `playing` becomes `paused` (reason `disconnected`).
   Training seconds, calibration time and the content clock stop. No samples
   are invented. Clean seconds already accepted stay. User **Resume** does not
   continue past this wait.
3. **All sound stops.** Reward, background, music, binaural, guard alarm and
   the calibration background are silent while the link is lost, in every
   phase.
4. **Auto-reconnect looks for the same device** (the session's device id,
   [device-autoconnect.md](device-autoconnect.md)). When it is back the
   session continues: `playing` resumes, a user pause stays paused,
   calibration continues from its frozen clocks.
5. **A different device may not join.** While a session is open only its own
   device can connect; it reopens in place so the session and its recording
   continue.
6. **Ask after 15 s.** When the device is still gone after
   `RECONNECT_PROMPT_S` = 15 s, the app asks: **Keep waiting** (e.g. turn the
   headset back on) or **End session**. The dialog has no countdown and does
   not close on Escape or an outside click. Keep waiting closes it until the
   link comes back; a later loss asks again.
7. **No grace end, no timeout.** Nothing ends the session on a link loss,
   however long it lasts.

Bad signal is unchanged: all gate pads bad for 10 s pauses (`bad_signal`)
and resumes by itself after 2 good seconds. It never ends the session.

---

## Surfaces

| Surface | Command / state |
|---|---|
| Disconnect confirmation | `device.disconnect {end_session: true}` on Confirm. Copy keys `session-guard-disconnect-*`. |
| Reconnect prompt | `feedback.status.reconnect_prompt`, `link_lost_s`; event `reconnect_prompt`. Buttons `feedback.keep_waiting` / `feedback.stop`. Copy keys `session-guard-lost-*`. |
| Training status chip | `Paused: waiting for the device to reconnect`. |

---

## Still open

- The recording has no explicit `disconnect` annotation span yet; the gap is
  visible as missing samples and as per-second feedback records with phase
  `paused` / reason `disconnected`.
- `sim.configure` reconnects a running simulator through a full connect,
  which still stops a session's recording.
