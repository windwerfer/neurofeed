# Active Task

**Branch:** `refactor/spine`

**Now:** Implement the frozen data-plane spine via a **coordinator
thread**. Governing spec:
[spine/data-plane-contract.md](spine/data-plane-contract.md).
Governing handoff (prompts, gates, one commit per PR):
[spine/handoff-spine.md](spine/handoff-spine.md).
Do not implement from archived Grokbot
[archive/data-plane-contract.md](archive/data-plane-contract.md).

The coordinator does **not** code or review diffs. It spawns one
subagent per PR (1→7), waits for `PASS` + matching commit, then the
next. Do not reopen feedback pipeline Key Decisions.

**Aside (not this branch):** Spur A / CBraMod encoder + A-vig guardrail lived
on `feat/spur-a-cbramod-guardrail` — pack `assets/packs/cbramod-a-vig-full/`,
Candle CPU forward latency still TBD. Do not mix Spur A into spine PRs unless
explicitly asked.

Do not unlock Crown Start, reopen Connect UX, or change the v5 68-byte header
**size** / tags 1–10. Outer zstd on the container raw section is **deleted**
(PR 3), not dual-read. Bands Y is **dB display** (storage linear). Do not add
averaging, a Bands strip on Spectrogram, Spectrogram FFT-window chrome, or
`SMOOTH` / `REAL TIME` Bands chrome. Do not pause `SweepBuffer` / `BandCache`
on view change.

## Queued elsewhere (not this branch)

- Crown *run* (quality vectors, computed frames, charts device-aware).
- Making Crown / Notion OSC connect (or OSC discovery) work.
- On-device QA leftover boxes in [feedback/todos.md](feedback/todos.md).
- Publish `third_party/edf_export` to git+tag once export proves out on device.
- Athena optics raw stream (muse-rs `Optics`, session tag 11). Queued:
  [TODO/athena-optics-contract.md](TODO/athena-optics-contract.md).
- Spur A CBraMod mobile forward profiling / ship hardening (prior branch).
- Replacing `MuseEventDto` (D3 declined for this series).

Android FGS for overnight **is** spine PR 7 (not queued).

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_neurofeed:*:*:D`. See [testing-guide.md](testing-guide.md).
