# Third-Party Notices

This application (`muse_ml`, the Muse ML headset companion) incorporates or
links against the following third-party components, plus attribution for the
bundled audio. License terms for each component are included here so that
redistribution complies with their terms.

The overall project is licensed under the Apache License 2.0 (see `LICENSE.txt`).

---

## FLAG — GPL-3.0 component

`rlx-cpu` (the CPU inference backend for the REVE/LUNA model engine) is
**GPL-3.0-only**. It is compiled into this application. If you distribute this
app, the combined work must satisfy the GPL-3.0 copyleft terms (offer source,
preserve notices, allow re-licensing under GPL). Review this dependency before
any distribution — it is the one component not permissively licensed.

See `Third-party → Rust → rlx / rlx-cpu` below.

---

## Third-party → Dart/Flutter

| Package | Version | License | Source |
|---------|---------|---------|--------|
| Flutter SDK | — | BSD-3-Clause | https://github.com/flutter/flutter |
| flutter_rust_bridge | 2.11.1 | MIT | https://pub.dev/packages/flutter_rust_bridge |
| flutter_riverpod / riverpod / riverpod_annotation | 2.6.1 | MIT | https://pub.dev/packages/flutter_riverpod |
| shared_preferences | 2.5.5 | BSD-3-Clause | https://pub.dev/packages/shared_preferences |
| path_provider | 2.1.6 | BSD-3-Clause | https://pub.dev/packages/path_provider |
| file_selector | 1.1.0 | BSD-3-Clause | https://pub.dev/packages/file_selector |
| permission_handler | 11.4.0 | MIT | https://pub.dev/packages/permission_handler |
| device_info_plus | 10.1.2 | BSD-3-Clause | https://pub.dev/packages/device_info_plus |
| crypto | 3.0.7 | BSD-3-Clause | https://pub.dev/packages/crypto |
| url_launcher | 6.3.2 | BSD-3-Clause | https://pub.dev/packages/url_launcher |
| flutter_soloud | 4.1.7 | MIT | https://pub.dev/packages/flutter_soloud |
| freezed / freezed_annotation | 2.5.8 / 2.4.4 | MIT | https://pub.dev/packages/freezed |
| build_runner | 2.5.4 | BSD-3-Clause | https://pub.dev/packages/build_runner |
| blake3 (via package deps) | — | CC0-1.0 | — |

## Third-party → Rust

| Crate | Version | License | Source |
|-------|---------|---------|--------|
| flutter_rust_bridge (Rust crate) | =2.11.1 | MIT | https://github.com/fzyzcjy/flutter_rust_bridge |
| muse-rs | 0.1.0 | Apache-2.0 | https://github.com/eugenehp/muse-rs |
| btleplug (fork) | 0.11.8 / 0.12.0-muse-3 | BSD-3-Clause (© 2020–2021 Nonpolynomial) | https://github.com/windwerfer/btleplug |
| jni | =0.19 | MIT / Apache-2.0 | https://github.com/jni-rs/jni-rs |
| tokio | 1.53.1 | MIT | https://github.com/tokio-rs/tokio |
| anyhow | 1.0.104 | MIT / Apache-2.0 | https://github.com/dtolnay/anyhow |
| log | 0.4.33 | MIT / Apache-2.0 | https://github.com/rust-lang/log |
| env_logger | 0.11.11 | MIT / Apache-2.0 | https://github.com/rust-cli/env_logger |
| android_logger | 0.14.1 | MIT / Apache-2.0 | https://github.com/NeoLegends/rust-android-logger |
| zstd | 0.13.3 | MIT / Apache-2.0 | https://github.com/gyscos/zstd-rs |
| reveal-rs | (git rev 9c8d856…) | Apache-2.0 | https://github.com/eugenehp/reve-rs |
| luna-rs | v0.0.4-latent-embedding-fix | Apache-2.0 | https://github.com/windwerfer/luna-rs |
| rlx | 0.2.13 | GPL-3.0-only | https://crates.io/crates/rlx |
| **rlx-cpu** | 0.2.13 (vendored, patched) | **GPL-3.0-only** | https://crates.io/crates/rlx-cpu; local copy at `vendor/rlx-cpu` |

Model weights are **not** shipped with the app. LUNA (Apache-2.0) downloads
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
  `reveal-rs`, `luna-rs`, `jni` (optionally).
- **BSD-3-Clause** — Flutter SDK, `shared_preferences`, `path_provider`,
  `file_selector`, `device_info_plus`, `crypto`, `url_launcher`, `build_runner`,
  `btleplug` (© Nonpolynomial).
- **MIT** — `flutter_rust_bridge`, `flutter_riverpod`/`riverpod`,
  `permission_handler`, `flutter_soloud`, `freezed`, `tokio`, `anyhow`, `log`,
  `env_logger`, `android_logger`, `zstd`, `jni`.
- **GPL-3.0-only** — `rlx`, `rlx-cpu` (see flag at top).
- **CC0 1.0** — most freesound audio.
- **CC BY 4.0** — rain, singing-bowl, bell/chime freesound audio.
- **CC BY-NC 4.0** — `guardrail-alarm-01.opus` (NonCommercial).