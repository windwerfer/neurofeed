#!/usr/bin/env bash
# Retry apt-get install on GitHub-hosted Ubuntu runners.
#
# Runners sometimes have a broken stub resolver, which shows up as
# "Temporary failure resolving azure.archive.ubuntu.com",
# "security.ubuntu.com", or even "archive.ubuntu.com". That cancelled
# rust-ci and dropped Linux release assets. Fix DNS first, then fall
# back to archive.ubuntu.com and retry apt.
set -euo pipefail
if [[ "$#" -eq 0 ]]; then
  echo "usage: $0 package [package...]" >&2
  exit 2
fi

fix_dns() {
  if timeout 3 getent hosts archive.ubuntu.com >/dev/null 2>&1 \
     && timeout 3 getent hosts security.ubuntu.com >/dev/null 2>&1; then
    return 0
  fi
  echo "Runner DNS failed; switching /etc/resolv.conf to 1.1.1.1 / 8.8.8.8"
  if [[ -L /etc/resolv.conf ]]; then
    sudo rm -f /etc/resolv.conf
  fi
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\noptions timeout:2 attempts:3\n' | sudo tee /etc/resolv.conf >/dev/null
}

fallback_mirrors() {
  echo "Falling back to archive.ubuntu.com (runner apt mirror / DNS unreachable)"
  if [[ -f /etc/apt/apt-mirrors.txt ]]; then
    printf 'http://archive.ubuntu.com/ubuntu\n' | sudo tee /etc/apt/apt-mirrors.txt >/dev/null
  fi
  sudo sed -i \
    -e 's|https\?://azure\.archive\.ubuntu\.com/ubuntu|http://archive.ubuntu.com/ubuntu|g' \
    -e 's|https\?://security\.ubuntu\.com/ubuntu|http://archive.ubuntu.com/ubuntu|g' \
    /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null || true
}

fix_dns
fallback_mirrors

sudo tee /etc/apt/apt.conf.d/99-neurofeed-retries >/dev/null <<'CFG'
Acquire::Retries "5";
Acquire::https::Timeout "20";
Acquire::http::Timeout "20";
CFG

for i in 1 2 3 4 5; do
  if sudo apt-get update && sudo apt-get install -y --no-install-recommends "$@"; then
    exit 0
  fi
  echo "apt failed (attempt $i); retrying..."
  fix_dns
  fallback_mirrors
  sleep 15
done
exit 1
