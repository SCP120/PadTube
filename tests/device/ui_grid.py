# IDs: AC-LIB-3 NFR-01 BR-TEXT-IOS6
"""Owner photo report 2026-11-12: compact grid (3 tiles portrait, 4 landscape) on Home, Search, Channel; scroll fps with
the grid; header title stops before the search field. Screenshots: tests/artifacts/device/grid_*.png (checked by eye)."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot

R = {"pass": True}
a = App()
def log(k, v, ok=None):
    R[k] = v
    if ok is False: R["pass"] = False
    print(("FAIL " if ok is False else "") + k, json.dumps(v)[:400], flush=True)
time.sleep(2)
for o, name in [(1, "port"), (3, "land")]:
    a.j(f"orient {o}"); time.sleep(1.5)
    a.cmd("tab 0"); time.sleep(4); shot(f"grid_{name}_home")
    a.cmd("mempeakreset")
    r = a.j("scroll 6 1500"); log(f"scroll_home_{name}", r, r["fps"] >= 55)
    log(f"search_{name}", a.j("search lofi")); time.sleep(2); shot(f"grid_{name}_search")
    r = a.j("scroll 6 1500"); log(f"scroll_search_{name}", r, r["fps"] >= 55)
    a.j("search veritasium"); time.sleep(1); a.cmd("openlist 0"); time.sleep(4); shot(f"grid_{name}_channel")
    a.cmd("openvideo"); a.j("waitplay 30"); time.sleep(2)
    h = a.j("header"); log(f"header_{name}", h, h["ok"]); shot(f"grid_{name}_watch")
    a.cmd("root")
log("mem", a.j("mem"))
json.dump(R, open(os.path.join(ART, "ui_grid.json"), "w"), indent=1)
print("RESULT", "PASS" if R["pass"] else "FAIL")
