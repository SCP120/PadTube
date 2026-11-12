# IDs: AC-PLAY-4 AC-PLAY-6 BR-PLAY-START
"""Regression: start time and bytes before the first frame do not grow with the video length (owner bug 2026-11-11).
Also: far seek downloads only the target segment, and full screen turns the interface to landscape and back."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot

R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:700], flush=True)

time.sleep(2)
CASES = [("dQw4w9WgXcQ", "3:33"), ("BDqvzFY72mg", "56:15"), ("Unzc731iCUY", "1:03:43")]
for q in [720, 0, 360]:
    a.cmd(f"setq {q}")
    for vid, length in CASES:
        a.cmd("root")
        a.cmd("open " + vid)
        st = a.j("waitplay 40")
        hl = a.j("hlslog")["log"].strip().splitlines()
        log(f"start_q{q}_{vid}", {"length": length, "start_ms": round(st["start_ms"]), "start_kb": round(st["start_bytes"] / 1024),
                                  "playing": st["playing"], "error": st["error"], "requests_before_play": hl})
        time.sleep(2)
# far seek on the long video: time to play again, and bytes fetched for it
a.cmd("setq 720")
a.cmd("root")
a.cmd("open BDqvzFY72mg")
a.j("waitplay 40")
time.sleep(3)
b0 = a.j("player")["fetched_bytes"]
a.cmd("stallreset")
t0 = time.time()
a.cmd("seek 2500")
st = {}
while time.time() - t0 < 20:
    st = a.j("player")
    if st["playing"] and abs(st["t"] - 2500) < 10 and st["t"] > 2500:
        break
    time.sleep(0.2)
log("far_seek_2500", {"seek_s": round(time.time() - t0, 2), "kb_for_seek": round((st["fetched_bytes"] - b0) / 1024), "t": st["t"],
                      **a.j("stalls"), "log_tail": a.j("hlslog")["log"].strip().splitlines()[-6:]})
# full screen: landscape and back
s0 = a.j("state")
shot("full_0_before")
a.cmd("full")
time.sleep(2.5)
s1 = a.j("state")
shot("full_1_on")
a.cmd("full")
time.sleep(2.5)
s2 = a.j("state")
shot("full_2_off")
log("fullscreen", {"before": s0["orientation"], "on": s1["orientation"], "on_full": s1["full"], "after": s2["orientation"], "presented_on": s1["presented"]})
json.dump(R, open(os.path.join(ART, "start_long.json"), "w"), indent=1)
