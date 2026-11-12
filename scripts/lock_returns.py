"""List PadTube returns in an idevicesyslog capture: away time, lock (backlight off), time to playback."""
import re, sys
from datetime import datetime

TS = re.compile(r'^(\w{3} +\d+ \d\d:\d\d:\d\d) (\S+)\[(\d+)\] <\w+>: (.*)$')
def t(s): return datetime.strptime("2026 " + s, "%Y %b %d %H:%M:%S")

blk = []          # (time, state)
ev = []           # (time, pid, kind, text)
for line in open(sys.argv[1], errors="replace"):
    m = TS.match(line.rstrip("\n"))
    if not m: continue
    ts, proc, pid, msg = t(m[1]), m[2], m[3], m[4]
    if proc == "kernel" and "framebufferState ->" in msg:
        st = int(msg[-1]); 
        if not blk or blk[-1][1] != st: blk.append((ts, st))
    elif proc == "PadTube":
        if msg.startswith("PadTube: resign active"): ev.append((ts, pid, "resign", msg))
        elif msg.startswith("PadTube: foreground"): ev.append((ts, pid, "fg", msg))
        elif "Ending background task assertion" in msg: ev.append((ts, pid, "stall_end", msg))
        elif msg.startswith("PadTube: return") or "moves=" in msg: ev.append((ts, pid, "ret", msg))
        elif "togglePlay" in msg or "play tap" in msg: ev.append((ts, pid, "tap", msg))

def screen_off_between(a, b):
    state = 1
    for ts, st in blk:
        if ts <= a: state = st
    if state == 0: return True
    return any(a <= ts <= b and st == 0 for ts, st in blk)

print("fg_time   pid  away_s lock playing stall_end_s ret_line")
last_resign = {}
for i, (ts, pid, kind, msg) in enumerate(ev):
    if kind == "resign": last_resign[pid] = (ts, msg)
    if kind != "fg": continue
    r = last_resign.get(pid)
    away = (ts - r[0]).total_seconds() if r else -1
    lock = screen_off_between(r[0], ts) if r else False
    playing = re.search(r"playing=(\d)", r[1])[1] if r else "?"
    se = next(((e[0]-ts).total_seconds() for e in ev[i+1:] if e[1]==pid and e[2]=="stall_end"
               and (e[0]-ts).total_seconds() < 120), None)
    nxt = next((e for e in ev[i+1:] if e[1]==pid and e[2] in ("resign","fg")), None)
    ret = [e[3] for e in ev[i+1:] if e[1]==pid and e[2]=="ret" and (nxt is None or e[0] <= nxt[0])]
    print(f"{ts:%H:%M:%S} {pid:>4} {away:6.0f} {'LOCK' if lock else '-':4} {playing:>7} "
          f"{'' if se is None else f'{se:.0f}':>11} {ret[0] if ret else ''}")
