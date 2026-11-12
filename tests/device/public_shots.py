"""README screenshots of the public copy (dev.padtube.public): dark watch page in portrait and landscape, at a later
frame of a CC-BY film (Big Buck Bunny, Blender Foundation). Run after public_build.py, with --no-install."""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import tb
from tb import App

tb.ART = os.path.join(tb.ART, "public")
a = App()
a.j("theme 1")
a.j("search Big Buck Bunny Blender")
time.sleep(1.5)
a.cmd("openlist 0")
print("play", a.j("waitplay 30").get("start_ms"))
a.cmd("seek 95")
time.sleep(6)
tb.shot("07_watch_dark_portrait")
a.cmd("orient 3")
time.sleep(4)
tb.shot("08_watch_dark_landscape")
a.cmd("wtab 1")
time.sleep(3)
tb.shot("09_watch_dark_landscape_suggested")
a.cmd("orient 1")
a.j("theme 0")
print("mem", a.cmd("mem"))
