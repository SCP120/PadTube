# IDs: AC-CHANNEL-2 AC-CHAPTERS-1 AC-CAP-2 BR-CAP-DRAW AC-PLAY-6
"""Tier 2 screens on the iPad in the 2012 look: channel page (3 tabs), chapters, captions inline and in full screen,
speed, and the far-seek timeline with the HLS request log (seek outlier)."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot, picture_stats, is_picture

R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:500], flush=True)
time.sleep(2)
a.cmd("orient 3"); time.sleep(1)
a.j("search 3blue1brown"); time.sleep(1)
r = a.cmd("openlist 0"); time.sleep(4)          # row 0 is the channel
log("channel", a.j("state")); shot("look_channel")
a.cmd("openvideo"); p = a.j("waitplay 30")
log("play_from_channel", {"start_ms": p["start_ms"], "playing": p["playing"], "chapters": p["chapters"]})
a.cmd("cc 0"); time.sleep(8)
p = a.j("player"); log("caption_inline", {"caption": p["caption"]}); shot("look_caption")
a.cmd("full"); time.sleep(4); p = a.j("player"); s = picture_stats(shot("look_caption_full"))
log("caption_full", {"caption": p["caption"], **s, "picture": is_picture(s)}); a.cmd("full"); time.sleep(2)
a.cmd("rate 1.5"); time.sleep(4); t0 = a.j("player")["t"]; time.sleep(4); t1 = a.j("player")["t"]
log("speed_1_5", {"advance_in_4s": round(t1 - t0, 2)}); a.cmd("rate 1")
for target in [600, 30, 900]:
    a.cmd("stallreset"); t0 = time.time(); a.cmd(f"seek {target}")
    st = {}
    while time.time() - t0 < 20:
        st = a.j("player")
        if st["playing"] and target <= st["t"] < target + 10:
            break
        time.sleep(0.2)
    log(f"seek_{target}", {"seek_s": round(time.time() - t0, 2), **a.j("stalls"), "log_tail": a.j("hlslog")["log"].strip().splitlines()[-8:]})
json.dump(R, open(os.path.join(ART, "tier2.json"), "w"), indent=1)
