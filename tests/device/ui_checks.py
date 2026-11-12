# IDs: AC-LIB-2 BR-CAP-DRAW BR-VPAGE-COMMENTS BR-VPAGE-PARALLEL
"""Signed-out lists, comments on their own screen, captions drawn in full screen (screen pixels + caption text),
watch page data present by the first frame. Screenshots in tests/artifacts/device/ui_*.png are checked by eye."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot, picture_stats, is_picture

R = {"pass": True}
a = App()
def log(k, v, ok=None):
    R[k] = v
    if ok is False:
        R["pass"] = False
    print(("FAIL " if ok is False else "ok   " if ok else "") + k, json.dumps(v)[:500], flush=True)

time.sleep(2)
a.cmd("tab 1"); a.cmd("root"); time.sleep(3)
st = a.j("state"); e = a.j("empty")
log("subscriptions_signed_out", {**st, **e}, st["rows"] == 0 and "Sign in" in e["text"])
shot("ui_subs_signed_out")
a.cmd("tab 0"); a.cmd("root"); time.sleep(3)
st = a.j("state")
log("home_signed_out", st, st["rows"] > 0)
shot("ui_home")
a.cmd("setq 720")
a.cmd("open aircAruvnKk")
p = a.j("waitplay 40")
log("watch_page_parallel", {"start_ms": p["start_ms"], "related": p["related"], "chapters": p["chapters"]}, p["related"] > 0 and p["playing"])
a.cmd("cc 0"); time.sleep(8)
p = a.j("player")
log("caption_inline", {"caption": p["caption"], "cc": p["cc"]}, bool(p["caption"]))
a.cmd("full"); time.sleep(4)
p = a.j("player"); png = shot("ui_full_caption"); s = picture_stats(png)
log("caption_fullscreen", {"caption": p["caption"], **s}, bool(p["caption"]) and is_picture(s))
a.cmd("full"); time.sleep(2)
a.cmd("comments"); time.sleep(4)
st = a.j("state")
log("comments_screen", st, st["top"] == "TBCommentsController" and st["rows"] >= 10)
shot("ui_comments")
a.cmd("back")
a.cmd("theme dark"); time.sleep(1); shot("ui_watch_dark"); a.cmd("theme light")
json.dump(R, open(os.path.join(ART, "ui_checks.json"), "w"), indent=1)
print("RESULT", "PASS" if R["pass"] else "FAIL")
