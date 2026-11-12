#!/bin/bash
# Release .deb for the owner's iPad (no self-test code, no JS test files). Checked by scripts/check_ios_binary.py.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export THEOS="${THEOS:-$HOME/theos}" PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
mkdir -p "$ROOT/build/release-pkg"
rm -f "$ROOT"/build/release-pkg/*.deb
LOG="$ROOT/build/release-pkg/build.log"
if ! make -s -C "$ROOT/ios" clean package FINALPACKAGE=1 THEOS_PACKAGE_DIR="$ROOT/build/release-pkg" >"$LOG" 2>&1; then
  grep -E "error" "$LOG" | head -20 >&2; echo "release build failed (log: $LOG)" >&2; exit 1
fi
DEB="$(ls -t "$ROOT"/build/release-pkg/*.deb | head -1)"
python3 -I "$ROOT/scripts/check_ios_binary.py" "$DEB" "$THEOS/sdks/iPhoneOS9.3-armv7.sdk" /dev/null >/dev/null || { echo "binary checks failed" >&2; exit 1; }
echo "$DEB"
