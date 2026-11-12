"""Where do the Shorts bytes go (D65 data check)? Same cadence as openssl_ab.py, but on a fixed list of Shorts.
usage: shorts_data.py <label> <ids file (one Short id per line; kept out of the repo)> [ahead s: the forward limit, D67;
       < 0 no limit; left out: the built-in value]. The setting is reset to the built-in value at the end.
Writes tests/artifacts/device/shorts_data_<label>.json; the per-Short lines are in build/ipad/device_syslog.txt
(PadTube: Short <id> format / let go, tb_stream: fetch, PadTube: net mark)."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART

LABEL, IDS = sys.argv[1], [x.strip() for x in open(sys.argv[2]) if x.strip()]
AHEAD = sys.argv[3] if len(sys.argv) > 3 else None
a = App(timeout=120)
time.sleep(2)
a.cmd("sab 1 720 0 0 0 " + AHEAD if AHEAD else "sab 1 720")
a.j("solver wait")
R = {"label": LABEL, "ahead": AHEAD, "ids": IDS, "open": a.j("sfeed " + ",".join(IDS))}
time.sleep(3)
n0, t0 = a.j("net start"), time.time()
fr = []
for i in range(5):                      # the openssl_ab.py window
    fr.append(round(a.j("sswipe 1")["settle_to_frame_ms"]))
    time.sleep(3)
n1, t1 = a.j("net end"), time.time()
time.sleep(20)                          # no swipe: what the current and next Shorts still fetch
n2, t2 = a.j("net hold"), time.time()
after = round(a.j("sswipe 1")["settle_to_frame_ms"])   # the next Short waited 20 s behind the limit (D58 case)
time.sleep(3)
a.j("sfeed " + IDS[0])                  # unloads every slot: each Short logs its "let go" line
a.cmd("tab 0")
a.cmd("sab 1 720")                      # the owner's settings: built-in values
R.update({"frame_ms": fr, "window_s": round(t1 - t0, 1), "window_mb": round((n1["bytes_in"] - n0["bytes_in"]) / 1048576, 2),
          "mb_per_min": round((n1["bytes_in"] - n0["bytes_in"]) / 1048576 / ((t1 - t0) / 60), 1),
          "cpu_s_per_min": round((n1["cpu_s"] - n0["cpu_s"]) / ((t1 - t0) / 60), 1),
          "requests": n1["requests"] - n0["requests"], "hold_s": round(t2 - t1, 1),
          "hold_mb": round((n2["bytes_in"] - n1["bytes_in"]) / 1048576, 2), "after_hold_frame_ms": after})
print(json.dumps(R))
json.dump(R, open(os.path.join(ART, f"shorts_data_{LABEL}.json"), "w"), indent=1)
