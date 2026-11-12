#!/bin/bash
# Install a PadTube .deb on the USB-connected iPad through the normal install service (no root). Install on top:
# never uninstall + install in a loop (it crashed SpringBoard once). Run it inside ipad-lock.
# usage: [PT_BUNDLE=<id>] ipad_deploy.sh [deb]   Writes the app container path to build/ipad/container.txt.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
I="$ROOT/build/ipad/ipa"
DEB="${1:-$(ls -t "$ROOT"/ios/packages/*.deb | head -1)}"
mkdir -p "$I"
find "$I" -mindepth 1 -delete
dpkg-deb -x "$DEB" "$I/x"
mkdir -p "$I/Payload"
ditto "$I/x/Applications/PadTube.app" "$I/Payload/PadTube.app"
rm -f "$ROOT/build/ipad/PadTube.ipa"
(cd "$I" && zip -qry ../PadTube.ipa Payload)
ideviceinstaller install "$ROOT/build/ipad/PadTube.ipa" 2>/dev/null | tail -1
# the container path from the install service (the install log is not reliable)
C="$(ideviceinstaller list --xml -b "${PT_BUNDLE:-dev.padtube.app}" -a Container 2>/dev/null | grep -A1 '<key>Container</key>' | grep -oE '/private/var/mobile/Applications/[0-9A-F-]{36}' || true)"
[ -n "$C" ] || { echo "app not found after install" >&2; exit 2; }
echo "$C" > "$ROOT/build/ipad/container.txt"
echo "container: $C"
