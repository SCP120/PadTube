# IDs: AC-LOGIN-3 AC-LIB-1 AC-VPAGE-3 AC-HIST-2 BR-LOGIN-TV
"""Signed in (TV client + OAuth token): every library screen loads from the account; like and Watch Later work
and are undone in the same run on one obscure video; speed with each engine. Screenshots: look_acct_*.png."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot

R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:500], flush=True)
time.sleep(2)
st = a.j("state"); log("state", {"signed_in": st["signed_in"]})
if not st["signed_in"]:
    sys.exit("not signed in")
a.cmd("orient 3"); time.sleep(1)
names = ["Home Feed", "Subscriptions", "Search", "History", "Watch Later", "Liked Videos", "Playlists", "YouTube History"]
for i in [0, 1, 4, 5, 6, 7]:
    a.cmd(f"tab {i}"); time.sleep(5)
    s = a.j("state"); e = a.j("empty")
    log("lib_" + names[i].replace(" ", "_"), {"rows": s["rows"], "empty": e.get("text", "")})
    shot("look_acct_" + names[i].replace(" ", "_"))
# like / Watch Later on an obscure video, then undo
a.j("search padtube test 3 views"); vid = None
v = a.j("openvideo"); vid = v.get("opened"); a.j("waitplay 30"); time.sleep(2)
log("video", {"id": vid})
log("like", a.j(f"acct like {vid} 1")); log("unlike", a.j(f"acct like {vid} 0"))
log("wl_add", a.j(f"acct wladd {vid}")); time.sleep(3)
log("wl_has", a.j(f"acct wlhas {vid}")); log("wl_rm", a.j(f"acct wlrm {vid}"))
time.sleep(3); log("wl_has_after", a.j(f"acct wlhas {vid}"))
for eng in ["av", "mp"]:
    a.cmd("engine " + eng); a.cmd("root"); a.cmd("open aircAruvnKk"); a.j("waitplay 30"); time.sleep(2)
    a.cmd("rate 1.5"); time.sleep(2); t0 = a.j("player")["t"]; time.sleep(4); t1 = a.j("player")["t"]
    log(f"speed_{eng}", {"advance_in_4s": round(t1 - t0, 2)}); a.cmd("rate 1")
a.cmd("engine mp")
json.dump(R, open(os.path.join(ART, "signed_in.json"), "w"), indent=1)
