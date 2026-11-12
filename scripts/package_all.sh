#!/bin/bash
# Release files in dist/ (docs/release.md §3, D48). Public build: PUBLIC=1 (no PadWeb, public icon).
#   PadTube-<v>-iOS6-jailbreak-rootful.deb    armv7 + arm64, /Applications
#   PadTube-<v>-iOS15-jailbreak-rootless.deb  arm64, /var/jb/Applications
#   PadTube-<v>-iOS7-sideload.ipa             armv7 + arm64, signed again by the user's tool (or TrollStore)
#   SHA256SUMS.txt
# Only the armv7 code has run on a device (iPad mini 1, iOS 6.1.3). The arm64 code is built and checked here only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export THEOS="${THEOS:-$HOME/theos}" PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
SDK="$THEOS/sdks/iPhoneOS16.5.sdk"; MINOS=7.0   # D48: every 64-bit iPad shipped with iOS 7 or later
P="$ROOT/third_party/prefix/ios-arm64"
O="$ROOT/build/arm64"; D="$ROOT/dist"; W="$ROOT/build/package"
V="$(awk '/^Version:/{print $2}' ios/control)"
scripts/build_deps.sh >/dev/null

# 1. armv7: the theos build, then its own checks (ARM only, iOS 6 symbols and libraries, no test code)
LOG="$ROOT/build/package-armv7.log"
make -s -C ios clean package FINALPACKAGE=1 PUBLIC=1 THEOS_PACKAGE_DIR="$ROOT/build/release-pkg" >"$LOG" 2>&1 \
  || { grep -E "error" "$LOG" | head -20 >&2; echo "armv7 build failed (log: $LOG)" >&2; exit 1; }
A7="$(ls -t build/release-pkg/*.deb | head -1)"
python3 -I scripts/check_ios_binary.py "$A7" "$THEOS/sdks/iPhoneOS9.3-armv7.sdk" /dev/null >/dev/null \
  || { echo "armv7 binary checks failed: python3 scripts/check_ios_binary.py $A7 ..." >&2; exit 1; }

# 2. arm64: the same sources, iPhoneOS16.5 SDK. ARC on the compile line only: with -fobjc-arc on the link line
# clang asks for libarclite, which Command Line Tools do not have.
find "$W" "$O" "$D" -mindepth 1 -delete 2>/dev/null || true
mkdir -p "$W/app" "$O" "$D"
FL="-arch arm64 -isysroot $SDK -miphoneos-version-min=$MINOS -ffile-prefix-map=$ROOT=."
for f in core/*.c third_party/vendor/yyjson.c third_party/vendor/qrcodegen.c; do
  xcrun clang -std=c99 -Os -Wall -Wextra -Werror -Wno-unused-parameter $FL -Icore -Ithird_party/vendor -I"$P/include" -c "$f" -o "$O/c_$(basename "$f" .c).o"
done
for f in ios/src/*.m; do
  xcrun clang -fobjc-arc -Os -Wall -Wno-unused-parameter -Wno-deprecated-declarations -Werror=unguarded-availability -DTB_NO_PADWEB \
    $FL -Icore -Ithird_party/vendor -Iios/src -c "$f" -o "$O/m_$(basename "$f" .m).o"
done
xcrun clang $FL -dead_strip "$O"/*.o "$P/lib/libssl.a" "$P/lib/libcrypto.a" -lz -lsqlite3 \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -framework MediaPlayer \
  -framework AVFoundation -framework CoreMedia -framework ImageIO -framework CoreFoundation -o "$O/PadTube.arm64"
strip -x "$O/PadTube.arm64"

# 3. one binary with both
dpkg-deb -x "$A7" "$W/app"
APP="$W/app/Applications/PadTube.app"
cp "$APP/PadTube" "$O/PadTube.armv7"
lipo -create "$O/PadTube.armv7" "$O/PadTube.arm64" -output "$APP/PadTube"
ldid -S "$APP/PadTube"
[ "$(lipo -archs "$APP/PadTube")" = "armv7 arm64" ] || { echo "fat binary: $(lipo -archs "$APP/PadTube")" >&2; exit 1; }
! grep -q PTSELFTEST "$APP/PadTube" || { echo "self-test code in the release" >&2; exit 1; }

mkdir -p "$W/app/DEBIAN"
cp ios/control "$W/app/DEBIAN/control"
dpkg-deb --root-owner-group -Zgzip -b "$W/app" "$D/PadTube-${V}-iOS6-jailbreak-rootful.deb" >/dev/null

# 4. rootless: arm64 only, under /var/jb
R="$W/rootless"
mkdir -p "$R/var/jb/Applications" "$R/DEBIAN"
ditto "$APP" "$R/var/jb/Applications/PadTube.app"
lipo -thin arm64 "$APP/PadTube" -output "$R/var/jb/Applications/PadTube.app/PadTube"
ldid -S "$R/var/jb/Applications/PadTube.app/PadTube"
sed -e 's/^Architecture:.*/Architecture: iphoneos-arm64/' -e 's/^Depends:.*/Depends: firmware (>= 15.0)/' ios/control > "$R/DEBIAN/control"
dpkg-deb --root-owner-group -Zgzip -b "$R" "$D/PadTube-${V}-iOS15-jailbreak-rootless.deb" >/dev/null

# 5. sideload .ipa
mkdir -p "$W/ipa/Payload"
ditto "$APP" "$W/ipa/Payload/PadTube.app"
(cd "$W/ipa" && zip -qryX "$D/PadTube-${V}-iOS7-sideload.ipa" Payload)

(cd "$D" && shasum -a 256 PadTube-* > SHA256SUMS.txt)
for s in armv7 arm64; do
  printf '%s: ' "$s"; otool -arch "$s" -l "$APP/PadTube" | grep -A3 -E "LC_VERSION_MIN_IPHONEOS|LC_BUILD_VERSION" | grep -E "version|minos" | head -1 | xargs
done
ls -l "$D" | awk 'NR>1{print $5, $9}'
