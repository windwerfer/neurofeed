# Protocols and features: electrodes

Which pads each feature, the gate and the device-side detectors read. Rust
owns the choice; protocol JSON can only override it. Feedback lanes and
feature ids: [pipeline-contract.md](pipeline-contract.md).

## Per-device × per-feature defaults (Rust)

`rust/src/api/features.rs` `SPECS`: every feature lists its default
electrodes per device by **name** (`muse_electrodes`, `crown_electrodes`),
plus availability. `available_features(kind)` exposes them as
`FeatureInfo.defaultElectrodes`.

| Feature | Muse | Crown |
|---------|------|-------|
| `band.atr` / `band.tar` / `band.btr` / `band.alpha` | AF7, AF8 | PO3, PO4 |
| `band.delta` (frontal pair) | AF7, AF8 | F5, F6 |
| `ai.*` (a_vig, wake_light, *_reve, drowsiness alias) | AF7, AF8, TP9, TP10 | unavailable |
| `device.focus` / `device.calm` | unavailable | none (headset-computed) |

`DeviceConfig` (`rust/src/api/device_config.rs`) is the montage and index
authority (`electrode_names`, `electrode_index`) and holds the role pairs:

| Field | Muse | Crown | Used by |
|-------|------|-------|---------|
| `target_electrodes` | AF7, AF8 | PO3, PO4 | Reward electrode names when a reward feature has no montage |
| `needed_electrodes` | AF7, AF8 | PO3, PO4 | Gate pads when neither lane has montage electrodes (below) |
| `frontal_electrodes` | AF7, AF8 | F5, F6 | Guardrail frontal delta rail and band-math guard delta pads (Dart takes them from `frontalElectrodes`), blink detection, AI model rows AF7/AF8 |
| `temporal_electrodes` | TP9, TP10 | CP3, CP4 | Clench EMG, eye-level reference, AI model rows TP9/TP10 (Crown has no temporal sites) |

## Protocol overrides (Dart → Rust)

A protocol's `reward.electrodes` / `guard.electrodes` (names) are applied at
session start with `set_feature_electrodes(id, names)` for the reward and
the active guard feature. No override in the protocol sends an empty list,
which resets the feature to its default, so one protocol's override never
leaks into the next session.

- Names, never indices; names unknown on the active device → `Err`.
- `device.*` features have no montage → `Err`.
- `ai.*` features are not overridable on Crown (Muse-only) → `Err`.

## Gate pads (Rust)

`session_gate_electrodes(kind, reward_feature, guard_feature)` (sync)
returns montage indices for continue-anyway and the playing-phase pause.
Dart calls it after the overrides are applied, passing the reward feature
when the protocol has a reward lane and the guard feature only while the
guard is on:

1. The reward feature's resolved electrodes (override, else default).
2. Else a `band.*` guard's resolved electrodes. AI guards never add pads.
3. Else `DeviceConfig.needed_electrodes`.

Before a session (idle) the same call with no features gives the device's
needed pads. Dart owns the gate state machine (waiting, pause/resume,
timers, UI) and only asks Rust for the pads.
