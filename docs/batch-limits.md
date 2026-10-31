# `command_batch`: what a rollback can undo

`Session::batch` parses every step first (an unknown id or bad params runs
nothing), then runs them in order. If a step fails, it restores the
`AppState`, simulator config, event log and data-path state (`Live`) from
before the batch. Some commands touch things outside that snapshot. This
table lists each command and what happens to it on rollback. Read-only
queries change nothing, so they are always safe in a batch.

| Command(s) | In a batch | On rollback |
|---|---|---|
| `view.set`, `sidebar.set`, `scale.set`, `stream.pause` / `stream.resume`, `mains.set`, `channel.set`, `stability.set`, `guard.set`, `threshold.set`, `feedback.override`, `feedback.pause` / `feedback.resume`, `calibration.*`, `protocol.set`, `protocol.validate`, `protocol.draft` | yes | fully undone (in-memory state) |
| `sim.configure`, `sim.fault`, `sim.fault.add`, `sim.fault.clear` | yes | fully undone (sim config, latched and timed faults) |
| `clock.advance` | yes | state is restored; the device is reopened fresh because sources cannot be cloned, so simulated data restarts |
| `device.connect`, `device.disconnect`, `history.open` (`replay:`) | yes | the previous device is reopened. A real headband reconnects over BLE, so a short link drop is visible |
| `device.scan` | yes | the scan result is dropped; the radio scan already happened |
| `settings.set` | yes | undone. Settings are written to the store again |
| `protocol.save`, `protocol.delete` | yes | undone. Custom protocols are rewritten to the store, and a write failure emits `StoreError` |
| `history.notes` | yes | undone. Old notes are written back to the store, and a failure emits `StoreError` |
| `recording.start`, `feedback.start`, `feedback.stop` | yes | state is undone. The partial recording is dropped, and checkpoint blobs written in the meantime are replaced by the next checkpoint |
| `recording.stop` (also a feedback session ending) | yes, partial | the saved session **stays saved**, and history is reloaded from the store after the rollback |
| `streaming.set` | yes, partial | the config is undone, but LSL / OSC packets already sent stay sent |
| `audio.set` | yes, partial | the setting is undone, but sound already played stays played |
| `ai.set`, `ai.load`, `ai.unload` | yes | undone, and the previously loaded model is restored |
| `ai.install`, `ai.remove` | **refused** | they download or delete model files |
| `history.delete`, `history.import` | **refused** | they delete or add saved sessions |
| `recovery.restore`, `recovery.discard` | **refused** | they consume the crash-recovery checkpoint |
| `events.drain` | yes | the event log is truncated back, but drained events are not re-queued |

If a step is refused, the whole batch fails before anything runs, with
`step N: … cannot be rolled back; run them on their own`.
