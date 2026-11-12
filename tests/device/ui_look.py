# IDs: AC-LOGIN-7 AC-LIB-3 NFR-01
"""The 2012 YouTube-for-iPad look (docs/design/old-youtube-ui.md), screen by screen, in both orientations, with
scroll fps on the new cards and the sign-in screen (code + QR, no web page). Screenshots: tests/artifacts/device/look_*.png."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot

R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:400], flush=True)
time.sleep(3)
for o, name in [(3, "land"), (1, "port")]:
    log(f"orient_{name}", a.j(f"orient {o}")); time.sleep(1.5)
    a.cmd("tab 0"); time.sleep(3); shot(f"look_{name}_home")
    if name == "port":
        a.cmd("guide"); time.sleep(1); shot("look_port_guide"); a.cmd("guide"); time.sleep(0.5)
    log(f"search_{name}", a.j("search numberphile")); time.sleep(2); shot(f"look_{name}_search")
    a.cmd("mempeakreset")
    log(f"scroll_{name}", a.j("scroll 6 1500"))
    a.cmd("openvideo"); p = a.j("waitplay 30"); log(f"play_{name}", {"start_ms": p["start_ms"], "playing": p["playing"]})
    time.sleep(4); shot(f"look_{name}_watch")
    a.cmd("comments"); time.sleep(3); shot(f"look_{name}_comments")
    a.cmd("root")
log("mem", a.j("mem"))
a.cmd("orient 1")
if "--signin" in sys.argv:
    r = a.j("signin"); log("signin", r)
    time.sleep(1.5); shot("look_port_signin")
json.dump(R, open(os.path.join(ART, "ui_look.json"), "w"), indent=1)
