# IDs: AC-PLAY-LIVE AC-THEME-1
"""Live playback on the iPad (EF-PLAY-4: local merge of video-only TS + AAC) in Dark and Light, both orientations:
start time, playing, screenshots of the watch page and its Comments tab to read by eye."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot, picture_stats, is_picture

R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:400], flush=True)
time.sleep(2)
LIVE = 8   # guide row "Live"
for mode, dark in [("dark", 1), ("light", 0)]:
    a.j(f"theme {dark}"); time.sleep(2)
    for o, on in [(1, "port"), (3, "land")]:
        a.j(f"orient {o}"); time.sleep(1.5)
        a.cmd(f"tab {LIVE}"); time.sleep(4)
        a.cmd("openlist 0"); p = a.j("waitplay 40"); time.sleep(5)
        p2 = a.j("player"); st = a.j("state")
        png = shot(f"live_{mode}_{on}_watch")
        import re
        m = re.findall(r"[-\d.]+", st.get("player_rect", ""))
        pic = picture_stats(png, tuple(float(x) for x in m)) if len(m) == 4 else {}
        log(f"live_{mode}_{on}", {"start_ms": round(p.get("start_ms", -1)), "playing": p2.get("playing"), "t": round(p2.get("t", 0), 1),
                                  "error": p2.get("error"), "video": p2.get("video"), "picture": is_picture(pic) if pic else None})
        a.cmd("wtab Comments"); time.sleep(3); shot(f"live_{mode}_{on}_comments"); a.cmd("wtab About")
        a.cmd("root"); time.sleep(1)
a.j("theme 0"); a.j("orient 1")
json.dump(R, open(os.path.join(ART, "live_check.json"), "w"), indent=1)
