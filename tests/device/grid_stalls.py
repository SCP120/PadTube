# IDs: R1-GRID-FRAMES
"""Regression R1 (2026-11-12): single slow frames of 25-101 ms in the compact grid. Stall stacks for every main
pass over 30 ms during grid scrolls (both orientations) and one watch page open. Then on the Mac:
scripts/stall_symbols.py build/ipad/device_syslog.txt"""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART

R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:300], flush=True)
time.sleep(2)
a.cmd("stallms 30")
for o, on in [(1, "port"), (3, "land")]:
    a.j(f"orient {o}"); time.sleep(1.5)
    a.cmd("tab 0"); time.sleep(4)
    log(f"scroll_home_{on}", a.j("scroll 6 1500"))
    a.j("search lofi"); time.sleep(2)
    log(f"scroll_search_{on}", a.j("scroll 6 1500"))
a.cmd("stallreset"); a.cmd("open aircAruvnKk"); a.j("waitplay 30"); time.sleep(3)
log("watch_open", a.j("stalls"))
a.cmd("stallms 100"); a.cmd("root"); a.j("orient 1")
json.dump(R, open(os.path.join(ART, "grid_stalls.json"), "w"), indent=1)
