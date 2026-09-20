# Active Task

**Branch:** `refactor/spine`

**Now:** Data-plane **spine contract** first
([spine/data-plane-contract.md](spine/data-plane-contract.md) — Draft /
freeze-in-progress), then Rust-owned implementation (acquisition / DSP /
feature registry / scratch writer; thin Dart views). Hybrid `MuseEventDto` +
off-UI recorder is a short bridge only, not the end state. Do not reopen
feedback pipeline Key Decisions.

**Aside (not this branch):** Spur A / CBraMod encoder + A-vig guardrail lived
on `feat/spur-a-cbramod-guardrail` — pack `assets/packs/cbramod-a-vig-full/`,
Candle CPU forward latency still TBD. Do not mix Spur A into spine PRs unless
explicitly asked.

Do not unlock Crown Start, reopen Connect UX, or change the v5 68-byte header
in spine work. Bands Y is **dB display** (storage linear). Do not add
averaging, a Bands strip on Spectrogram, Spectrogram FFT-window chrome, or
`SMOOTH` / `REAL TIME` Bands chrome. Do not pause `SweepBuffer` / `BandCache`
on view change.

## Queued elsewhere (not this branch)

- Crown *run* (quality vectors, computed frames, charts device-aware).
- Making Crown / Notion OSC connect (or OSC discovery) work.
- Android foreground service so recording survives app background.
- On-device QA leftover boxes in [feedback/todos.md](feedback/todos.md).
- Publish `third_party/edf_export` to git+tag once export proves out on device.
- Athena optics raw stream (muse-rs `Optics`, session tag 11). Queued:
  [TODO/athena-optics-contract.md](TODO/athena-optics-contract.md).
- Spur A CBraMod mobile forward profiling / ship hardening (prior branch).

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_neurofeed:*:*:D`. See [testing-guide.md](testing-guide.md).
