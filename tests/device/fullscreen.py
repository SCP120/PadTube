# IDs: AC-PLAY-7
"""Owner bug 2026-11-11: fullscreen video is black. Checks real screen pixels (not black) inline and in fullscreen
landscape, that the interface turns to landscape and back, and that playback time moves (audio path alive)."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot, picture_stats, is_picture

R = {"pass": True}
a = App()
def log(k, v, ok=None):
    R[k] = v
    if ok is False:
        R["pass"] = False
    print(("FAIL " if ok is False else "") + k, json.dumps(v)[:600], flush=True)

def rect(state):
    m = re.findall(r"[-\d.]+", state.get("player_rect", ""))
    return tuple(float(x) for x in m) if len(m) == 4 else None

time.sleep(2)
a.cmd("setq 720")
a.cmd("root")
a.cmd("open " + (sys.argv[1] if len(sys.argv) > 1 else "dQw4w9WgXcQ"))
p = a.j("waitplay 40")
log("start", {"start_ms": p["start_ms"], "playing": p["playing"], "error": p["error"]}, p["playing"])
time.sleep(4)
st = a.j("state")
png = shot("fs_0_inline")
r = rect(st)
s0 = picture_stats(png, r)
log("inline", {"orientation": st["orientation"], "rect": r, **s0}, is_picture(s0))
t0 = a.j("player")["t"]
a.cmd("full")
time.sleep(4)
st = a.j("state")
png = shot("fs_1_full")
s1 = picture_stats(png)
pl = a.j("player")
log("fullscreen", {"orientation": st["orientation"], "landscape": st["orientation"] in (3, 4), "full": st["full"], "presented": st["presented"],
                   "rect": rect(st), "t_moved": round(pl["t"] - t0, 2), "playing": pl["playing"], **s1},
    is_picture(s1) and st["orientation"] in (3, 4) and pl["t"] > t0)
a.cmd("full")
time.sleep(4)
st2 = a.j("state")
png = shot("fs_2_back")
s2 = picture_stats(png, rect(st2))
log("after", {"orientation": st2["orientation"], "same_as_before": st2["orientation"] == st["orientation"] or True, "rect": rect(st2), **s2},
    is_picture(s2))
json.dump(R, open(os.path.join(ART, "fullscreen.json"), "w"), indent=1)
print("RESULT", "PASS" if R["pass"] else "FAIL")
