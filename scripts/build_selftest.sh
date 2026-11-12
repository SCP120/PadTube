#!/bin/bash
# Self-test build for the iPad (tests/device). Always clean: theos does not rebuild objects when only -D flags
# change, so a release build followed by a self-test build would mix both.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export THEOS="${THEOS:-$HOME/theos}" PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
mkdir -p "$ROOT/build/ipad/selftest-pkg"
rm -f "$ROOT"/build/ipad/selftest-pkg/*.deb
LOG="$ROOT/build/ipad/selftest-build.log"
if ! make -s -C "$ROOT/ios" clean package FINALPACKAGE=1 SELFTEST=1 THEOS_PACKAGE_DIR="$ROOT/build/ipad/selftest-pkg" >"$LOG" 2>&1; then
  grep -E "error" "$LOG" | head -20 >&2; echo "self-test build failed (log: $LOG)" >&2; exit 1
fi
DEB="$(ls -t "$ROOT"/build/ipad/selftest-pkg/*.deb | head -1)"
T="$(mktemp -d)"; dpkg-deb -x "$DEB" "$T"; grep -q PTSELFTEST "$T/Applications/PadTube.app/PadTube"; rc=$?; rm -rf "$T"; [ $rc = 0 ] || { echo "self-test code missing" >&2; exit 1; }
echo "$DEB"
