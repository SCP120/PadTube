"""Owner-approved icon (2026-11-12): after an install on top, show the home screen and take a screenshot."""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, shot
a = App()
time.sleep(2)
a.cmd("suspend")
time.sleep(2.5)
print("SHOT", shot("icon_home"))
