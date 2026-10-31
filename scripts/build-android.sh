#!/usr/bin/env bash
# Build NeuroFeed Android APKs, one per ABI (same steps as .github/workflows/
# release-android.yml and repro-android.yml).
#
#   scripts/build-android.sh [--abis arm64-v8a,armeabi-v7a] [--version 1.2.3] [--debug]
#
# Output: dist/neurofeed-<version>-<abi>.apk (release) or -<abi>-debug.apk.
# Signing (env, all four or none; unset = unsigned release APK):
#   KEYSTORE_BASE64 or NF_KEYSTORE (path), KEYSTORE_PASSWORD, KEYSTORE_ALIAS, KEY_PASSWORD
# Needs: ANDROID_HOME (platform 35, build-tools 35.0.0, NDK 27.2.12479018), JDK 17,
# cargo-ndk, rustup targets aarch64-linux-android armv7-linux-androideabi (x86_64-… for emulator).
#
# Reproducible: SOURCE_DATE_EPOCH = commit time, build paths remapped, no Gradle
# build cache, fresh jniLibs. Two builds of one commit give byte-identical APKs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ABIS=arm64-v8a,armeabi-v7a
VERSION=""
TYPE=release
while [[ $# -gt 0 ]]; do
  case "$1" in
    --abis) ABIS="$2"; shift 2 ;;
    --version) VERSION="${2#v}"; shift 2 ;;
    --debug) TYPE=debug; shift ;;
    -h | --help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
# Version: --version > $NEUROFEED_VERSION > git tag > Cargo.toml (scripts/version.sh); baked into the binary.
[[ -n "$VERSION" ]] && export NEUROFEED_VERSION="$VERSION"
VERSION="$("$ROOT/scripts/version.sh")"
export NEUROFEED_VERSION="$VERSION"
: "${ANDROID_HOME:?set ANDROID_HOME}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/27.2.12479018}"
BUILD_TOOLS="$ANDROID_HOME/build-tools/35.0.0"

# ---- reproducibility -------------------------------------------------------
SOURCE_DATE_EPOCH="$(git -C "$ROOT" log -1 --format=%ct)"
export SOURCE_DATE_EPOCH TZ=UTC LC_ALL=C CARGO_INCREMENTAL=0
CARGO_HOME_DIR="${CARGO_HOME:-$HOME/.cargo}"
RUSTUP_HOME_DIR="${RUSTUP_HOME:-$HOME/.rustup}"
export RUSTFLAGS="--remap-path-prefix=$ROOT=/neurofeed --remap-path-prefix=$CARGO_HOME_DIR=/cargo --remap-path-prefix=$RUSTUP_HOME_DIR=/rustup ${RUSTFLAGS:-}"
umask 022

# ---- signing ---------------------------------------------------------------
cleanup() { if [[ -n "${KS_TMP:-}" ]]; then rm -f "$KS_TMP"; fi; }
trap cleanup EXIT
if [[ -n "${KEYSTORE_BASE64:-}" && -z "${NF_KEYSTORE:-}" ]]; then
  KS_TMP="$(mktemp --suffix .jks)"
  printf '%s' "$KEYSTORE_BASE64" | tr -d '[:space:]' | base64 -d >"$KS_TMP"
  export NF_KEYSTORE="$KS_TMP"
fi
SIGNED=0
if [[ "$TYPE" = release && -n "${NF_KEYSTORE:-}" ]]; then
  export NF_KEYSTORE_PASSWORD="${NF_KEYSTORE_PASSWORD:-${KEYSTORE_PASSWORD:?}}"
  export NF_KEY_ALIAS="${NF_KEY_ALIAS:-${KEYSTORE_ALIAS:?}}"
  export NF_KEY_PASSWORD="${NF_KEY_PASSWORD:-${KEY_PASSWORD:-$NF_KEYSTORE_PASSWORD}}"
  keytool -list -keystore "$NF_KEYSTORE" -storepass "$NF_KEYSTORE_PASSWORD" -alias "$NF_KEY_ALIAS" >/dev/null \
    || { echo "error: keystore does not open (check KEYSTORE_BASE64 / KEYSTORE_PASSWORD / KEYSTORE_ALIAS)" >&2; exit 1; }
  SIGNED=1
else
  unset NF_KEYSTORE
fi

echo "==> NeuroFeed $VERSION Android $TYPE [$ABIS] signed=$SIGNED SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"
AND="$ROOT/apps/neurofeed-android/android"
rm -rf "$AND/app/src/main/jniLibs" "$AND/app/build/outputs/apk"
TASK=assembleRelease
[[ "$TYPE" = debug ]] && TASK=assembleDebug
(cd "$AND" && ./gradlew --no-daemon --no-build-cache -Dorg.gradle.parallel=false \
  "$TASK" -Pabis="$ABIS" -PversionName="$VERSION")

mkdir -p "$ROOT/dist"
IFS=, read -ra abi_list <<<"$ABIS"
for abi in "${abi_list[@]}"; do
  src=$(ls "$AND/app/build/outputs/apk/$TYPE/"app-"$abi"-"$TYPE"*.apk)
  if [[ "$TYPE" = debug ]]; then dst="$ROOT/dist/neurofeed-$VERSION-$abi-debug.apk"
  elif [[ "$SIGNED" = 1 ]]; then dst="$ROOT/dist/neurofeed-$VERSION-$abi.apk"
  else dst="$ROOT/dist/neurofeed-$VERSION-$abi-unsigned.apk"; fi
  cp "$src" "$dst"
  if [[ "$SIGNED" = 1 ]]; then
    "$BUILD_TOOLS/apksigner" verify --verbose --print-certs "$dst" | grep -v '^WARNING'
  fi
  "$BUILD_TOOLS/aapt2" dump badging "$dst" | sed -n 1p
  sha256sum "$dst"
done
