# IDs: R5-WEB-FIRST
"""R5 (2026-11-12): main stall at the first web link after launch (PadWeb start parsed the CA roots on the main
thread: 120 ms). Fixed in PadWeb c9b567b6299d. Measures the largest main pass around the first and a second link."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART

a = App()
time.sleep(3)
R = {}
for i in range(2):
    a.cmd("root"); time.sleep(2); a.cmd("stallreset")
    a.cmd("link https://example.com/"); time.sleep(5)
    R[f"link_{i}"] = a.j("stalls"); a.cmd("dismiss"); time.sleep(2)
    print(f"link_{i}", R[f"link_{i}"], flush=True)
json.dump(R, open(os.path.join(ART, "web_first_link.json"), "w"), indent=1)
