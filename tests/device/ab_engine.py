# IDs: AC-PLAY-4 AC-PLAY-6 NFR-06
"""MPMoviePlayerController vs AVPlayer on the same videos: start time, seek time, main-thread stall, full screen pixels."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot, picture_stats, is_picture

R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:300], flush=True)
time.sleep(2)
a.cmd("setq 720")
for eng in ["av", "mp"]:
    a.cmd("engine " + eng)
    for vid in ["Unzc731iCUY", "dQw4w9WgXcQ", "BDqvzFY72mg"]:
        a.cmd("root"); a.cmd("stallreset"); a.cmd("open " + vid)
        st = a.j("waitplay 40")
        log(f"{eng}_start_{vid}", {"engine": st.get("engine"), "start_ms": round(st["start_ms"]), "playing": st["playing"], "error": st["error"], **a.j("stalls")})
        time.sleep(3)
    for target in [600, 1800, 30]:
        a.cmd("stallreset"); t0 = time.time(); a.cmd(f"seek {target}")
        st = {}
        while time.time() - t0 < 20:
            st = a.j("player")
            if st["playing"] and target <= st["t"] < target + 10:
                break
            time.sleep(0.2)
        log(f"{eng}_seek_{target}", {"seek_s": round(time.time() - t0, 2), **a.j("stalls"), "t": round(st["t"], 1)})
    a.cmd("stallreset"); time.sleep(10)
    log(f"{eng}_playing_10s", a.j("stalls"))
    a.cmd("full"); time.sleep(3)
    s = picture_stats(shot(f"ab_{eng}_full"))
    log(f"{eng}_full", {**s, "picture": is_picture(s), "orientation": a.j("state")["orientation"]})
    a.cmd("full"); time.sleep(2)
json.dump(R, open(os.path.join(ART, "ab_engine.json"), "w"), indent=1)
