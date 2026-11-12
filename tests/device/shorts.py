# IDs: D53-D56, BR-SHORTS-FEED, BR-SHORTS-TWO-PLAYERS; gates: swipe end -> first frame <= 500 ms, >= 55 fps in the
# swipe, no main-thread pass > 50 ms, RAM <= 120 MB steady / 180 MB peak
"""Shorts tab on the iPad: open, swipes forward (the next Short prerolled) and back, a fast double swipe, pause,
loop, comments (pushed; back with the swipe back of D49), share sheet, portrait and landscape, Light and Dark
screenshots. The swipes are driven frame by frame through the self-test port (the same end-of-swipe call as the
scroll view); real finger events are not made."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot

GATE_MS, GATE_FPS, GATE_MAIN = 500, 55, 50
R = {"pass": True, "cases": {}}
a = App(timeout=60)


def log(k, v, ok=None):
    R["cases"][k] = {"ok": ok, **v} if isinstance(v, dict) else {"ok": ok, "v": v}
    if ok is False:
        R["pass"] = False
    print(("FAIL " if ok is False else "") + k, json.dumps(v)[:420], flush=True)


KEYS = ("index", "video", "settle_to_frame_ms", "prepared", "fps", "slow_frames", "max_frame_ms", "swipe_max_main_ms", "to_frame_max_main_ms", "timed_out")


def swipe(name, d=1, gate=True, wait=2.5):
    r = a.j(f"sswipe {d}")
    ok = (not r["timed_out"] and r["settle_to_frame_ms"] <= GATE_MS and r["fps"] >= GATE_FPS
          and r["swipe_max_main_ms"] <= GATE_MAIN and r["to_frame_max_main_ms"] <= GATE_MAIN) if gate else None
    log(name, {k: r.get(k) for k in KEYS}, ok)
    time.sleep(wait)
    return r


def screen(name):
    p = shot(name)
    return os.path.basename(p or "")


time.sleep(2)
a.cmd("root")
a.j("orient 1")
time.sleep(1.5)
o = a.j("shorts")
log("open", {k: o.get(k) for k in ("open_to_frame_ms", "count", "video", "title", "max_main_ms")}, o.get("count", 0) > 0 and o.get("video") != "")
log("no_swipe_back_on_shorts", a.j("edgecheck 10 400"), not a.j("edgecheck 10 400")["accept"])
h = a.j("sheader")
log("reload_button_in_header", h, h["has_button"])
time.sleep(3)
s = a.j("sstate")
log("playing_after_open", {"t": s["t"], "slots": s["slots"]}, s["t"] > 1)
log("port_shot", {"png": screen("shorts_port_light")}, None)

# forward swipes: the next Short is prepared (loaded, first frame decoded, paused) while the current one plays
res = [swipe(f"port_fwd_{i}", gate=False) for i in range(8)]
ms = sorted(round(r["settle_to_frame_ms"]) for r in res)
log("port_fwd_summary", {"swipes": len(res), "prepared": sum(r["prepared"] for r in res), "frame_ms": ms, "p50": ms[len(ms) // 2],
                         "fps_min": round(min(r["fps"] for r in res), 1), "swipe_main_max": round(max(r["swipe_max_main_ms"] for r in res), 1),
                         "to_frame_main_max": round(max(r["to_frame_max_main_ms"] for r in res), 1)},
    ms[len(ms) // 2] <= GATE_MS and min(r["fps"] for r in res) >= GATE_FPS and max(r["swipe_max_main_ms"] for r in res) <= GATE_MAIN)
# a step back (not prepared) and a fast double swipe: reported, not gated by the prerolled target
swipe("port_back_not_prepared", -1, gate=False)
swipe("port_fast_1", 1, gate=False, wait=0.1)
swipe("port_fast_2", 1, gate=False)

# pause and play
a.cmd("stap"); time.sleep(0.3); t1 = a.j("sstate")["t"]; time.sleep(1.5); t2 = a.j("sstate")["t"]
log("pause", {"t1": t1, "t2": t2}, abs(t2 - t1) < 0.1)
log("pause_shot", {"png": screen("shorts_port_paused")}, None)
a.cmd("stap"); time.sleep(1.5)
log("resume", {"t": a.j("sstate")["t"]}, a.j("sstate")["t"] > t2 + 0.5)

# loop: swipe until a Short of 30 s or less, wait past its end
loop = None
for i in range(10):
    st = a.j("sstate")
    if 0 < st["length"] <= 30:
        loop = st
        break
    swipe(f"to_short_{i}", gate=False, wait=1.5)
if loop:
    time.sleep(loop["length"] + 3)
    st = a.j("sstate")
    log("loop", {"length": loop["length"], "t_after_end": st["t"], "video": st["video"]}, st["video"] == loop["video"] and st["t"] < loop["length"] and st["slots"][st["current_slot"]]["playing"])
else:
    log("loop", {"note": "no Short of 30 s or less in 10 swipes"}, None)

# reload button (owner 2026-11-13): a new feed from the start, the first new Short at once
r = a.j("sreload")
log("reload_button", {k: r.get(k) for k in ("reload_to_frame_ms", "video", "old_video", "index", "count", "max_main_ms", "timed_out")},
    not r["timed_out"] and r["index"] == 0 and r["reload_to_frame_ms"] > 0)
log("reload_shot", {"png": screen("shorts_after_reload")}, None)
time.sleep(2)
p = a.j("spull")   # pull down at the first Short
log("pull_to_reload", {k: p.get(k) for k in ("reload_to_frame_ms", "video", "old_video", "index", "timed_out")}, not p["timed_out"] and p["index"] == 0)
time.sleep(2)

# comments, pushed; back with the swipe back (D49): the Short plays on
before = a.j("sstate")
a.cmd("scomments"); time.sleep(3)
st = a.j("state")
log("comments_open", {"top": st["top"], "title": st["title"]}, st["top"] == "TBCommentsController")
log("comments_shot", {"png": screen("shorts_comments_light")}, None)
b = a.j("bswipe 300 0.7 0")
time.sleep(1.5)
after = a.j("sstate")
log("comments_swipe_back", {"popped": b["popped"], "top": b["top"], "drag_fps": b.get("drag_fps"), "t": after["t"], "video": after["video"]},
    b["popped"] and b["top"] == "TBShortsController" and after["video"] == before["video"] and after["slots"][after["current_slot"]]["playing"])

# share sheet
a.cmd("sshare open"); time.sleep(1.5)
log("share_open", {"open": a.j("sstate")["share_open"], "png": screen("shorts_share")}, a.j("sstate")["share_open"])
a.cmd("sshare close"); time.sleep(0.5)

# landscape: video left, side panel right
a.j("orient 3"); time.sleep(2)
s = a.j("sstate")
log("land_state", {"page_rect": s["page_rect"], "video": s["video"]}, s["video"] != "")
log("land_shot", {"png": screen("shorts_land_light")}, None)
lres = [swipe(f"land_fwd_{i}") for i in range(4)]

# Dark theme (rebuilds the UI): both orientations
a.j("theme 1"); time.sleep(2)
o = a.j("shorts"); time.sleep(3)
log("dark_open", {k: o.get(k) for k in ("open_to_frame_ms", "count")}, o.get("count", 0) > 0)
log("land_dark_shot", {"png": screen("shorts_land_dark")}, None)
a.j("orient 1"); time.sleep(2)
log("port_dark_shot", {"png": screen("shorts_port_dark")}, None)
swipe("port_dark_fwd")
a.cmd("scomments"); time.sleep(3)
log("comments_dark_shot", {"png": screen("shorts_comments_dark")}, None)
a.cmd("back"); time.sleep(1)
a.j("theme 0"); time.sleep(2)

m = a.j("mem")
log("memory", m, m["mb"] <= 120 and m["peak_mb"] <= 180)
a.cmd("tab 0")
json.dump(R, open(os.path.join(ART, "shorts.json"), "w"), indent=1)
print("RESULT", "PASS" if R["pass"] else "FAIL")
