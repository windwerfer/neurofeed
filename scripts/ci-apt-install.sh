#!/usr/bin/env bash
# Retry apt-get install on GitHub-hosted Ubuntu runners. Azure and
# security.ubuntu.com DNS often fail transiently ("Temporary failure resolving
# azure.archive.ubuntu.com" / "security.ubuntu.com"), which cancelled rust-ci
# and dropped Linux release assets. Fall back to archive.ubuntu.com.
set -euo pipefail
if [ "$#" -eq 0 ]; then
  echo "usage: $0 package [package...]" >&2
  exit 2
fi

fallback_mirrors() {
  echo "Falling back to archive.ubuntu.com (runner apt mirror / DNS unreachable)"
  if [ -f /etc/apt/apt-mirrors.txt ]; then
    printf 'http://archive.ubuntu.com/ubuntu\n' | sudo tee /etc/apt/apt-mirrors.txt >/dev/null
  fi
  sudo sed -i \
    -e 's|https\?://azure\.archive\.ubuntu\.com/ubuntu|http://archive.ubuntu.com/ubuntu|g' \
    -e 's|https\?://security\.ubuntu\.com/ubuntu|http://archive.ubuntu.com/ubuntu|g' \
    /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true
}

sudo tee /etc/apt/apt.conf.d/99-neurofeed-retries >/dev/null <<'CFG'
Acquire::Retries "5";
Acquire::https::Timeout "20";
Acquire::http::Timeout "20";
CFG

if ! getent hosts azure.archive.ubuntu.com >/dev/null 2>&1 \
   || ! getent hosts security.ubuntu.com >/dev/null 2>&1; then
  fallback_mirrors
fi

for i in 1 2 3 4 5; do
  if sudo apt-get update && sudo apt-get install -y --no-install-recommends "$@"; then
    exit 0
  fi
  echo "apt failed (attempt $i); retrying..."
  fallback_mirrors
  sleep 15
done
exit 1
