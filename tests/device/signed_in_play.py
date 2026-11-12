# IDs: D64 (signed-in player path), owner bug "not a bot" (D60); read-only for the account (no like, no subscribe)
"""Plays videos that YouTube bot-checks signed out, through the signed-in path (tv_samsung + token + the n/sig
solver in iOS 6's JavaScriptCore). Few YouTube calls on purpose (D60). Needs the owner's signed-in session."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot

R = {"pass": True}
a = App(timeout=120)


def log(k, v, ok=None):
    R[k] = {"ok": ok, **v} if isinstance(v, dict) else {"ok": ok, "v": v}
    if ok is False:
        R["pass"] = False
    print(("FAIL " if ok is False else "") + k, json.dumps(v)[:400], flush=True)


time.sleep(2)
st = a.j("state")
log("signed_in", {"signed_in": st["signed_in"]}, st["signed_in"])
s = a.j("solver wait")
log("solver", {k: s.get(k) for k in ("ok", "version", "sts", "wait_ms", "version_ms", "prep_ms", "load_ms", "error")}, s.get("ok"))
a.cmd("setq 720")
for name, vid in (("bot_checked_bbb", "aqz-KE-bpKQ"), ("bot_checked_short", "FQKeCgDowAk")):
    a.cmd("root")
    a.cmd("open " + vid)
    p = a.j("waitplay 40")
    time.sleep(4)
    q = a.j("player")
    log(name, {"video": vid, "playing": q.get("playing"), "start_ms": p.get("start_ms"), "t": q.get("t"), "signed_in_path": q.get("signed_in_path"),
               "error": q.get("error")}, bool(q.get("playing")) and q.get("t", 0) > 2 and bool(q.get("signed_in_path")))
png = shot("signed_in_play")
log("shot", {"png": os.path.basename(png or "")}, None)
a.cmd("root")
r = a.j("search lofi music")
a.j("openvideo")
p = a.j("waitplay 40")
time.sleep(3)
q = a.j("player")
log("search_result", {"rows": r.get("rows"), "playing": q.get("playing"), "start_ms": p.get("start_ms"), "signed_in_path": q.get("signed_in_path"), "error": q.get("error")},
    bool(q.get("playing")))
a.cmd("root")
o = a.j("shorts")
time.sleep(4)
ss = a.j("sstate")
log("shorts", {"open_to_frame_ms": o.get("open_to_frame_ms"), "video": ss.get("video"), "t": ss.get("t"), "error": [x.get("error") for x in ss.get("slots", [])]},
    ss.get("t", 0) > 1)
m = a.j("mem")
log("memory", m, m["mb"] <= 120 and m["peak_mb"] <= 180)
log("net", a.j("net"), None)
a.cmd("tab 0")
json.dump(R, open(os.path.join(ART, "signed_in_play.json"), "w"), indent=1)
print("RESULT", "PASS" if R["pass"] else "FAIL")
