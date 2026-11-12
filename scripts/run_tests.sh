#!/bin/bash
# Mac-side tests: unit (core, fixtures judged by ffprobe/ffmpeg), e2e (real YouTube, no account), release iOS build +
# static iOS 6 checks of the binary. Writes tests/artifacts/test_results.json. The iPad tests are tests/device/*.py.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export THEOS="${THEOS:-$HOME/theos}" PATH="/opt/homebrew/opt/make/libexec/gnubin:$PATH"
OUT=build/host/results.jsonl
mkdir -p build/host tests/artifacts
: > "$OUT"
make -s -j8 all || { echo "host build failed" >&2; exit 2; }
make -s -C ios clean package FINALPACKAGE=1 THEOS_PACKAGE_DIR="$ROOT/build/release-pkg" >/dev/null 2>&1 || { echo "iOS release build failed" >&2; exit 2; }
status=0
build/host/unit_tests unit "$OUT" || status=1
build/host/e2e_tests e2e "$OUT" || status=1
DEB="$(ls -t build/release-pkg/*.deb | head -1)"
python3 -I scripts/check_ios_binary.py "$DEB" "$HOME/theos/sdks/iPhoneOS9.3-armv7.sdk" "$OUT" || status=1
python3 -I -c "
import json; rows=[json.loads(l) for l in open('$OUT')]
json.dump(rows, open('tests/artifacts/test_results.json','w'), indent=1)
print(sum(r['status']=='passed' for r in rows), 'passed,', sum(r['status']!='passed' for r in rows), 'failed')"
exit $status
