# neurofeed-android

The NeuroFeed egui app as an Android APK: GameActivity (android-activity) plus `libneurofeed.so`.
There's no Flutter and no webview.

- Rust: `src/android.rs` holds `android_main`, the JNI bridge and the platform hooks (SAF, keep-screen-on, pause → checkpoint).
- BLE: btleplug through droidplug. The Java helpers are vendored under `android/app/src/main/java` and were copied from the old Flutter app. `nativeInit` runs from `MainActivity.onCreate`.
- Kotlin: `MainActivity` handles permissions and SAF. `CaptureService` is the connectedDevice foreground service and runs while a session is active.
- App id: `org.windwerfer.neurofeed.rs` (debug builds: `org.windwerfer.neurofeed.rs.debug`, so both install side by side). To change it, pass `-PappId=…` (the Kotlin package stays `org.neurofeed.android`).
- Version: taken from the newest git tag `X.Y.Z` (versionCode X*10000+Y*100+Z).
- F-Droid metadata: `fastlane/metadata/android/en-US`.

## Build

```sh
. /home/box/sdk/env-android.sh            # JAVA_HOME, ANDROID_HOME, NDK 27.2
cd apps/neurofeed-android/android
./gradlew assembleDebug                   # all ABIs: arm64-v8a, armeabi-v7a, x86_64
./gradlew assembleDebug -Pabis=x86_64     # emulator only
../../../scripts/build-android.sh           # release APK per ARM ABI -> dist/ (docs/release.md)
../../../scripts/build-android.sh --fast    # quick local iteration: arm64 debug APK -> dist/*-fast-debug.apk
```

`--fast` is for local iteration only (not reproducible, never for releases): Gradle daemon +
build cache + parallel, Rust built incrementally with `[profile.android-fast]` (root
`Cargo.toml`: opt-level 2, no LTO, 256 codegen units; fast enough for BLE/live bands), and
jniLibs/APK outputs are kept so caches stay warm. Add `--abis` to pick other ABIs.

Gradle calls `cargo ndk` (`cargo install cargo-ndk`; rustup targets aarch64/armv7/x86_64-linux-android).
