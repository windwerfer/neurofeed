# Architecture

```text
 BandSource (trait) ──poll(now)──▶ app.rs ──push──▶ AppState.bands
                                     │                  │
                                     │      &AppState   ▼
                                     └──── ui::show ◀── render
                                              │
                                        Vec<Action> ──▶ AppState::apply
```

Each frame (`app.rs`):
1. If not paused, `source.poll(time)` may return a new `BandSnapshot`, which is
   pushed into a bounded ring buffer (`BandHistory`, 600 entries ≈ 60 s).
2. `ui::show(ctx, &state)` draws everything and returns `Action`s.
3. Actions are applied to state. Repaint is requested every 100 ms.

## Data model

- `Band`: Delta 1–4, Theta 4–8, Alpha 8–13, Beta 13–30, Gamma 30–44 Hz.
- `BandSnapshot { time, powers: Vec<[f32; 5]> }`: per-channel absolute power in
  log10 units (Muse convention). `relative()` converts to share of total.
- `DeviceInfo { name, channels, simulated }`.

## Plugging in a real device

Implement `BandSource` (non-blocking `poll`). For a Muse/Crown stream, run the
transport elsewhere (a thread on desktop, a WebSocket/WebBluetooth callback on
web) and have `poll` drain a channel. Then construct the app with
`NeuroFeedApp::with_source(Box::new(MySource::new()))`.
