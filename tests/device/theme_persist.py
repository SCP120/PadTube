# IDs: AC-THEME-2
"""The theme choice stays after the app quits. usage (two launches):
   theme_persist.py set   -> picks Dark and quits the app
   theme_persist.py check -> the new process must start in Dark; then picks Light again (the default)"""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART

a = App()
time.sleep(2)
if sys.argv[1] == "set":
    print("set", a.j("theme 1"))
    a.cmd("quit")
else:
    st = a.j("state")
    ok = st.get("dark") is True
    print("check", json.dumps({"dark_after_relaunch": st.get("dark"), "pass": ok}))
    print("reset", a.j("theme 0"))
    json.dump({"dark_after_relaunch": st.get("dark"), "pass": ok}, open(os.path.join(ART, "theme_persist.json"), "w"))
    sys.exit(0 if ok else 1)
