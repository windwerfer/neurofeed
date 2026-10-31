#!/usr/bin/env bash
# Print the NeuroFeed version used by every build (scripts/*, Gradle, release.yml):
#   1. $NEUROFEED_VERSION if set (local override; scripts also take --version)
#   2. git tag X.Y.Z / vX.Y.Z on HEAD           -> X.Y.Z
#   3. nearest such tag, `git describe` style   -> X.Y.Z-<commits>-g<sha>
#   4. no tag (e.g. tarball, shallow clone)     -> version from Cargo.toml
# Only plain release tags count; tags such as 0.1.0-ai_guardrail-01 are ignored.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${NEUROFEED_VERSION:-}" ]]; then echo "${NEUROFEED_VERSION#v}"; exit 0; fi
v="$(git -C "$ROOT" describe --tags --match '[0-9]*' --match 'v[0-9]*' --exclude '*[!0-9.v]*' 2>/dev/null || true)"
if [[ -n "$v" ]]; then echo "${v#v}"; exit 0; fi
sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT/Cargo.toml" | head -1
