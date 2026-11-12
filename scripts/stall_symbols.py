#!/usr/bin/env python3
"""Map PadTube frames in PTSTALL lines ("TBStr+N", "TBLog+N": nearest exported name) to function names with nm on the
unstripped armv7 binary, then count the stacks by their first PadTube frame and their top system frame.
usage: stall_symbols.py <device syslog> [binary]  (frames "NAME+N" with NAME exported by PadTube)"""
import bisect, re, subprocess, sys, collections

log = sys.argv[1]
binary = sys.argv[2] if len(sys.argv) > 2 else "ios/.theos/obj/armv7/PadTube.app/PadTube"
syms = []
for line in subprocess.run(["nm", "-n", binary], capture_output=True, text=True).stdout.splitlines():
    parts = line.split(maxsplit=2)   # ObjC names have spaces: "-[TBTile setItem:]"
    if len(parts) == 3 and parts[1] in "tT":
        syms.append((int(parts[0], 16), parts[2]))
# ObjC methods: not in the symbol table (stripped), but in the class metadata (otool -oV: class name, then name/imp pairs)
cls, sel = "?", None
for line in subprocess.run(["otool", "-oV", binary], capture_output=True, text=True).stdout.splitlines():
    m = re.match(r"^( +)name +0x[0-9a-f]+ (.+)$", line)
    if m:
        if len(m.group(1)) <= 8: cls = m.group(2)
        else: sel = m.group(2)
        continue
    m = re.match(r"^ +imp +0x([0-9a-f]+)$", line)
    if m and sel:
        syms.append((int(m.group(1), 16) & ~1, f"[{cls} {sel}]")); sel = None
syms.sort()
addrs = [a for a, _ in syms]
exported = {n[1:]: a for a, n in syms if n.startswith("_")}   # iOS names a frame after the nearest exported symbol

def name(frame):
    sym, _, off = frame.rpartition("+")
    if sym not in exported or not off.isdigit():
        return frame
    at = exported[sym] + int(off)
    i = bisect.bisect_right(addrs, at) - 1
    return f"{syms[i][1]}+{at - syms[i][0]}" if i >= 0 else frame

by_ours, rows = collections.Counter(), []
for line in open(log, errors="replace"):
    m = re.search(r"PTSTALL (\d+) ms:(.*)", line)
    if not m:
        continue
    frames = [f.strip() for f in m.group(2).split("|") if f.strip()]
    frames = [name(f) for f in frames]
    ours = next((f for f in frames if f.startswith(("[", "_tb", "_TB"))), "(no PadTube frame)")
    by_ours[ours.split("+")[0]] += 1
    rows.append((int(m.group(1)), frames[:8]))
for k, v in by_ours.most_common():
    print(f"{v:4d}  {k}")
print()
for ms, fr in sorted(rows, reverse=True)[:12]:
    print(ms, " | ".join(fr))
