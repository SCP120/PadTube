# IDs: AC-WATCH-1 AC-PLAY-4 AC-PLAY-5 AC-CAPTIONS-1 AC-CAP-2 AC-CAP-3 AC-BG-1 AC-LIVE-1 AC-SEARCH-4 AC-SEARCH-5 AC-LIB-3 AC-VPAGE-4 AC-HIST-3
"""Phase 0 on the iPad: the A5 truths of PLAN §7 and the watch-core gates. Writes tests/artifacts/device/phase0.json."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot

R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:400], flush=True)

time.sleep(3)
log("home_state", a.j("state"))
shot("p0_home")
log("tls", a.j("tlsbench"))
log("parse", a.j("parsebench"))
# search: first call opens the connection, the next two reuse it
for i, q in enumerate(["lofi music", "rick astley", "numberphile"]):
    log(f"search_{i}", a.j("search " + q))
time.sleep(2)
shot("p0_search")
a.cmd("mempeakreset")
log("scroll_search", a.j("scroll 8 1500"))
log("mem_after_scroll", a.j("mem"))

def play(vid, quality=None, tag=""):
    a.cmd("root")
    a.cmd("open " + vid)
    if quality:
        time.sleep(0.2)
    r = a.j("waitplay 40")
    log(f"play_{vid}{tag}", r)
    return r

# 1) start time in Auto (360p first), three times on different videos
for vid in ["dQw4w9WgXcQ", "aircAruvnKk", "jNQXAC9IVRw"]:
    play(vid, tag="_auto")
    time.sleep(4)
shot("p0_watch_landscape_or_portrait")
# 2) fixed qualities: switch on the running video and time to playing again
for h in [360, 480, 720]:
    a.cmd(f"quality {h}")
    t0 = time.time()
    while time.time() - t0 < 30:
        st = a.j("player")
        if st["playing"] and st["quality"] == h:
            break
        time.sleep(0.3)
    log(f"quality_{h}", {"switch_s": round(time.time() - t0, 2), **a.j("player")})
    time.sleep(3)
a.cmd("quality 0")
# 3) play to the end: 19 s video in full, then the last 20 s of two longer ones
log("stall_before_end", a.j("stalls"))
for vid, seek in [("jNQXAC9IVRw", None), ("dQw4w9WgXcQ", 192), ("aircAruvnKk", 1060)]:
    play(vid, tag="_end")
    if seek:
        a.cmd(f"seek {seek}")
    t0 = time.time()
    end = {}
    while time.time() - t0 < 90:
        end = a.j("player")
        if end["ended"] or end["error"]:
            break
        time.sleep(1)
    log(f"ended_{vid}", {"waited_s": round(time.time() - t0, 1), **end})
# 4) seek time: from 0 to the middle of a long video
play("aircAruvnKk", tag="_seek")
a.cmd("stallreset")
t0 = time.time()
a.cmd("seek 600")
while time.time() - t0 < 20:
    st = a.j("player")
    if st["playing"] and abs(st["t"] - 600) < 8:
        break
    time.sleep(0.2)
log("seek_600", {"seek_s": round(time.time() - t0, 2), **a.j("stalls"), "t": st["t"]})
# 5) captions: manual track 1 (index 0), then auto-generated
a.cmd("cc 0")
time.sleep(6)
log("captions", a.j("player"))
shot("p0_captions")
a.cmd("full")
time.sleep(2)
shot("p0_fullscreen_captions")
a.cmd("full")
# 5b) live: the iOS player on YouTube's own HLS manifest (separate audio renditions)
a.cmd("cc -1")
for vid in ["GotlA1KKWoo", "ZTNT_DuaL3Q"]:
    r = play(vid, tag="_live")
    if r.get("playing"):
        break
time.sleep(5)
log("live_after_5s", a.j("player"))
shot("p0_live")
play("aircAruvnKk", tag="_bg")
# 6) background audio: home button, then check the clock keeps moving
t_before = a.j("player")["t"]
a.cmd("suspend")
time.sleep(12)
st = a.j("player")
log("background", {"t_before": t_before, "t_after_12s": st["t"], "playing": st["playing"], "advanced": st["t"] - t_before})
# 7) memory while playing, and the main-thread stall over a minute of playback
a.cmd("stallreset")
time.sleep(30)
log("play_mem_30s", {**a.j("mem"), **a.j("stalls")})
# 8) JS solver helper in its own process
log("js_preprocessed_one", a.j("jsbench run_one.js"))
log("js_full_player", a.j("jsbench run_player_es6.js"))
json.dump(R, open(os.path.join(ART, "phase0.json"), "w"), indent=1)
print("saved")
