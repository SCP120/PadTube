#!/bin/bash
# Print PadTube's return log from the iPad (Documents/padtube_returns.log): one line per return from the background
# or the lock screen. Run inside ipad-lock. afcclient waits for commands, so it gets "quit" and a time limit.
set -euo pipefail
OUT="${1:-/tmp/padtube_returns.log}"
printf 'get Documents/padtube_returns.log %s\nquit\n' "$OUT" | timeout 30 afcclient --documents dev.padtube.app >/dev/null 2>&1 || true
[ -s "$OUT" ] && cat "$OUT" || echo "no return log yet"
