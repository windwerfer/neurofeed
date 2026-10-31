# Releases and packaging

Publishing a GitHub release (tag `vX.Y.Z`) runs `.github/workflows/release.yml`, which builds
every platform and attaches the assets with `gh release upload`:

| Asset | Job | Local script |
|---|---|---|
| `neurofeed-X.Y.Z-arm64-v8a.apk`, `neurofeed-X.Y.Z-armeabi-v7a.apk` (signed) | `android` (`_android-apk.yml`) | `scripts/build-android.sh` |
| `neurofeed-X.Y.Z-linux-x86_64.tar.gz`, `neurofeed-X.Y.Z-x86_64.AppImage` | `linux` (Ubuntu 22.04, glibc 2.35) | `scripts/package-linux.sh` |
| `neurofeed-X.Y.Z-x86_64.flatpak` | `flatpak` (`flatpak/org.windwerfer.neurofeed.yml`) | `scripts/package-flatpak.sh` |
| `neurofeed-X.Y.Z-windows-x64.zip` (portable) | `windows` | `scripts/package-windows.ps1` |
| `neurofeed-X.Y.Z-macos-arm64.dmg` | `macos` | `scripts/package-macos.sh` |
| `SHA256SUMS.txt` | `upload` | |

Test run without a release: *Actions → release → Run workflow* with `dry-run` checked (default):
everything builds, the artifacts stay on the run, nothing is uploaded. With a `tag` and
`dry-run` off, the assets go to that existing release.

## Android

- One APK per ABI, ARM only (a fat APK is twice the size). x86_64 only as a debug APK in push CI
  (`android.yml`) for the emulator.
- **versionCode** = `(X*10000 + Y*100 + Z) * 10 + abi`, abi digit `1` armeabi-v7a, `2` arm64-v8a,
  `3` x86, `4` x86_64, `0` universal. Example 0.9.2: armv7 `9021`, arm64 `9022`. arm64 is higher so
  64-bit devices always take it; this is the scheme F-Droid's `VercodeOperation` expects
  (`10 * %c + 1`, `10 * %c + 2`). Version name comes from the tag (`-PversionName`), else `git describe`.
- Signing: repo secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEYSTORE_ALIAS`, `KEY_PASSWORD`
  (APK Signature Scheme v2 + v3; minSdk 26). The release job fails without them and verifies
  every APK with `apksigner`. Without secrets the release APK is unsigned (push CI, F-Droid).
- Reproducible: `.github/workflows/repro-android.yml` (manual + weekly) builds twice on separate
  runners with one throwaway key and compares sha256 per ABI. Pinned: Rust 1.99.1, NDK
  27.2.12479018, build-tools 35.0.0, cargo-ndk 4.1.2, Gradle 8.14 / AGP 8.11.1, JDK 17;
  `SOURCE_DATE_EPOCH` = commit time, `--remap-path-prefix` for the checkout, cargo and rustup
  paths, no Gradle build cache, fresh `jniLibs`.

## macOS

Same approach as PhotoCraft: `NeuroFeed.app` (Apple Silicon, macOS 11+) on a drag-to-Applications
DMG built with `hdiutil makehybrid` + `convert`, signed inside-out. Without a Developer ID it is
ad-hoc signed (`MACOS_SIGN_IDENTITY=-`, not notarized): users open it once via right-click → Open.
