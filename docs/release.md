# Releases and packaging

Publishing a GitHub release (tag `vX.Y.Z`) runs `.github/workflows/release.yml`, which builds
every platform and attaches the assets with `gh release upload`:

| Asset | Job | Local script |
|---|---|---|
| `neurofeed-X.Y.Z-arm64-v8a.apk`, `neurofeed-X.Y.Z-armeabi-v7a.apk` (signed) | `android` (`_android-apk.yml`) | `scripts/build-android.sh` |
| `neurofeed-X.Y.Z-linux-x86_64.tar.gz`, `neurofeed-X.Y.Z-x86_64.AppImage` | `linux` (Ubuntu 22.04, glibc 2.35) | `scripts/package-linux.sh` |
| `neurofeed-X.Y.Z-x86_64.flatpak` | `flatpak` (`flatpak/org.windwerfer.neurofeed.yml`) | `scripts/package-flatpak.sh` |
| `neurofeed-X.Y.Z-windows-x64.zip` (portable) | `windows` | `scripts/package-windows.ps1` |
| `neurofeed-X.Y.Z-macos-universal.dmg` (arm64 + x86_64) | `macos` | `scripts/package-macos.sh` |
| `neurofeed-web-X.Y.Z.zip` (static wasm site, unzip and serve over HTTP) | `web` (trunk) | `scripts/package-web.sh` |
| `SHA256SUMS.txt` | `upload` | |

Push CI (`rust-ci.yml`, job `wasm`) also runs `trunk build --release` and keeps the web
`dist/` as the `neurofeed-web` artifact (14 days). Trunk is pinned to 0.22.1 (`Trunk.toml`);
wasm-bindgen-cli follows the `wasm-bindgen` version in `Cargo.lock`.

Test run without a release: *Actions → release → Run workflow* with `dry-run` checked (default):
everything builds, the artifacts stay on the run, nothing is uploaded. With a `tag` and
`dry-run` off, the workflow on `main` checks out that tag (it does not move it) and uploads
to the existing release with `gh release upload --clobber`.

The macOS job runs on `macos-15` (Apple Silicon) and builds both `aarch64-apple-darwin` and
`x86_64-apple-darwin`, combined with `lipo` into one universal binary. GitHub retired `macos-14` on 2026-11-02;
jobs on that label are cancelled at queue time. Platform jobs already run in parallel; the
`upload` job still attaches whatever built if one platform is cancelled or fails, then fails
the workflow so a missing platform is not silent.

## Version

Every build takes its version from `scripts/version.sh` (Gradle, all `scripts/package-*`,
`release.yml`), in this order:

1. `--version X.Y.Z` on a script (`-Version` for `package-windows.ps1`, `-PversionName` for Gradle),
   or the env var `NEUROFEED_VERSION` (local override)
2. a release tag `X.Y.Z` / `vX.Y.Z` on HEAD → `X.Y.Z`
3. the nearest such tag, `git describe` style → `X.Y.Z-<commits>-g<sha>` (dev builds)
4. no tag at all (source tarball, shallow clone) → `version` in `Cargo.toml`

Only plain release tags count (`0.1.0-ai_guardrail-01` and the like are ignored). A published
release uses its tag. The scripts export `NEUROFEED_VERSION` into the cargo build, so the About
view, session files and MCP server report it (`nf_core::APP_VERSION`, Cargo.toml version when
unset). The version is a pure function of the commit, so reproducible builds stay reproducible.

## Android

- One APK per ABI, ARM only (a fat APK is twice the size). x86_64 only as a debug APK in push CI
  (`android.yml`) for the emulator.
- **versionCode** = `(X*10000 + Y*100 + Z) * 10 + abi`, abi digit `1` armeabi-v7a, `2` arm64-v8a,
  `3` x86, `4` x86_64, `0` universal. Example 0.9.2: armv7 `9021`, arm64 `9022`. arm64 is higher so
  64-bit devices always take it; this is the scheme F-Droid's `VercodeOperation` expects
  (`10 * %c + 1`, `10 * %c + 2`). versionName is the version above; versionCode uses its `X.Y.Z` (so Y and Z must stay below 100).
- Signing: repo secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEYSTORE_ALIAS`, `KEY_PASSWORD`
  (APK Signature Scheme v2 + v3; minSdk 26). The release job fails without them and verifies
  every APK with `apksigner`. Without secrets the release APK is unsigned (push CI, F-Droid).
- Reproducible: `.github/workflows/repro-android.yml` (manual + weekly) builds twice on separate
  runners with one throwaway key and compares sha256 per ABI. Pinned: Rust 1.99.1, NDK
  27.2.12479018, build-tools 35.0.0, cargo-ndk 4.1.2, Gradle 8.14 / AGP 8.11.1, JDK 17;
  `SOURCE_DATE_EPOCH` = commit time, `--remap-path-prefix` for the checkout, cargo and rustup
  paths, no Gradle build cache, fresh `jniLibs`.

## macOS

Same approach as PhotoCraft: `NeuroFeed.app` (universal: Apple Silicon + Intel, macOS 11+;
`MACOSX_DEPLOYMENT_TARGET=11.0` for both slices, `lipo -create`, `lipo -info` printed in the job log) on a drag-to-Applications
DMG built with `hdiutil makehybrid` + `convert` on the `macos-15` runner, signed inside-out.
Without a Developer ID it is ad-hoc signed (`MACOS_SIGN_IDENTITY=-`, not notarized): users open
it once via right-click → Open. There is no Apple Developer ID or notarization in CI.
