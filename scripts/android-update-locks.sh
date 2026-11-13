#!/usr/bin/env bash
# Regenerate the Gradle dependency lockfiles and verification metadata
# for the Android wrapper.
# Run this after changing any dependency or plugin version, then commit
# the changed *.lockfile and gradle/verification-metadata.xml files
# together with that change.
#
# Lockfiles pin versions; gradle/verification-metadata.xml pins sha256
# checksums of every artifact the wrapper, plugins, and assemble tasks
# resolve. Rust native builds are skipped because they don't add Maven
# artifacts. assembleDebug/assembleRelease are included so CI does not
# fail later on a missing checksum.
# Incremental: existing checksums are kept, so platform-specific
# artifacts recorded on another OS (e.g. aapt2 osx/windows jars) are
# not dropped when this is run on Linux.
set -euo pipefail

cd "$(dirname "$0")/../apps/neurofeed-android/android"

# Pin versions for every resolvable configuration (root + :app).
./gradlew --no-daemon dependencies :app:dependencies --write-locks

# Refresh sha256 checksums. Incremental: existing trusted entries are kept,
# newly resolved artifacts are added. Use the assemble tasks from
# scripts/build-android.sh so the set matches CI.
./gradlew --no-daemon --write-verification-metadata sha256 \
  help dependencies :app:dependencies \
  :app:assembleDebug :app:assembleRelease \
  -x cargoBuildDebug -x cargoBuildRelease

echo "Lockfiles and verification metadata updated:"
git status --short -- '*.lockfile' 'gradle/verification-metadata.xml'
