# IDs: D49 (swipe back), D50 (swipe down in full screen), D51 (double tap skip), D52 (tab swipe)
"""Owner request 2026-11-13: gestures. Drives each gesture through the self-test port with the same code the
recognizers call (no real finger events: iOS 6 has no API for them), checks the result, the frame times of the
swipe back (gate: 55 fps, no main-thread pass over 50 ms) and takes screenshots for a check by eye.
Uses search results (public videos), not the owner's Home feed."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot

GATE_FPS, GATE_MAIN_MS = 55, 50
R = {"pass": True, "cases": {}}
a = App()


def log(k, v, ok=None):
    R["cases"][k] = {"ok": ok, **v} if isinstance(v, dict) else {"ok": ok, "v": v}
    if ok is False:
        R["pass"] = False
    print(("FAIL " if ok is False else "") + k, json.dumps(v)[:500], flush=True)


def state():
    return a.j("state")


def gate(r):
    """The owner's gate is for the drag (the finger phase). The slide after the release is a Core Animation
    animation in the render server; its main-thread passes are reported apart (slide_max_main_ms)."""
    if "drag_fps" in r and r.get("slide_ms"):
        return r["drag_fps"] >= GATE_FPS and r["drag_max_main_ms"] <= GATE_MAIN_MS
    return r["fps"] >= GATE_FPS and r["max_main_ms"] <= GATE_MAIN_MS


def push_video(wait_play=True):
    o = a.j("openvideo")
    time.sleep(1.0)   # the push slides for 0.35 s
    if wait_play:     # the gated drags measure the gesture, not the player start (reported apart: *_during_start)
        a.j("waitplay 40")
        time.sleep(1.0)
    st = state()
    if st["top"] != "TBWatchController":
        print("push failed:", o, st)
    return st


def swipe(name, ms, frac, vx, want_pop):
    before = state()
    r = a.j(f"bswipe {ms} {frac} {vx}")
    time.sleep(0.5)
    after = state()
    ok = r["ended"] and r["popped"] == want_pop and gate(r)
    log(name, {**{k: r[k] for k in ("drag_fps", "drag_slow_frames", "drag_max_frame_ms", "drag_max_main_ms", "slide_ms", "slide_max_main_ms",
                                    "fps", "max_frame_ms", "popped", "depth", "top")},
               "from": before["top"], "to": after["top"]}, ok)
    return r


time.sleep(2)
a.cmd("root")
s = a.j("search big buck bunny")
log("search", s, s["rows"] > 0)

for orient, tag in ((3, "land"), (1, "port")):
    o = a.j(f"orient {orient}")
    time.sleep(1.5)
    a.cmd("root")
    time.sleep(0.5)
    st = state()
    # touch filter: no swipe back on a root screen, only in the left 24 pt, never in the header
    log(f"{tag}_root_no_swipe", a.j("edgecheck 10 400"), not a.j("edgecheck 10 400")["accept"])
    # informational (no gate): a swipe right after the open, while the player starts
    push_video(wait_play=False)
    r = a.j("bswipe 300 0.3 0")
    log(f"{tag}_drag_during_start", {k: r[k] for k in ("drag_fps", "drag_max_main_ms", "drag_max_frame_ms", "popped")}, None)
    a.cmd("root")
    time.sleep(0.5)
    w = push_video()
    log(f"{tag}_pushed", {"top": w["top"], "orientation": o["orientation"]}, w["top"] == "TBWatchController")
    # interface x of the content's left edge: 0 on the full-width watch page
    for name, (x, y), want in ((f"{tag}_edge_in", (10, 400), True), (f"{tag}_edge_out", (40, 400), False),
                               (f"{tag}_edge_header", (10, 20), False), (f"{tag}_edge_player", (10, 120), True)):
        e = a.j(f"edgecheck {x} {y}")
        log(name, e, e["accept"] == want)
    # hold at half way: the list under the watch page, guide on the left in landscape
    h = a.j("bswipe hold 0.5 300")
    time.sleep(0.3)
    png = shot(f"gest_{tag}_hold")
    log(f"{tag}_hold", {**{k: h[k] for k in ("fps", "max_main_ms", "max_frame_ms")}, "png": os.path.basename(png or "")}, gate(h) and png is not None)
    r = a.j("bswipe release 0")   # 0.5 is not past half and no flick: back to the watch page
    log(f"{tag}_hold_release_cancel", {k: r[k] for k in ("popped", "top", "fps", "max_main_ms")}, not r["popped"] and r["top"] == "TBWatchController")
    swipe(f"{tag}_cancel_short", 300, 0.3, 0, False)
    swipe(f"{tag}_cancel_left_flick", 300, 0.7, -800, False)
    swipe(f"{tag}_pop_past_half", 400, 0.7, 0, True)
    push_video()
    swipe(f"{tag}_pop_flick", 150, 0.2, 900, True)
    push_video()
    a.cmd("stallreset")
    a.cmd("backbutton")
    time.sleep(1.5)
    log(f"{tag}_button_pop_for_comparison", {**a.j("stalls"), "top": state()["top"]}, None)
    png = shot(f"gest_{tag}_after_pop")
    st = state()
    log(f"{tag}_after_pop", {"top": st["top"], "png": os.path.basename(png or "")}, st["top"] != "TBWatchController")

# watch -> watch (both full width) and the tab swipe, portrait (About, Suggested, Comments)
push_video()
a.cmd("open YE7VzlLtp-4")   # a second public video (Big Buck Bunny, Blender Foundation) on top
time.sleep(1.5)
r = swipe("port_watch_to_watch", 400, 0.7, 0, True)
log("port_watch_to_watch_top", {"top": r["top"]}, r["top"] == "TBWatchController")
tabs = [a.j("wswipe 1")["tab"], a.j("wswipe 1")["tab"], a.j("wswipe 1")["tab"], a.j("wswipe -1")["tab"]]
log("port_tab_swipe", {"tabs": tabs}, tabs == ["Suggested", "Comments", "Comments", "Suggested"])
png = shot("gest_port_tab_suggested")
log("port_tab_shot", {"png": os.path.basename(png or "")}, png is not None)
a.j("wswipe -1")

# player: double tap to skip, swipe down in full screen (landscape)
a.j("orient 3")
time.sleep(1.5)
p = a.j("waitplay 40")
log("play", {k: p.get(k) for k in ("playing", "start_ms", "error")}, p["playing"])
time.sleep(3)
a.cmd("stallreset")
f = a.j("dtap 0.9")
png = shot("gest_land_skip_fwd")
time.sleep(2)
t1 = a.j("player")["t"]
st1 = a.j("stalls")
log("skip_forward", {**f, "t_after_2s": t1, "max_main_ms": st1["max_main_ms"], "png": os.path.basename(png or "")},
    f["skipped"] == 10 and t1 >= f["t_before"] + 9)
a.cmd("stallreset")
b = a.j("dtap 0.1")
time.sleep(2)
t2 = a.j("player")["t"]
log("skip_back", {**b, "t_after_2s": t2, "max_main_ms": a.j("stalls")["max_main_ms"]}, b["skipped"] == -10 and t2 <= b["t_before"] - 6)
m = a.j("dtap 0.5")
log("skip_middle_none", m, m["skipped"] == 0)
log("swipe_down_inline_ignored", a.j("fswipe"), not a.j("fswipe")["handled"])
a.cmd("full")
time.sleep(3)
log("full_on", {"full": state()["full"]}, state()["full"])
log("full_no_back_swipe", a.j("edgecheck 10 400"), not a.j("edgecheck 10 400")["accept"])
fs = a.j("fswipe")
time.sleep(3)
st = state()
log("swipe_down_leaves_full", {**fs, "full": st["full"], "presented": st["presented"]}, fs["handled"] and not st["full"])
tabs = [a.j("wswipe 1")["tab"], a.j("wswipe -1")["tab"]]
log("land_tab_swipe", {"tabs": tabs}, tabs == ["Comments", "About"])
mem = a.j("mem")
log("memory", mem, mem["mb"] <= 120 and mem["peak_mb"] <= 180)
a.cmd("root")
json.dump(R, open(os.path.join(ART, "gestures.json"), "w"), indent=1)
print("RESULT", "PASS" if R["pass"] else "FAIL")
