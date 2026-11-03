# Device scan and auto-reconnect

| Field | Value |
|---|---|
| Status | **Implemented.** `crates/nf-core/src/autoconnect.rs` (timing), `Session::auto_reconnect` (`crates/nf-core/src/session.rs`). Tests: `crates/nf-mcp/tests/autoconnect.rs` (push transport, manual clock) and the unit tests in `autoconnect.rs`. |
| Date | 2026-11-03 |
| Scope | When the app scans for devices, and which device it connects without a user action. Muse BLE, Crown OSC, simulators. Desktop, Android, headless (`neurofeed-cli`). |
| Not this | What a live feedback session does on link loss ([feedback-disconnect.md](feedback-disconnect.md)). Connect list labels and groups ([../connect-simulator-ux.md](../connect-simulator-ux.md)). Muse matching rules ([../../docs/automation.md](../../docs/automation.md) troubleshooting). |

The workflow: a device the user has already connected finds its way back at any time. A new device always needs a user action.

---

## Law

1. **The Device dialog scans for as long as it is open.** `device.dialog {"open":true}` starts a watch (`DeviceProvider::watch`) on every provider that can scan. It has no fixed length. While the dialog stays open, the session re-arms a watch that stopped (an error, or a Muse connect that took the adapter) every 5 s (`DIALOG_REARM_S`). It does not re-arm while a link is `connecting`. `{"open":false}` stops every scan, unless rule 2 applies.
2. **No connected device means a background search for the remembered device.** The search runs when all of these hold:
   - a remembered device exists (`auto_reconnect.target`);
   - auto-reconnect is not suspended (rule 4);
   - either no device is connected, or the connected device *is* the target and its link is `lost`.

   The search scans only the target's provider (`muse` → BLE, `crown` → OSC listen). Once the target is in the device list, the session connects it. If the target is the current device with a lost link, it is reopened in place, so the recording and feedback session waiting for that id carry on.
3. **Other devices are never connected automatically.** A device that is not the target, even one found during the background search, needs the user: **Connect** / **Switch** in the dialog, or an explicit `device.connect` (MCP, CLI, `--device`). A failed user connect to a new device is not retried. The user retries it.
4. **The user's Disconnect suspends auto-reconnect.** `device.disconnect` stops the search and sets `suspended`. The suspension ends at the next user connect (any device, including a simulator) or at the next app start. It is not persisted. The target stays remembered.
5. **The target is the last real device that streamed.** It is set when a non-simulated device's link reaches `streaming`, not when the connect starts, so a failed connect does not replace it. It is persisted as `last_device` in the settings doc and survives a restart: on start, with nothing connected, the search begins at once.
6. **Simulators are never the target.** Connecting `sim:*` does not change the target, and a simulator is never auto-connected. Simulators are always "visible", so making them a target would connect one on every start. Connecting a simulator while a real headset is remembered is still a user connect: it lifts the suspension of rule 4. While the simulator streams, nothing is searched (a device is connected).
7. **Crown follows the same rules over OSC.** "Scanning" means listening on UDP 9000 for Crown OSC packets. A burst listens for the burst length. The target Crown is auto-connected once its packets name its device id again. A Crown sending to this machine that is not the target is listed but not connected.

---

## Battery and duty cycle

The background search scans in bursts, not continuously:

| Constant | Value | Meaning |
|---|---|---|
| `BURST_S` | 6 s | One scan burst |
| `PERIOD_S` | 30 s | Burst period for the first 5 min of a search (~20 % radio duty) |
| `SLOW_AFTER_S` / `SLOW_PERIOD_S` | 300 s / 120 s | After 5 min, one burst every 2 min (~5 %) |
| `ATTEMPT_GAP_S` | 20 s | Minimum gap between two automatic connect attempts (a Muse connect can take 18 s) |

Closing the dialog while a search is due runs the next burst at once (the close stopped the scans). The search stops as soon as the target streams again.

Android: the search runs inside `Session::tick`, so it runs only while the app ticks (foreground, or kept alive by the recording foreground service). It never wakes the device. BLE scanning on Android also needs location/nearby-devices permission, and Android throttles apps that start more than 5 scans in 30 s. The 30 s period stays under that limit.

---

## MCP visibility

`device.status` includes:

- `scan_mode`: `dialog` | `background` | `timed` (`device.scan`) | `idle`.
- `scanning`: schemes with a scan running right now (empty between bursts).
- `auto_reconnect`: `{ target, suspended, searching, attempts, next_scan_in_s }`.

`settings.get` shows `last_device`. Each automatic attempt emits the event `auto_reconnect {id, error}`. The Device dialog shows one line while searching, or while suspended.

`device.scan {"seconds":n}` stays a one-shot timed scan for scripts. It does not connect anything.

---

## Not testable without hardware

- BlueZ / Android radio behaviour during bursts, and whether a Muse that dropped advertises again quickly enough for a 6 s burst.
- Reopening a Muse in place (muse-rs rescan by BLE id) after a real drop, during a feedback session.
- Crown: whether a Crown that stopped streaming starts sending OSC to this host again without the Neurosity app.
- Battery impact on a phone.

---

## Out of scope

- Remembering more than one device, or a "forget device" control (clear by connecting another real device).
- A user setting to turn auto-reconnect off.
- Reconnecting while the app is not ticking (Android background without the foreground service).
