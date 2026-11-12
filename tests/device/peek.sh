#!/bin/bash
# Ask the running self-test app one command (default: state) without install or relaunch. Run inside ipad-lock.
P="${PORT:-5130}"
iproxy 6197:$P >/dev/null 2>&1 & IP=$!
sleep 1.5
python3 -I -c "
import socket,sys
try:
    s = socket.create_connection(('127.0.0.1', 6197), timeout=5); s.sendall((sys.argv[1] + '\n').encode()); print(s.makefile().readline().strip())
except OSError as e: print('no app:', e)
" "${1:-state}"
kill $IP 2>/dev/null; wait $IP 2>/dev/null
