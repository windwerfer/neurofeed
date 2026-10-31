# Dependencies: supply-chain status

Checked 2026-10-31 with `cargo deny check` (cargo-deny 0.20.2) and `cargo audit`.
Policy: `deny.toml`; rule for new deps: AGENTS.md "Adding a dependency".
CI: `deny` job in `.github/workflows/rust-ci.yml` on every push and weekly (Mon 05:17 UTC).

## Ignored advisories (all transitive, no semver-compatible fix)

| Advisory | Crate | Via | Why acceptable now | Removed by |
|---|---|---|---|---|
| RUSTSEC-2026-0367/0368/0369 | zip 0.6.6, 2.6.1, 8.6.0 | rlx 0.2.19 (npyz, rlx-dduf), candle-core 0.11 | only `extract()` to disk is affected; never called | rlx / candle releases on zip >= 9 |
| RUSTSEC-2026-0391/0398/0403 | zstd 0.13.3, zstd-safe 5.0.2 / 7.3.0 | rlx-pkg, zip 0.6 | decodes only model packages we bundle (trusted) | rlx update |

Cleared by the 2026-10-31 update round: RUSTSEC-2026-0194/0195 (quick-xml 0.30,
gone with egui/eframe 0.37 / accesskit 0.25) and the unmaintained / unsound
warnings that came with it (bincode 1, paste, ttf-parser 0.25, unsafe-libyaml,
zbus_names 3 / zvariant 4). Still reported (warnings, not failing): 28
duplicate-version entries (objc2/windows-*, rustix, syn, base64, jni-sys, ...),
4 allowed-but-unused licenses, and muse-rs without a license field (clarified).

## Exceptions

- `vendor/rlx-cpu-0.2.19`: vendored via `[patch.crates-io]` (default BLAS
  feature disabled, f8411d4). Path source, so not source-checked; advisories
  still match crates.io rlx-cpu 0.2.19. `rlx` stays pinned `=0.2.19`, because
  `cargo update` would move the rlx-* sub-crates to 0.2.19 without moving the pin.
- `muse-rs` (our fork, rev e4891ba): has an Apache-2.0 LICENSE file but no
  `license` field, so it's clarified in deny.toml.
