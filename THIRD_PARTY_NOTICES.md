# Third-Party Notices

This application (`neurofeed`, the NeuroFeed headset companion) incorporates or
links against the following third-party components, plus attribution for the
bundled audio. License terms for each component are included here so that
redistribution complies with their terms.

The overall project is licensed under the Apache License 2.0 (see `LICENSE.txt`).

---

## Third-party → Rust

| Crate | Version | License | Source |
|-------|---------|---------|--------|
| muse-rs (fork) | 0.1.2 (patches eugenehp 0.1.0) | Apache-2.0 | https://github.com/windwerfer/muse-rs |
| btleplug | 0.13.5 | MIT / Apache-2.0 / BSD-3-Clause (© 2020–2021 Nonpolynomial) | https://github.com/deviceplug/btleplug |
| jni | 0.22.4 | MIT / Apache-2.0 | https://github.com/jni-rs/jni-rs |
| tokio | 1.53.1 | MIT | https://github.com/tokio-rs/tokio |
| anyhow | 1.0.104 | MIT / Apache-2.0 | https://github.com/dtolnay/anyhow |
| log | 0.4.33 | MIT / Apache-2.0 | https://github.com/rust-lang/log |
| env_logger | 0.11.11 | MIT / Apache-2.0 | https://github.com/rust-cli/env_logger |
| android_logger | 0.14.1 | MIT / Apache-2.0 | https://github.com/NeoLegends/rust-android-logger |
| zstd | 0.13.3 | MIT / Apache-2.0 | https://github.com/gyscos/zstd-rs |
| reveal-rs | (git rev 9c8d856…) | Apache-2.0 | https://github.com/eugenehp/reve-rs |
| rlx | =0.2.19 | MIT / Apache-2.0 | https://crates.io/crates/rlx |
| rlx-cpu | 0.2.19 (vendored, patched) | MIT / Apache-2.0 | https://crates.io/crates/rlx-cpu; local copy at `vendor/rlx-cpu-0.2.19` |
| candle-core | 0.11.0 | MIT / Apache-2.0 | https://github.com/huggingface/candle |
| candle-nn | 0.11.0 | MIT / Apache-2.0 | https://github.com/huggingface/candle |
| rustfft | 6.4.1 | MIT / Apache-2.0 | https://github.com/ejmahler/RustFFT |
| socket2 | 0.6 | MIT / Apache-2.0 | https://github.com/rust-lang/socket2 |
| rustix | 1 | Apache-2.0 WITH LLVM-exception / Apache-2.0 / MIT | https://github.com/bytecodealliance/rustix |

**liblsl** (protocol reference for `crates/pure-lsl`, no code copied; not linked or shipped) — MIT, Copyright (C) 2012 Christian A. Kothe, https://github.com/sccn/liblsl. pylsl is used only as a test tool. Full notice:

> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Model weights: Spur A ships the A-vig **head** pack; the CBraMod encoder (~20 MB Apache-2.0) downloads
from Hugging Face with SHA-256 verification; REVE (gated) is user-imported.

---

## Third-party → Audio

Sound assets are bundled by file. Attribution and license follow Freesound
(CC0 / CC BY 4.0 / CC BY-NC 4.0). Attribution links are the canonical IDs.

| Asset file | Original work / author | Source | License |
|------------|------------------------|--------|---------|
| `assets/audio/rain/346562__lebaston100__rain-without-thunder.opus` | "Rain without thunder" by lebaston100 | https://freesound.org/s/346562/ | CC BY 4.0 |
| `assets/audio/drone/845842__frame__complex-shifting-ambient-drone-8-1min.opus` | "Complex shifting ambient drone 8" by +frame+ | https://freesound.org/s/845842/ | CC0 1.0 |
| `assets/audio/drone/859763__kkenny101__drone-loop-ambient-background-texture.opus` | "Drone Loop – Ambient Background Texture" by kkenny101 | https://freesound.org/s/859763/ | CC0 1.0 |
| `assets/audio/bowl/bowl_low-531269__asuriya__aud-10-ancient-tibet-bowl-pure-vibrations.opus` | "Aud 10” ancient Tibet bowl pure vibrations" by Asuriya | https://freesound.org/s/531269/ | CC0 1.0 |
| `assets/audio/bowl/bowl_high-421829__dersinnsspace__tibetan-bowl_center-hit.opus` | "Tibetan bowl center hit" by dersinnsspace | https://freesound.org/s/421829/ | CC0 1.0 |
| `assets/audio/bell/864397__valerie-vivegnis__2607.opus` | "26.07.24 Tibetan Singing Bowl – Octave Pitch-Shifted Scale" by Valerie-Vivegnis | https://freesound.org/s/864397/ | CC BY 4.0 |
| `assets/audio/guardrail-cough-01.opus` (…02, …03) | "Coughing 001.wav" by frenkfurth | https://freesound.org/s/650914/ | CC0 1.0 |
| `assets/audio/guardrail-alarm-01.opus` | "Alarm Clock Digital" by zanox | https://freesound.org/s/233645/ | **CC BY-NC 4.0** |
| `assets/audio/guardrail-chime-01.opus` | Same work as `864397__valerie-vivegnis` (Bell chime) | https://freesound.org/s/864397/ | CC BY 4.0 |
| `assets/audio/guardrail-softBowl-01.opus` | Same work as `bowl_high-421829__dersinnsspace` (Soft bowl) | https://freesound.org/s/421829/ | CC0 1.0 |
| `assets/audio/calibration/grok-reve-*.opus` | Generated narration clips | — | see note |

> **NonCommercial flag:** `guardrail-alarm-01.opus` is **CC BY-NC 4.0**
> (NonCommercial). Keep it unless the app is distributed commercially, or
> swap it for a CC0/CC BY alarm. Consider before any commercial store listing.

> **Narrator clips (`calibration/grok-reve-*.opus`):** produced by the user via
> Grok (xAI) text-to-speech reading their own sentences. These are generated
> audio, not sampled works; treat as user-original content under the project
> license. Confirm xAI's output-usage terms if distributing.

---

## Full license texts

- **Apache License 2.0** — `LICENSE.txt` (this project); `muse-rs`,
  `reveal-rs`, `jni` (optionally).
- **BSD-3-Clause** — `btleplug` (© Nonpolynomial).
- **MIT** — `tokio`, `anyhow`, `log`,
  `env_logger`, `android_logger`, `zstd`, `jni`.
- **MIT / Apache-2.0** — `candle-core`, `candle-nn`, `rustfft` (Spur A Candle
  CBraMod encoder path); `rlx` 0.2.19 and vendored `rlx-cpu` 0.2.19 (REVE).
- **CC0 1.0** — most freesound audio.
- **CC BY 4.0** — rain, singing-bowl, bell/chime freesound audio.
- **CC BY-NC 4.0** — `guardrail-alarm-01.opus` (NonCommercial).

## DejaVu Sans (subset) — apps/neurofeed-egui/assets/arrows.ttf

A glyph subset (arrows, math signs, play/pause) of DejaVu Sans, used as a
fallback font in the egui app. DejaVu fonts are based on Bitstream Vera:
Copyright (c) 2003 Bitstream, Inc. (Bitstream Vera license); DejaVu changes are
in the public domain. https://dejavu-fonts.github.io/License.html
