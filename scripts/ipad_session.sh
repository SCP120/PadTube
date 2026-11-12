#!/bin/bash
# One device session for the self-test build, run inside ipad-lock:
#   install (on top) -> start the app -> iproxy 6124->5124 -> run the given command -> stop the relays.
# usage: ipad-lock scripts/ipad_session.sh [--no-install] <command...>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
INSTALL=1
[ "${1:-}" = "--no-install" ] && { INSTALL=0; shift; }
image_ok() { idevicescreenshot build/ipad/probe.tiff >/dev/null 2>&1; }
if ! image_ok; then
  ideviceimagemounter mount build/ipad/ddi/dmg build/ipad/ddi/sig >/dev/null 2>&1
  build/ipad/ptmount build/ipad/ddi/sig >/dev/null
fi
image_ok || { echo "developer image not mounted" >&2; exit 2; }
# old self-test instances (kept alive by background audio) hold a control port: ask each to quit
for P in 5130 5131 5132 5133 5134; do
  iproxy 6199:$P >/dev/null 2>&1 &
  QP=$!
  sleep 1.5
  python3 -I -c "
import socket
try:
    s = socket.create_connection(('127.0.0.1', 6199), timeout=2); f = s.makefile()
    s.sendall(b'whoami\n')
    if f.readline().strip() == 'padtube':   # never quit another app (PadBook shares the iPad)
        s.sendall(b'quit\n'); print('old PadTube instance on $P:', f.readline().strip())
except OSError: pass
" 2>/dev/null
  kill $QP 2>/dev/null; wait $QP 2>/dev/null
done
if [ $INSTALL = 1 ]; then
  scripts/ipad_deploy.sh "${PT_DEB:-$(ls -t build/ipad/selftest-pkg/*.deb | head -1)}" || exit 2
fi
CON="$(cat build/ipad/container.txt)"
idevicesyslog > build/ipad/device_syslog.txt 2>&1 &
SYS=$!
sleep 1
build/ipad/ptlaunch "$CON/PadTube.app/PadTube" "$CON" >/dev/null
PORT=""
for i in $(seq 1 30); do
  PORT="$(grep -aoE 'PadTube\[[0-9]+\].*PTSELFTEST port [0-9]+' build/ipad/device_syslog.txt | tail -1 | grep -oE '[0-9]+$')"
  [ -n "$PORT" ] && break
  sleep 1
done
if [ -z "$PORT" ]; then # the app was already running: find the port by asking each one
  for P in 5130 5131 5132 5133 5134; do
    iproxy 6198:$P >/dev/null 2>&1 & QP=$!; sleep 1.5
    R="$(python3 -I -c "
import socket
try:
    s = socket.create_connection(('127.0.0.1', 6198), timeout=2); s.sendall(b'whoami\n'); print(s.recv(16).decode().strip())
except OSError: pass" 2>/dev/null)"
    kill $QP 2>/dev/null; wait $QP 2>/dev/null
    [ "$R" = "padtube" ] && { PORT=$P; break; }
  done
fi
[ -n "$PORT" ] || { echo "no PTSELFTEST port" >&2; kill $SYS; exit 2; }
echo "control port $PORT"
iproxy 6124:$PORT >/dev/null 2>&1 &
PROXY=$!
sleep 2
"$@"
status=$?
kill "$SYS" "$PROXY" 2>/dev/null
echo "--- PadTube log lines:"; grep -aE "PadTube|PTSELFTEST" build/ipad/device_syslog.txt | grep -v "kernel" | tail -15
echo "--- crashes:"; grep -aE "PadTube.*(crashed|exited abnormally)|Terminating app due to" build/ipad/device_syslog.txt | tail -5
exit $status
