# Audio assets for Muse ML Feedback

| File | Role |
|------|------|
| `calibration/alpha-theta-ratio_*.opus` | Calibration narrator variants (single-baseline intro) |
| `calibration/grok-reve-*.opus` | Staged-calibration guidance clips (artifacts / eyes-open challenge / eyes-closed drifting) |
| `drone/859763__kkenny101__drone-loop-ambient-background-texture.opus` | Background layer — "Drone Loop" |
| `drone/845842__frame__complex-shifting-ambient-drone-8-1min.opus` | Background layer — "Ambient Drone" |
| `rain/346562__lebaston100__rain-without-thunder.opus` | Background layer — "Rain" |
| `bowl/bowl_low-531269__asuriya__aud-10-ancient-tibet-bowl-pure-vibrations.opus` | Reward / recalibrate chime |
| `bowl/bowl_high-421829__dersinnsspace__tibetan-bowl_center-hit.opus` | Reserved |
| `bell/864397__valerie-vivegnis__2607.opus` | End-of-session + guardrail warning chime |

Supported formats: opus (Ogg Opus), ogg (vorbis/flac), mp3, wav, flac — flutter_soloud 4.x bundles the Xiph decoders (`libopus`/`libogg`/`libvorbis`) and decodes Opus natively on Android and Linux.

Licenses: see `attribute.md`.
