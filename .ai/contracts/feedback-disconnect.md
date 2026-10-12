# Feedback session disconnect

| Field | Value |
|---|---|
| Status | **Frozen.** Law for a live feedback session. The orchestrator still ends the session on link loss (`interruptionGraceSeconds`, and `end()` when `allowAutoReconnect` is false). That end is the bug this contract retires. |
| Date | 2026-10-12 |
| Scope | Feedback session while `calibrating`, `playing`, `paused`, or `interrupted`. |
| Not this | GraphShell recording. Bad-signal wait ([pipeline-contract.md](pipeline-contract.md) gate pads). Annotation vocabulary ([fileformat_v6.md](fileformat_v6.md)). Connect dropdown labels ([../connect-simulator-ux.md](../connect-simulator-ux.md)). SoLoud lifetime ([../audio-engine.md](../audio-engine.md)). |

Do not reopen these decisions. A link loss pauses the session. It does not end it. The session continues only when the same device connects again.

---

## Law

1. **A disconnect does not end the session.** Headset drop, the forwarder's 30 s silence `Disconnected`, status-bar **Disconnect**, and the device-type dialog's **Disconnect** all leave the feedback session open. Do not call `end()`. Do not assemble a `.neurofeed`. Do not set `phase` to `ended`. Do not open the session summary.
2. **The session pauses.** Phase becomes `interrupted` with `FeedbackInterruptKind.disconnect`. The content clock (`elapsedSeconds`) stops. Calibration stage countdowns and the baseline wall clock stop with it. Clean seconds already accepted stay. The user **Resume** control does not continue past this wait.
3. **Audio cues pause with the session.** Call `AudioService.pause()`: reward, guard alarm, background, music, rain, binaural, and calibration clips on that path go silent. On continue, call `AudioService.resume()`. Do not call `AudioService.stop()`. Do not call `SoLoudEngine.deinit()`.
4. **Continue only for the same device.** Latch `ConnectionStatus.id` while that id is non-empty and the session is open, before the link drops. On the next connect, continue only when the new `ConnectionStatus.id` equals the latched id. Display name is not identity. `sim:muse-2` and `sim:muse-s` are different devices. An empty id is not a match.
5. **A different device leaves the session paused.** Audio stays silent. Do not rewrite the session `deviceId`. Do not feed the new headset into this session. The session keeps waiting for the latched id, until the user ends it.
6. **Continue restores the phase from before the link loss.** Playing resumes playing, the ticker, and audio. A user pause stays `paused` with audio still paused. Calibration resumes `calibrating` from the frozen clocks and cues. Close the open `disconnect` annotation when the same device continues.
7. **There is no grace end.** `interruptionGraceSeconds` must not call `end()`. Do not show `Ending in {n}s if not recovered…`.
8. **The user can still end.** **End session**, the back-guard **End session**, and the duration elapsed still call `end()`.

Bad signal is unchanged: all gate pads critical for 10 s still enters `interrupted` / `badSignal`, waits, and resumes when those pads recover. It still never auto-ends. A link loss during that wait uses this contract (annotation type becomes `disconnect`, still no `end()`).

The 30 s silence timer that emits `Disconnected` stays. This contract changes what the session does with that event.

`allowAutoReconnect == false` (manual **Disconnect**) must not end the session. This contract does not require an automatic scan after that tap. A later connect of the latched id still continues the session.

---

## On-screen copy

Update [../ui-map.md](../ui-map.md) in the same change that lands these strings.

| Surface | Text |
|---|---|
| Disconnect wait | `Paused — waiting for {name} to reconnect.` `{name}` is `ConnectionStatus.name`. Empty name: `Paused — waiting for this device to reconnect.` |
| Disconnect wait actions | **End session** only. No countdown. |
| Device-type dialog, playing / paused / interrupted | Title stays `Session in progress`. Body: `Disconnect {name}? The feedback session stays paused until this same device reconnects. NeuroFeed will then look for a {next} device.` Actions stay **Cancel** / **Disconnect**. |
| Device-type dialog, calibration | Title stays `Session in progress`. Body: `Disconnect {name}? Calibration stays paused until this same device reconnects. NeuroFeed will then look for a {next} device.` |
| Status-bar **Disconnect** | Tooltip stays `Disconnect`. The tap drops the link and pauses the session. |

Device-type **Recording in progress** is unchanged. That recording stays open.

---

## File

Annotation type for this gap stays `disconnect` (`{onset, duration, type}`). Do not write `pause` for a link loss. User pause still stops raw and computed and still uses type `pause`. During the disconnect gap the content clock is frozen, the capture lease stays, and the writer does not invent samples. Close the open `disconnect` span when the same device continues, or when the user later ends.

---

## Out of scope

- GraphShell **Record** / **Stop**, and the recording device-type dialog.
- Changing how long a silent link waits before `Disconnected`.
- Bad-signal thresholds, gate electrodes, and the 10 s critical-pad wait.
- New annotation types or a second timeline.
