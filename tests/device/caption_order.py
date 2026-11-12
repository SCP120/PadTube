# IDs: AC-CAP-ORDER
"""Owner report 2026-11-12 (Arabic first in the Subtitles list): the list order on the iPad, for a video with many
manual tracks. The device languages come first, then English (tb_caps_sort, golden test test_captions_order.c)."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART

a = App()
time.sleep(2)
a.cmd("open UF8uR6Z6KLc")            # Steve Jobs, Stanford 2005: tens of manual subtitle tracks
p = a.j("waitplay 30")
r = {"cc_tracks": p.get("cc_tracks", "").split(","), "cc_on_start": p.get("cc")}
print("order", json.dumps(r)[:600])
json.dump(r, open(os.path.join(ART, "caption_order.json"), "w"), indent=1)
a.cmd("root")
