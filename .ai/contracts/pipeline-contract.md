# Feedback pipeline contract

| Field | Value |
|---|---|
| Status | **Implemented** (PRs 1–7). |
| Scope | Feature IDs, protocol documents, lane semantics, FFI, catalog mapping, Crown Start refused. |
| Not this | Capture writer ([data-plane-contract.md](data-plane-contract.md)); `.neurofeed` header / computed field set ([fileformat_v6.md](fileformat_v6.md)); Connect UX; SoLoud internals ([../audio-engine.md](../audio-engine.md)); Crown *session run*. |

Do not reopen [Key Decisions](#key-decisions). **Crown Start stays refused.**

Implemented map: [../feedback/architecture.md](../feedback/architecture.md).
Catalog copy: `assets/features.json`, `assets/protocols.json` (file version **4**).
PR history: [../archive/pipeline-contract-pr-plan.md](../archive/pipeline-contract-pr-plan.md).

`DeviceKind` is Muse | Neurosity. Simulation is `simulate` + `sim:*`, not extra kind variants.

---

## Ownership

| Concern | Owner |
|---|---|
| BLE / Crown OSC / raw packets | Rust |
| Always-on bands, movement, peak-alpha, line-noise, gestures | Rust |
| Pad quality 0–100 for autodrop | Rust forwarder |
| Pad quality UI dots (Muse 4-slot) | Dart `connection_provider` (keep formula in sync) |
| Band-derived features (`band.atr` …) | Rust, from the same FFT; autodrop in the producer |
| AI labels (`ai.*`) | Rust analysis; Dart loads the model and consumes samples |
| Device-native (`device.focus`, `device.calm`) | Rust `neurosity_osc.rs` as `FeatureDto` |
| Threshold math (`percentileUptrain`, `percentileWarn`) | Dart lanes; protocol **names** the policy |
| Inhibit AND-gate | Dart RewardLane |
| Output mapping | Dart output methods; protocol names the output ID |
| Protocol documents | JSON (IDs only) |
| Feature copy + `usableFor` | `assets/features.json` |
| Producer registry (electrodes, rate, exists-on-device) | Rust `available_features` |

JSON names IDs. Code owns behavior. Availability is derived from the
last-connected / selected device + installed models, not copied into every
protocol row.

The catalog **may list** band protocols when the selected kind is Crown.
**Running** a catalog protocol on Crown is out of scope. The orchestrator
refuses Start on Crown (`DeviceKind.neurosity`, real or simulated).

---

## Glossary

| Word | Meaning |
|---|---|
| **protocol** | Wiring document (catalog or user). UI may say "Programs". |
| **feature** | ATR, TAR, BTR, relative alpha, AI label, Crown focus/calm. Not OSC/LSL/BrainFlow. |
| **reward** | Uptraining lane: feature → threshold + inhibit → reward output. |
| **inhibit** | AND-gates on the **reward verdict** (`betaCeiling`, `deltaCeiling`). Never a separate alarm. |
| **guard** | Independent alert lane. Never modulates the reward scalar or `inTarget`. |
| **output / modality** | What a lane drives: `chime`, `musicFilter`, `rainStage`, `binauralSwell`, `cough`, `alarm`, … |
| **background** | Ambient soundscape, **not** mapped to a feature. |
| **producer electrodes** | Montage channels the feature reads. |
| **gate electrodes** | Continue-anyway + playing-phase pause. **Not** the AI window. |

---

## Always-on vs subscribed

**Always-on** (never gated by `set_enabled_features`):

- Per-electrode `BandsDto`
- Movement, pulse, SpO₂, peak-alpha, telemetry, IMU, raw EEG (record filter: `Settings.recordStreams`)
- Gestures
- Pad quality 0–100 in the forwarder (not a `MuseEventDto` variant)

**Subscribed** (replace-set via `set_enabled_features`):

- Band-derived features as `FeatureDto` **only while enabled**
- `ai.*`, `device.focus` / `device.calm`

Default enabled set is **empty**. `set_enabled_features([])` at process init and session end. Duplicate ids are deduped. A disabled guard is not enabled just because the document has a `guard` object.

**Missing sample = no sample**, not `0.0`. Dart lanes hold last output and do not `recordEpoch`.

### Two scalars

| Scalar | Where | Used by |
|---|---|---|
| Native value | `FeatureDto.value` | `FeedbackEngine` baseline / `isInTarget`; guard threshold |
| Percentile rank (0–100 vs this session's baseline) | Dart `FeedbackEngine.percentileOf` | Continuous reward outputs |

---

## Inhibit ≠ guard

```
reward feature → percentileUptrain ─┐
relative bands on reward electrodes ─┴→ inTarget → reward output

guard feature → percentileWarn → guard output   (independent)
```

Inhibit failure ⇒ `inTarget = false` ⇒ no reward. It does **not** play a warning.
Guard warning / muffle does **not** change `inTarget`.

Inhibit **fails closed** if the relative-band vector for the reward electrodes is missing: `inTarget = false`.

`band.delta` as a **guard** is absolute δ µV²/Hz average on AF7/AF8. Relative delta for **inhibit** comes from always-on `BandsDto` totals, not from this feature ID. Do not conflate the two.

---

## Feature catalog (v1 freeze)

Producer registry in Rust. Copy + `usableFor` in `assets/features.json`. No Dart enum. Document parse **rejects** a lane whose feature is not listed for that lane.

| ID | Source | Native value | `usableFor` | Muse producer | Crown producer | Rate |
|---|---|---|---|---|---|---|
| `band.atr` | band | α/θ | reward | AF7, AF8 | PO3, PO4 | 1 Hz |
| `band.tar` | band | θ/α | reward | AF7, AF8 | PO3, PO4 | 1 Hz |
| `band.btr` | band | β/θ | reward | AF7, AF8 | PO3, PO4 | 1 Hz |
| `band.alpha` | band | α / total | reward | AF7, AF8 | PO3, PO4 | 1 Hz |
| `band.delta` | band | absolute δ µV²/Hz avg | guard | AF7, AF8 | PO3, PO4 | 1 Hz |
| `ai.drowsiness` | ai | `sleep_dir` | guard | AF7, AF8, TP9, TP10 | **unavailable** | 1 Hz |
| `device.focus` | device | Crown OSC 0–1 | reward, guard | **unavailable** | n/a | ~4 Hz |
| `device.calm` | device | Crown OSC 0–1 | reward, guard | **unavailable** | n/a | ~4 Hz |

**Who wins:** availability = Rust `FeatureInfo.available`. Gear picker / `usableFor` = Dart JSON. Rust `usable_for` must match JSON for all eight ids.

Add a feature later: register producer in Rust, add a copy row to `features.json`, then name it from a protocol. Do not add Dart enum cases.

### Gate vs producer

Do **not** union every subscribed feature’s channels into one `needed_electrodes` (that would pause on TP9/TP10 whenever `ai.drowsiness` is on).

1. Reward lane on → gate = that feature’s **montage** producer electrodes (`device.*` have none — Crown run is OOS).
2. Else guard lane on → gate = that feature’s montage electrodes if it has them. **`ai.drowsiness` does not add TP9/TP10**; fall back to AF7/AF8 on Muse.
3. Else (`recordOnly`) → gate = AF7/AF8 on Muse.

Playing pause: **all gate pads** below `signal_critical_threshold` (40) for `badSignalPauseSeconds` (10). Rear pads never pause a frontal-gated session.

**`_allGreen` stays all montage pads** on Muse before calibration. Do not replace it with gate electrodes without an explicit product PR.

`DeviceConfig` montage is the index authority (`muse()` / `neurosity_crown()`). Protocol override: optional `reward.electrodes` / `guard.electrodes` as **names**, never indices. Rust rejects unknown names. Do not restore `const electrodeAf7 = 1` on the reward path.

Autodrop: 0–100 in the Rust forwarder (Muse: 1.0 **second** EEG ring, same std/noise formula as the Dart UI dots). Null/short quality → skip the sample. Crown `/signalQuality` 0–1 → 0–100 is defined for `band.*` computation; Crown **run** stays refused.

---

## Protocol documents

Catalog and user documents are the same type (`origin: catalog | user`). `ProtocolType` / `RewardMetric` / `GuardrailMode` enums are gone.

### Catalog IDs (on-disk forever)

`drowsiness`, `twilight`, `alertnessOpen`, `alertnessClosed`, `mindfulness`, `concentration`, `relaxedConcentration`, `recordOnly`, `guardrailOnly`

Unknown IDs **must not** fall back to `drowsiness` (`SessionMetadata`, SQLite list, crash recovery). List rows: `catalog.forName(id)?.copy` else raw id. Recent: catalog hit only (skip unknown). `protocolJson` is for detail / export / replay only.

User IDs: `user.<slug>` where `slug` is `[a-z0-9-]{3,64}`. Catalog IDs are reserved.

### Schema (document `schemaVersion` 1; catalog file `version` 4)

A protocol wires: optional `reward` (feature + output + policy + inhibit), optional `guard` (feature + output + policy + `muffleReward` + `defaultEnabled`), `background.kind`, calibration id, electrode **names** (omit = Rust default), copy strings, color.

**Do not put in JSON:** FFT bins, biquad math, percentile numbers, EMA alphas, electrode indices, model kinds, `usableFor`, device allow-lists.

Derived: `hasReward` ⇔ `reward != null`; guard allowed ⇔ `guard != null`; `recordOnly` ⇔ both lanes absent; `guardrailOnly` ⇔ reward absent, guard present.

Catalog rows lock `reward.feature` (and `inhibit` when non-empty). They do **not** lock `guard.feature` (gear may switch `band.delta` ↔ `ai.drowsiness`).

`requiredElectrodes` / `allowedDevices` stay **deleted**. Removing them is not a Crown unlock.

### Catalog mapping (do not guess)

| ID | `reward.feature` | inhibit | `guard` | muffleReward | defaultEnabled | `reward.locked` | calibration | skippable |
|---|---|---|---|---|---|---|---|---|
| `drowsiness` | `band.atr` | none | `band.delta` | true | true | `feature` | `eyes-closed-01` | no |
| `twilight` | `band.tar` | none | `band.delta` | true | true | `feature` | `eyes-closed-01` | no |
| `alertnessOpen` | `band.btr` | none | **omit** | — | — | `feature` | `eyes-open-01` | no |
| `alertnessClosed` | `band.btr` | none | `band.delta` | false | true | `feature` | `eyes-closed-01` | no |
| `mindfulness` | `band.alpha` | none | `band.delta` | false | true | `feature` | `eyes-closed-01` | no |
| `concentration` | `band.alpha` | betaCeiling 0.25 | `band.delta` | false | true | `feature`, `inhibit` | `eyes-closed-01` | no |
| `relaxedConcentration` | `band.atr` | betaCeiling 0.25 **and** deltaCeiling 0.5 | `band.delta` | true | true | `feature`, `inhibit` | `eyes-closed-01` | no |
| `recordOnly` | **omit** | — | **omit** | — | — | — | `eyes-closed-01` | **yes** |
| `guardrailOnly` | **omit** | — | `band.delta` | false | true | — | `eyes-closed-01` | no |

Any document **with** a `guard` object defaults ON (`band.delta`) when no pref exists. Documents without `guard` default to **none**. Do not honor unused v3 `guardrailDefault: false`.

### Listing vs running

List filter = last-connected / currently connected `DeviceKind` this process; if none, show all catalog rows. Band protocols **list** on Crown; **Start is refused**. `ai.drowsiness` stays unavailable on Crown. `recordOnly` lists on every known kind; Start on Crown is still refused.

---

## Guard settings

Per-protocol remaining knobs: **on/off** and **band vs AI**. The installed model is **global**.

| Key | Role |
|---|---|
| `guardrail_mode` | `protocolId → { "feature": "band.delta"\|"ai.drowsiness"\|"none" }` |
| `guard_model` | Global model id or unset |
| `warning_sound` | global |
| `reve_warning_threshold_percentile` | global |

`ai.drowsiness` is the only v1 AI label. Eager migrate already ran: old `GuardrailMode.name` → the object shape; first catalog AI id in freeze order filled `guard_model`.

**Keep writing `GuardrailMode.name` into `SessionSettings.guardrailEngine`** (`drowsinessMath`, …). Also write `guardFeature` + `guardModel`. Do not start writing `bandMath` / `luna_base` into `guardrailEngine`. Readers accept `name`, then `ffId`, then camel `lunaLarge`.

---

## Threshold policies (code-owned)

| Policy | Lane | Behavior |
|---|---|---|
| `percentileUptrain` | reward | `RatioEngine`: baseline percentile (default 40); `adapt()` every 30 s wall-clock; ceiling `baselineMean + 1.5·sd`; floor = initial percentile; success=0 circuit breaker. `isInTarget` = native > threshold, then inhibit AND-gates. |
| `percentileWarn` (band-math) | guard | Rest native `band.delta` → warning percentile (default 75). Warn if live native > threshold **or** > `guardrailDeltaCeiling` (0.25). |
| `percentileWarn` (AI) | guard | Rest `sleep_dir` → same percentile. Warn if live `sleep_dir` > threshold **or** absolute frontal delta > 0.25 (always-on bands, **not** the AI `FeatureDto`). |

`epochWindowSeconds = 75` (wall-clock). Do **not** switch to 30 one-Hz `FeatureDto` samples. `adaptIntervalSeconds = 30` stays wall-clock.

The comment/code unit mismatch on `guardrailDeltaCeiling` (comment says normalized; code uses absolute µV²/Hz) is **preserved**. Fixing units is a later explicit science PR.

Cooldown `warningChimeCooldown` (20 s) for one-shots; continuous alarm ramps while active.

---

## Computed 1 Hz (no layout change)

| Field | Write |
|---|---|
| `feedback.ratio` | reward **native** value |
| `feedback.threshold` / `inTarget` / `pct` | unchanged |
| `guardrail.sleepDir` | AI `sleep_dir`, or **0** for band-math |
| `guardrail.delta` | frontal **absolute** delta (µV²/Hz) |
| `guardrail.warning` / `clarity` | as today |

Do not stuff absolute delta into `sleepDir`. Do not add feature-id fields on the frame. Which feature ran lives in `protocolJson` / `SessionSettings.guardFeature`.

---

## Background vs reward vs guard outputs

Three layers. Do not collapse them. Muffle is `RewardOutput.setMuffle` (audio-engine freeze). Do not restore `AudioService.setMusicMuffle`. Do not duck unmodulated background.

| Layer | IDs |
|---|---|
| Background (unmapped) | `drone`, `droneLoop`, `rain`, `userMusic`, `binaural`, `none` |
| Reward | `chime`, `musicFilter`, `rainStage`, `binauralSwell`, `none` |
| Guard | existing `GuardrailSound`: `softBowl`, `chime`, `cough`, `alarm`, `none` |

**Muffle is not a GuardOutputId.** It is `guard.muffleReward: bool`.

Suppress (engine, not JSON): `rainStage` and `musicFilter` suppress background. `binauralSwell` layers under background. `chime` / `none` keep background.

---

## Calibration compose

`assets/calibrations.json` v2 is the clip library (`eyes-closed-01` / `eyes-open-01`, each with `single` and `staged`). Protocol points at one calibration id. Stages are composed from subscribed features `S`:

| Condition | Stages |
|---|---|
| `S` empty (`recordOnly`) | skippable; else `single` baseline only |
| any `ai.*` in `S` | `staged`: artifact + challenge + baseline |
| else any lane present | `single` baseline only |

Clips stay those in `calibrations.json` (artifacts 15 s, challenge 30 s, rest 45 s; `single` baseline **50 s**). Do not retune 15 s → 12 s here. Eyes-open vs closed comes from the calibration id.

---

## Feature FFI (names frozen)

`FeatureDto` is defined **once** in `rust/src/api/features.rs`. On `MuseEventDto`, not a side stream, **not** written to the `.neurofeed` raw body (`encode_session_event` no-ops `Feature` the same as `Reve` / Gestures).

| Fn | Rules |
|---|---|
| `available_features(kind)` | no headset required |
| `set_enabled_features(ids)` | replace-set; `[]` unsubscribes subscribed features; unknown / unavailable / always-on names → `Err`; dupes `Ok`; succeeds with no headset |
| `set_feature_electrodes(id, names)` | names, not indices; empty = reset default; allowed before enable; `device.*` → `Err`; unknown names → `Err`; `ai.drowsiness` on Crown → `Err` |

Reconnect does not re-enable; the orchestrator re-calls on session start.

---

## Key Decisions

1. **Inhibit ≠ guard.** Inhibit AND-gates the reward verdict. Guard never changes `inTarget` or the reward scalar.
2. **Background ≠ reward output ≠ guard output.** `muffleReward` is a guard-document bool; live muffle is `RewardOutput.setMuffle`.
3. **JSON names IDs; code owns behavior.** Protocols may say `band.atr` / `musicFilter` / `percentileUptrain`. They may not say FFT bins, biquads, or percentile math.
4. **Rust owns `(device, feature)` producer electrodes / rate / existence.** Protocol override is names. Gate electrodes are a second list: reward montage, else guard montage; **`ai.drowsiness` does not add TP9/TP10 to the gate.** `DeviceConfig` montage is the index authority. Do not change `DeviceConfig` FFI fields (`targetElectrodes` / `neededElectrodes` / `DeviceFeatures`) for Crown run.
5. **Always-on vs subscribed.** Bands, movement, gestures always-on. Pad quality 0–100 for autodrop is in the Rust forwarder; null/short quality skips the sample. Subscribe only `FeatureDto` producers. Default enabled set is empty.
6. **Band-derived features computed in Rust** from the FFT already running, autodropped there. Do not restore Dart `scalarForFeature` or `electrodeAf7` on the reward path. Charts may keep 4-ch names until the Crown-run series.
7. **Missing sample = no sample**, not 0.
8. **Two scalars:** native value on `FeatureDto`; percentile rank in Dart `FeedbackEngine`.
9. **Calibration composed from subscribed features**, using existing `single`/`staged` clips. AI in `S` → three stages; otherwise baseline; record-only skippable.
10. **`ProtocolType` stays gone.** Keep the nine current IDs. Unknown IDs do not become `drowsiness`. Snapshot `protocolJson` for detail/export/replay.
11. **`GuardrailMode` stays split** into guard feature vs **global** model. Document with `guard` defaults ON (`band.delta`); without `guard` → none. `guardrailEngine` **keeps writing `GuardrailMode.name`**.
12. **Availability is derived.** Catalog **may list** band protocols on Crown; **running them is out of scope**. List filter = connected/last `DeviceKind`, else show all.
13. **`FeatureDto` on `MuseEventDto`**, type in `features.rs`, not a side stream, not written to the `.neurofeed` raw body.
14. **v1 feature IDs frozen** (all eight rows); add more via registry + JSON, no Dart enum.
15. **Custom builder is a form over the document.** Catalog and a hand-built user JSON run the same path (on Muse).
16. **`epochWindowSeconds = 75`.** Not 30 s.
17. **`percentileWarn` preserves today’s code split** (band-math native `band.delta` vs rest percentile **and** vs 0.25; AI `sleep_dir` vs rest percentile **and** absolute frontal delta vs 0.25). Unit mismatch is a later science PR.
18. **Computed frames stay ATR/sleep_dir-shaped.** No feature-id fields on the frame.
19. **`_allGreen` stays all montage pads** on Muse. Playing pause uses **gate** electrodes only.

---

## Still out of scope

- Unlocking Crown sessions (quality length, `ComputedFrame.bands` length, name-based chart electrodes).
- Changing the `.neurofeed` (NFED6) container / raw body / computed columnar layout.
- SQLite schema redesign.
- Medical-device claims.
- Silently switching `guardrailDeltaCeiling` to relative-δ.
