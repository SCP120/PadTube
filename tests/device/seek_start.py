# IDs: AC-PLAY-4 AC-PLAY-6 NFR-06
"""Start time at 720p on long videos (cold and warm connection) and the main-thread cost of a seek."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART

R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:600], flush=True)
time.sleep(2)
a.cmd("setq 720")
for vid in ["Unzc731iCUY", "BDqvzFY72mg", "NNnIGh9g6fA", "Unzc731iCUY"]:
    a.cmd("root"); a.cmd("open " + vid)
    st = a.j("waitplay 40")
    log("start_" + vid, {"start_ms": round(st["start_ms"]), "kb": round(st["start_bytes"] / 1024), "log": a.j("hlslog")["log"].strip().splitlines()[:5]})
    time.sleep(3)
for target in [600, 1800, 30]:
    a.cmd("stallreset")
    t0 = time.time()
    a.cmd(f"seek {target}")
    st = {}
    while time.time() - t0 < 20:
        st = a.j("player")
        if st["playing"] and target <= st["t"] < target + 10:
            break
        time.sleep(0.2)
    log(f"seek_{target}", {"seek_s": round(time.time() - t0, 2), **a.j("stalls"), "t": round(st["t"], 1)})
json.dump(R, open(os.path.join(ART, "seek_start.json"), "w"), indent=1)
