# Handoff — continue PR 2 (feature bus)

| Field | Value |
|---|---|
| Date | 2026-08-29 |
| Branch | `main` (ahead of origin; do not commit unless asked) |
| Thought level | User was on **high** for implementation. Contract was frozen on xhigh. Do not reopen Key Decisions. |
| Status | **PR 1 done. PR 2 ~85% done, blocked on FRB codegen.** Tree does **not** compile on the Dart side. |

The previous thread hit ~250k context. This file is the continuation point. Read it, then the contract, then the files listed under “Resume here”. Do not re-design the pipeline.

---

## What this project is doing

Muse ML: Flutter UI + Rust BLE (`muse-rs` / btleplug) + on-device LUNA/REVE. PoC (connect, record v5, export, AI, audio) is in. The **feedback** stack is being restructured so custom programs and catalog “bookmarks” share one pipeline:

```
Rust feature registry → MuseEventDto::Feature(FeatureDto)
  → Dart FeatureBus → RewardLane / GuardLane / Background / Orchestrator
```

**Inhibit ≠ guard.** Background ≠ reward output. JSON names IDs; Rust owns `(device, feature)` electrodes. Crown **may list** band protocols later; **running a catalog session on Crown is out of scope** this series.

Frozen spec: [`.ai/feeback/pipeline-contract.md`](pipeline-contract.md) (also copied historically to `/tmp/grok-vscode/grok-design-doc-1615861b.md`). Key Decisions 1–19 and the 7-PR plan are the law.

PR order: **1 contract (done) → 2 feature bus (this) → 3 protocol documents → 4 notifier split → 5 audio outputs → 6 calibration compose → 7 custom builder last.**

---

## PR 2 scope (from the contract)

`feat(rust): feature registry, FeatureDto, Crown focus/calm pass-through`

- **Do:** registry + `FeatureDto` on the existing event stream; quality autodrop in Rust; Crown `/focus` `/calm` pass-through; encode no-op; FRB both sides.
- **Do not:** UI, `ProtocolType` kill, `DeviceConfig` FFI fields, v5 body layout, graphs, export, BLE.
- Default enabled set is **empty**. No band `FeatureDto` in the live view until something calls `set_enabled_features`.
- Dual-emit `ai.drowsiness` **only while `ReveDto` is already emitted** (`guardrail_enable` path).
- Dart `switch` `default:` already ignores unknown variants (`feedback_state.dart` ~1320, `connection_provider.dart` ~290, `streaming_controller.dart` ~143, `session_recorder.dart` `_ => false`).

---

## Done (Rust logic — keep)

| Piece | Where | Notes |
|---|---|---|
| Registry + FFI sketches | `rust/src/api/features.rs` (**new**) | `available_features`, `set_enabled_features`, `set_feature_electrodes`; 8 v1 IDs; Muse AF7/AF8 vs Crown PO3/PO4; `ai.drowsiness` Muse-only; `device.*` Crown-only |
| Quality formula | same file `pad_quality_from_std_and_noise` | Port of Dart `_maybeComputeSignalQuality`. 1.0 **second** EEG ring = **256 samples @ 256 Hz**, skip pad if `< 10` samples. `noise < 0` = no penalty. Keep pad if `>= 80`. |
| Module | `rust/src/api/mod.rs` | `pub mod features;` |
| `MuseEventDto::Feature` | `rust/src/api/muse.rs` | imports `FeatureDto` from `features.rs` (single definition) |
| 1 Hz band tick | `muse.rs` `emit_enabled_band_features` | autodrop via `collect_usable_pads`; skip sample if none usable (never emit `0.0`) |
| Reve dual-emit | `muse.rs` after `MuseEventDto::Reve` | only if `features::is_enabled("ai.drowsiness")` |
| Active kind | `set_active_kind` on all connect paths; `clear_active_kind` on disconnect + forwarder Drop | so `set_enabled_features` can reject unavailable-on-this-kind when a headset is up; no headset → store set |
| Crown focus/calm | `rust/src/api/neurosity_osc.rs` | emit `FeatureDto` iff enabled |
| Crown SQ | same | `/signalQuality` 0–1 → `set_crown_quality` 0–100 for aggregator only. `BandsDto.line_noise_ratio` on Crown is still the old 0–1 stuffing for Dart UI — do not “fix” that in PR 2 |
| Crown electrode comment | same | **was wrong** (`0=PO3…`). Now `0=CP3, 1=C3, 2=F5, 3=PO3, 4=PO4, …` matching `DeviceConfig::neurosity_crown()` |
| Encode no-op | `rust/src/api/session_format.rs` | `Feature(_)` with Reve/Gestures; test in `non_recording_events_encode_empty` |
| Dart keep-in-sync comment | `lib/src/connection_provider.dart` `_maybeComputeSignalQuality` | required by the contract |

**Rust tests passing** (before the last codegen; re-run after FRB fix):

```
cargo test --manifest-path rust/Cargo.toml --lib features::
cargo test --manifest-path rust/Cargo.toml --lib session_format
```

11 `features::` tests + 27 `session_format` tests were green.

`features.rs` tests share process-global registry state; they take `TEST_LOCK` in `reset()`. Do not drop that.

---

## Blocked — resume here

`flutter_rust_bridge_codegen generate` **did run** (CLI 2.11.1) and **wrote broken Dart**.

### Root cause

`struct Registry` in `features.rs` is a private process-global holder with:

```rust
crown_quality: [Option<f64>; 8],
```

FRB still codegen’d it (and `Registry.default_()`). Dart cannot name `double?Array8` (`lib/src/rust/lib.dart`, `lib/src/rust/api/features.dart` line 67). `build_runner` / `dart format` / freezed for `features.dart` all failed. **`lib/src/rust/api/features.freezed.dart` does not exist.**

### Fix (do this first, in order)

1. `#[frb(ignore)]` on `struct Registry` in `rust/src/api/features.rs` (same pattern as `EegRing` / `ChannelBands` / Crown `BandAccumulator`).
2. Confirm no other `[Option<T>; N]` or `[T; CONST]` leaks onto the Dart FFI. Allowed Dart FFI types: `FeatureDto`, `FeatureInfo`, `FeatureSource`, `FeatureLane`, and the three `pub fn`s.
3. Re-run `flutter_rust_bridge_codegen generate` from the repo root (pinned **2.11.1**, same as crate + Dart package).
4. Confirm:
   - `lib/src/rust/api/features.dart` has **no** `Registry` / `double?Array8`
   - `lib/src/rust/lib.dart` is back to the previous small generated file (no `class double?Array8`)
   - `features.freezed.dart` exists
   - `MuseEventDto` has a `Feature` variant in `muse.dart` / `muse.freezed.dart`
5. `cargo test --manifest-path rust/Cargo.toml --lib features::` and `… session_format` still green (codegen rewrites `rust/src/frb_generated.rs`).
6. `flutter analyze lib/src` clean. Exhaustive Dart switches: the four `default:` sites above must still compile (Feature should hit `default` until PR 4).
7. **Do not** change `DeviceConfig` FFI fields.

### FRB gotchas already handled

- `BandAccumulator` used `[f32; CROWN_ELECTRODE_COUNT]` → FRB “Cannot parse array length”. Fields are now `[f32; 8]`. `#[frb(ignore)]` on `BandAccumulator`, `CrownOscHandle`, `start_crown_osc_receiver`, `connect_crown_osc`.
- `EegRing` duplicated opaque/non-opaque → `#[frb(ignore)]` on `EegRing` and `ChannelBands`.
- Codegen may warn about `.fvmrc` without fvm; ignore.
- `build_runner` analyzer vs SDK 3.12 warning is pre-existing; it still ran once Dart parsed.

`lib/src/rust/api/neurosity_osc.dart` is a new generated stub (JoinHandle opaque). Harmless if codegen still emits it after ignores; don’t wire it from app code.

---

## After codegen is green — PR 2 is done when

- [ ] Dart FFI: `availableFeatures` / `setEnabledFeatures` / `setFeatureElectrodes` + `FeatureDto` on `MuseEventDto`
- [ ] Default enable set empty (already in Rust)
- [ ] `flutter analyze lib/src` clean
- [ ] Rust tests above green
- [ ] No UI / protocol JSON / `ProtocolType` changes
- [ ] User did **not** ask to commit; don’t commit unless they do

Optional smoke (not required to close PR 2): Dart could log unused `MuseEventDto.Feature` — contract says ignore until PR 4.

---

## Do not reopen

See contract Key Decisions. Highlights the last thread already fought:

- Crown **Start refused** this series; listing later is PR 3. Quality/computed/charts stay 4-ch.
- Gate electrodes ≠ producer electrodes. AI window does **not** add TP9/TP10 to the playing pause.
- `epochWindowSeconds = 75` is PR 4, not PR 2.
- `percentileWarn` preserves absolute `_lastDelta` vs 0.25 (unit-comment mismatch is a later science PR).
- `guardrailEngine` metadata stays `GuardrailMode.name` (`drowsinessMath`, …).
- No-pref guardrail: any document **with** a `guard` object defaults **ON** (today’s Settings, not unused JSON `guardrailDefault: false`).
- `assets/features.json` is **PR 3**, not PR 2.

---

## Thought level (user asked)

The agent **cannot** switch xhigh/high. The user sets the slider.

Suggested: stay on **high** to finish PR 2 codegen + analyze. Bump to xhigh only if FRB keeps exploding. PR 3–7 guidance is in the previous conversation (high default; xhigh optional for PR 4 notifier split).

---

## First prompt for the new thread

> Continue from `.ai/feeback/handoff-pr2.md`. Frozen contract: `.ai/feeback/pipeline-contract.md`. Finish PR 2: `#[frb(ignore)]` the private `Registry` in `rust/src/api/features.rs` so codegen stops emitting `double?Array8`, re-run `flutter_rust_bridge_codegen generate`, make `flutter analyze lib/src` and `cargo test --manifest-path rust/Cargo.toml --lib features::` + `session_format` green. Do not start PR 3. Do not commit unless I ask.

Then implement. Do not rewrite `features.rs` from scratch; the registry and tests are already there.
