#!/usr/bin/env bash
# Regenerate the Gradle dependency lockfiles for the Android wrapper.
# Run this after changing any dependency or plugin version, then commit
# the changed *.lockfile files together with that change.
set -euo pipefail

cd "$(dirname "$0")/../apps/neurofeed-android/android"
./gradlew --no-daemon :app:dependencies --write-locks >/dev/null
echo "Lockfiles updated:"
git status --short -- '*.lockfile'
