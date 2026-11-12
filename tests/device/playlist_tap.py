# IDs: AC-LIB-PLAYLIST-OPEN BR-LIB-PLAYLIST-TV
"""Owner report 2026-11-12 "playlist tap does nothing": open playlists from the Playlists screen (private and public)
and a mix from Home; record the page that opens, its rows and its empty text."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot

R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:400], flush=True)
time.sleep(2)
a.j("orient 1")
a.cmd("tab 6"); time.sleep(4)
items = a.j("items")
log("playlists_screen", {"n": len(items.get("items", [])), "first": items.get("items", [])[:6]})
for row in range(min(4, len(items.get("items", [])))):
    a.cmd("tab 6"); time.sleep(3)
    log(f"open_{row}", a.j(f"openlist {row}")); time.sleep(5)
    st = a.j("state"); e = a.cmd("empty")
    log(f"page_{row}", {"top": st.get("top"), "title": st.get("title"), "rows": st.get("rows"), "empty": e})
    shot(f"playlist_tap_{row}")
json.dump(R, open(os.path.join(ART, "playlist_tap.json"), "w"), indent=1)
