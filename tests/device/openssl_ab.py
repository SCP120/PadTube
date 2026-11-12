# IDs: D65 (OpenSSL armv7 with assembly vs without): TLS handshake, playback start, CPU per MB, Shorts CPU per minute
"""One run of the OpenSSL A/B on the iPad. usage: openssl_ab.py <label>. Few YouTube calls on purpose (D60)."""
import json, os, statistics, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART

LABEL = sys.argv[1] if len(sys.argv) > 1 else "run"
a = App(timeout=120)
R = {"label": LABEL}
time.sleep(2)
t = a.j("tlsbench")
R["handshake_ms"] = {h: round(statistics.median(x["handshake_ms"] for x in v), 1) for h, v in t.items()}
a.cmd("setq 720")
a.j("solver wait")
plays = []
for vid in ("aqz-KE-bpKQ", "dQw4w9WgXcQ"):
    a.cmd("root")
    n0 = a.j("net")
    a.cmd("open " + vid)
    p = a.j("waitplay 40")
    time.sleep(25)
    n1 = a.j("net")
    q = a.j("player")
    mb = (n1["bytes_in"] - n0["bytes_in"]) / 1048576
    plays.append({"video": vid, "start_ms": round(p.get("start_ms", -1)), "playing": q.get("playing"), "signed_in_path": q.get("signed_in_path"),
                  "mb": round(mb, 1), "cpu_s": round(n1["cpu_s"] - n0["cpu_s"], 1), "cpu_s_per_mb": round((n1["cpu_s"] - n0["cpu_s"]) / mb, 2) if mb > 0 else None})
R["plays"] = plays
a.cmd("root")
a.j("shorts")
time.sleep(3)
n0, t0 = a.j("net"), time.time()
fr = []
for i in range(5):
    fr.append(round(a.j("sswipe 1")["settle_to_frame_ms"]))
    time.sleep(3)
n1 = a.j("net")
mins = (time.time() - t0) / 60
R["shorts"] = {"frame_ms": fr, "cpu_s_per_min": round((n1["cpu_s"] - n0["cpu_s"]) / mins, 1), "mb_per_min": round((n1["bytes_in"] - n0["bytes_in"]) / 1048576 / mins, 1)}
R["mem"] = a.j("mem")
a.cmd("tab 0")
print(json.dumps(R))
json.dump(R, open(os.path.join(ART, f"openssl_ab_{LABEL}.json"), "w"), indent=1)
