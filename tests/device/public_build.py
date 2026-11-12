"""Public build on the iPad (docs/release.md §6): a self-test copy with its own bundle (dev.padtube.public), so its
data folder is empty and no screenshot can show the owner's account. Start, search, play, light and dark, then a web
link, which must leave PadTube for Safari (D46). Screenshots: tests/artifacts/device/public/ (look at each by eye)."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import tb
from tb import App

tb.ART = os.path.join(tb.ART, "public")
a = App()
out = {"start_state": a.j("state")}
time.sleep(3)
tb.shot("01_home_light")
t0 = time.time(); out["search"] = a.j("search Big Buck Bunny Blender"); out["search_s"] = round(time.time() - t0, 2)
time.sleep(2)
tb.shot("02_search_light")
a.cmd("openlist 0")
out["play"] = a.j("waitplay 30")
time.sleep(4)
tb.shot("03_watch_light")
out["dark"] = a.j("theme 1")
time.sleep(3)
tb.shot("04_watch_dark")
a.cmd("root")
time.sleep(2)
tb.shot("05_search_dark")
a.j("theme 0")
out["mem"] = a.cmd("mem")
a.cmd("link https://example.com/")
time.sleep(4)
tb.shot("06_after_link")
out["after_link_state"] = a.cmd("state")
print(json.dumps(out, indent=1))
