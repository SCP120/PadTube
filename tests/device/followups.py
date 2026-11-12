# IDs: R2-RAM AC-SPEED-AV AC-PLAY-START-LONG AC-HOME-DEDUPE-DEVICE AC-LINK-YT AC-EMOJI-DEVICE
"""Open device checks (2026-11-12): speed with each engine, 64-min start again, Home duplicates over pages on the
signed-in Home, a YouTube link opens in PadTube, a title with new emoji (screenshot to read by eye)."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot

R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:500], flush=True)
time.sleep(2)
a.j("orient 1"); a.cmd("setq 720")
# 1) speed: MediaPlayer vs AVPlayer, video advance in 6 s at rate 1.5
for eng in ["mp", "av"]:
    a.cmd(f"engine {eng}"); a.cmd("root"); a.cmd("open BDqvzFY72mg"); a.j("waitplay 40"); time.sleep(3)
    a.cmd("rate 1.5"); time.sleep(2)
    t0 = a.j("player")["t"]; time.sleep(6); t1 = a.j("player")["t"]
    log(f"speed_{eng}", {"advance_in_6s": round(t1 - t0, 2), "want": 9.0})
    a.cmd("rate 1")
a.cmd("engine mp")
# 2) 64-min video start (3 runs)
for i in range(3):
    a.cmd("root"); time.sleep(2); a.cmd("open Unzc731iCUY"); st = a.j("waitplay 40")
    log(f"start_long_{i}", {"start_ms": round(st["start_ms"]), "start_kb": round(st["start_bytes"] / 1024)})
# 3) signed-in Home: duplicates by id over 3 pages
a.cmd("root"); a.cmd("tab 0"); time.sleep(5)
for _ in range(3):
    a.j("scroll 4 3000"); time.sleep(3)
items = a.j("items")["items"]
ids = [i[0] for i in items]
dups = sorted({x for x in ids if ids.count(x) > 1})
log("home_dupes", {"items": len(ids), "duplicate_ids": dups})
# 4) a YouTube link opens in PadTube
a.cmd("root"); time.sleep(1); a.cmd("link https://youtu.be/dQw4w9WgXcQ"); time.sleep(4)
st = a.j("state"); log("link_youtube", {"top": st.get("top"), "presented": st.get("presented")}); a.cmd("root")
# R2) RAM before and after one web link (PadWeb browser)
a.cmd("root"); time.sleep(2); m0 = a.j("mem")
a.cmd("link https://example.com/"); time.sleep(5); m1 = a.j("mem"); a.cmd("dismiss"); time.sleep(3); m2 = a.j("mem")
log("ram_web_link", {"before": m0, "open": m1, "after_close": m2})
# 5) emoji titles
a.j("search 🫠 melting face emoji"); time.sleep(3); shot("emoji_search")
json.dump(R, open(os.path.join(ART, "followups.json"), "w"), indent=1)
