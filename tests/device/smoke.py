"""First device run: app starts, search, play one video, screenshots."""
import json, sys, time
sys.path.insert(0, __import__("os").path.dirname(__file__))
from tb import App, shot

a = App()
print("state", a.cmd("state"))
time.sleep(2)
shot("00_home")
r = a.j("search lofi music")
print("search", r)
time.sleep(1.5)
shot("01_search")
print("open", a.cmd("openlist 0"))
r = a.j("waitplay 30")
print("play", json.dumps(r))
time.sleep(3)
shot("02_watch")
print("player", a.cmd("player"))
print("mem", a.cmd("mem"))
