# Release builds (GitHub Actions)

Release automation lives in `.github/workflows/`. Each platform has its **own
workflow file**, so you can enable/disable them individually (rename a file to
`.disabled.yml`, or delete it, to turn a platform off).

| Workflow | File | Trigger | Produces |
|----------|------|---------|----------|
| Android | `release-android.yml` | `release` (published) | signed `muse_ml-<ver>.apk` |
| Linux | `release-linux.yml` | `release` (published) | `muse_ml-<ver>-linux-x86_64.tar.gz` + best-effort `.AppImage` |
| Windows | `release-windows.yml` | `release` (published) | `muse_ml-<ver>-windows-x64.zip` |
| Reproducibility check | `repro-android.yml` | manual (`workflow_dispatch`) | byte-identical APK verification |
| Shared Android build | `_build-apk.yml` | called by Android workflows (do not trigger) | — |

All three release workflows also accept `workflow_dispatch` with an optional
`tag` input: leave it empty to do a **build-only test run** (nothing is
uploaded), or fill it in to attach assets to an existing release.

When a release is **published**, each workflow builds the tag's commit and
uploads its assets to that release with `gh release upload --clobber`
(so re-runs overwrite).

## One-time setup: signing keystore

Android release APKs are signed with a keystore you own. The keystore is
**not** committed (`.gitignore` already excludes `*.jks`, `*.keystore` and
`key.properties`). It is stored in GitHub as a base64-encoded **secret**.

The app reads signing config from `android/key.properties` (also gitignored),
which the CI job generates from the secrets.

### 1. Create a keystore

Run this once on your machine (back it up somewhere safe — losing it means you
can never update the app in place):

```bash
keytool -genkeypair -v \
  -keystore release-keystore.jks \
  -alias release \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass <your-store-password> -keypass <your-key-password> \
  -dname "CN=Your Name, OU=Org, O=Org, L=City, ST=State, C=DE"
```

### 2. Add the secrets to GitHub

1. Go to repo → **Settings → Secrets and variables → Actions → New repository
   secret**.
2. Add these four secrets:

| Secret | Value |
|--------|-------|
| `KEYSTORE_BASE64` | `base64 -w0 release-keystore.jks` output (Linux/macOS) or `certutil -encode -f release-keystore.jks tmp.b64` on Windows |
| `KEYSTORE_PASSWORD` | the `-storepass` value |
| `KEYSTORE_ALIAS` | the `-alias` value (e.g. `release`) |
| `KEY_PASSWORD` | the `-keypass` value |

To generate the base64 on Linux/macOS:

```bash
base64 -w0 release-keystore.jks   # copy the single line into KEYSTORE_BASE64
```

> The release workflow **fails** if these secrets are missing when triggered by
> a real `release` event (it refuses to ship an unsigned/debug-signed APK).

### 3. Local builds without the keystore

If `android/key.properties` is absent, the Gradle build falls back to the
debug signing key, so local `flutter build apk --release` keeps working. When
you want to build a signed release locally, create `android/key.properties`
(replace with your values):

```properties
storeFile=release-keystore.jks
storePassword=your-store-password
keyAlias=release
keyPassword=your-key-password
```

and put `release-keystore.jks` in `android/app/`.

## F-Droid

The goal "an APK that can be given to F-Droid without changes" works like this:

- **F-Droid builds from source on their own servers** and signs with their own
  key. Your keystore is only used for your GitHub-release APK (direct
  installs). So the thing F-Droid actually needs is not the signed APK but a
  **reproducible build** — when their build farm rebuilds your tag, they must
  get a byte-identical APK.
- The `repro-android.yml` workflow exists to prove this: it builds the same
  commit twice in parallel with the same keystore and fails unless the two
  APKs are byte-identical. Run it from the Actions tab
  (Actions → **repro-android** → *Run workflow*).
  For a real end-to-end check, configure the signing secrets first.
- Tooling is pinned so rebuilds match:
  - Flutter `3.41.7` stable (update `FLUTTER_VERSION` in the workflows when you
    bump Flutter — keep it in sync with `.metadata`)
  - Rust `1.97.1` (via `rust/rust-toolchain.toml`; the toolchain file makes
    local builds match CI too)
  - Gradle wrapper `8.14`, AGP `8.11.1`, Kotlin `2.2.20`
  - NDK version is read from the pinned Flutter's default and installed
    explicitly
  - `pubspec.lock` and `rust/Cargo.lock` are committed, so pub/cargo
    dependencies are frozen
  - Gradle archive tasks use fixed timestamps + deterministic ordering
    (`android/app/build.gradle.kts`); CI also disables parallel builds and
    caching for the Android build
  - AGP's non-deterministic extras are disabled in `android/app/build.gradle.kts`:
    the "Dependency Info" block (id `0x504b4453`, embedded in the APK Signing
    Block, encrypted and randomized per build) via
    `dependenciesInfo { includeInApk = false }`, and the VCS-info file
    (`META-INF/version-control-info.textproto`, env-dependent) via
    `vcsInfo { include = false }`
- The APK is a single fat APK (all ABIs), which F-Droid prefers.
- When you submit to F-Droid you will also need to request an app entry in
  `fdroiddata` (metadata + build recipe). Reproducibility issues they commonly
  hit — timestamps, R8 nondeterminism, native-strip paths — are documented at
  f-droid.org/docs/Reproducible_Builds; if `repro-android.yml` ever reports a
  diff, that page plus `diffoscope` are the way to find it.

## Linux

- `muse_ml-<ver>-linux-x86_64.tar.gz` is a portable bundle of the Flutter
  release output. Extract it anywhere and run `./muse_ml` from inside the
  extracted directory — no root, no install. It needs GTK3 system libraries
  (the usual desktop environment provides them).
- The tarball is built deterministically (fixed mtime, sorted entries) so it is
  reproducible across runs.
- An `.AppImage` is also produced as a best-effort step; if AppImage tooling
  fails it never blocks the tarball upload.
- The Rust crate compiles the btleplug/dbus stack, so the runner installs
  `libdbus-1-dev` and `libglib2.0-dev` (this is why the build host needs a few
  extra apt packages).

## Windows (optional)

- The Windows runner scaffolds the `windows/` platform folder itself
  (`flutter create --platforms=windows`), so nothing extra needs to be checked
  in to build it.
- `muse_ml-<ver>-windows-x64.zip` contains the `Release/` folder — unzip and
  run `muse_ml.exe`.
- `media_kit_libs_windows_audio` was added to `pubspec.yaml` so the media-kit
  audio player actually ships `libmpv` on Windows. If you do not care about
  Windows, delete `release-windows.yml` and the dependency.

## Caching

Each run starts from a fresh runner; to save bandwidth the workflows enable
caching (Flutter SDK + pub deps, rustup toolchain + cargo registry, Gradle
downloads). GitHub evicts cache entries not accessed for **7 days** (and caps
total cache at 10 GB per repo), so with release-only frequency the caches may
be gone before the next release. Running the manual `workflow_dispatch` test
builds between releases keeps them warm.

## Troubleshooting

- **"sdkmanager not found"**: the GitHub Ubuntu image layout changed; the
  workflow searches `$ANDROID_HOME` for `cmdline-tools` first.
- **Release APK is debug-signed**: the signing secrets are missing. Set the
  four secrets above and re-run the workflow.
- **`[patch]` silently ignored in Cargo**: the btleplug fork must stay at
  `version = "0.11.8"` (see `.ai/btleplug.md`). `rust/Cargo.lock` references
  the fork commit; if Cargo rewrites it, keep it.
- **Repro reports a diff**: the usual culprit is AGP's "Dependency Info" block
  (id `0x504b4453`) in the APK Signing Block — it is non-deterministic
  (encrypted, randomized per build). `android/app/build.gradle.kts` disables it
  (`dependenciesInfo`) plus AGP's VCS-info file (`vcsInfo`); both settings must
  stay. If it still differs, compare the two APKs with `diffoscope` and inspect
  the signing block with `apksigtool parse`.
