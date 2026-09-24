# Active Task

**Now:** Data-plane spine is **implemented**. Governing spec:
[contracts/data-plane-contract.md](contracts/data-plane-contract.md).
Historical coordinator steps (done):
[archive/handoff-spine.md](archive/handoff-spine.md).

Do not reopen spine Key Decisions, feedback pipeline Key Decisions, Crown
Start, Connect UX, or the 68-byte `.neurofeed` header **size** / tags 1–10
(current container is NFED6 / formatVersion 6 — see
[contracts/fileformat_v6.md](contracts/fileformat_v6.md)). Outer zstd
on the container raw section stays **deleted**, not dual-read. Bands Y is
**dB display** (storage linear). Do not add averaging, a Bands strip on
Spectrogram, Spectrogram FFT-window chrome, or `SMOOTH` / `REAL TIME` Bands
chrome. Do not pause `SweepBuffer` / `BandCache` on view change.

**Aside:** Spur A / CBraMod encoder + A-vig guardrail lived on
`feat/spur-a-cbramod-guardrail` — pack `assets/packs/cbramod-a-vig-full/`,
Candle CPU forward latency still TBD. Do not mix Spur A into unrelated work
unless explicitly asked.

## Queued elsewhere (not this branch)

- Crown *run* (quality vectors, computed frames, charts device-aware).
- Making Crown / Notion OSC connect (or OSC discovery) work.
- On-device QA leftover boxes in [feedback/todos.md](feedback/todos.md).
- Publish `third_party/edf_export` to git+tag once export proves out on device.
- Athena optics raw stream (muse-rs `Optics`, session tag 11). Queued:
  [TODO/athena-optics-contract.md](TODO/athena-optics-contract.md).
- Spur A CBraMod mobile forward profiling / ship hardening (prior branch).
- Replacing `MuseEventDto` (D3 declined).
- Phone overnight QA of keepable-capture FGS (literal 12 h night; FGS itself
  landed).

## How to verify BLE (still)

`flutter run`, status bar battery from `bp` not the fuel gauge. Logcat:
`adb logcat -s rust_lib_neurofeed:*:*:D`. See [testing-guide.md](testing-guide.md).
