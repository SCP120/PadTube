# IDs: AC-THEME-1 AC-THEME-3 BR-THEME-STYLE BR-THEME-FAST
"""Theme audit (owner 2026-11-12, DUC-SET-THEME): every screen in Light and Dark, portrait and landscape, as
screenshots to read by eye: tests/artifacts/device/theme_<tag>_<mode>_<orient>_<screen>.png. Also scroll fps and
RAM in each mode. usage: theme_audit.py <tag> (for example "before" or "after1")."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot

TAG = sys.argv[1] if len(sys.argv) > 1 else "run"
R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:300], flush=True)
def snap(name):
    shot(f"theme_{TAG}_{name}")
def guide_row(title):
    return ["Home Feed", "Subscriptions", "Search", "History", "Watch Later", "Liked Videos", "Playlists",
            "YouTube History", "Live", "Account"].index(title)
time.sleep(2)
for mode, dark in [("dark", 1), ("light", 0)]:
    log(f"theme_{mode}", a.j(f"theme {dark}")); time.sleep(2)
    for o, on in [(1, "port"), (3, "land")]:
        k = f"{mode}_{on}"
        a.j(f"orient {o}"); time.sleep(1.5)
        a.cmd(f"tab {guide_row('Home Feed')}"); time.sleep(4); snap(f"{k}_home")
        a.cmd("mempeakreset"); log(f"scroll_home_{k}", a.j("scroll 6 1500"))
        if on == "port":
            a.cmd("guide"); time.sleep(1); snap(f"{k}_guide"); a.cmd("guide"); time.sleep(0.5)
        for title in ["Subscriptions", "Search", "History", "Watch Later", "Liked Videos", "Playlists", "YouTube History", "Live", "Account"]:
            a.cmd(f"tab {guide_row(title)}"); time.sleep(3); snap(f"{k}_{title.replace(' ', '').lower()}")
        a.cmd(f"tab {guide_row('Home Feed')}"); time.sleep(1)
        a.cmd("type lofi"); time.sleep(2.5); snap(f"{k}_suggest"); a.cmd("endtype"); time.sleep(0.5)
        log(f"search_{k}", a.j("search lofi")); time.sleep(2); snap(f"{k}_search")
        log(f"scroll_search_{k}", a.j("scroll 6 1500"))
        a.j("search 3blue1brown"); time.sleep(1); a.cmd("openlist 0"); time.sleep(4); snap(f"{k}_channel")
        a.cmd("openvideo"); a.j("waitplay 30"); time.sleep(3); snap(f"{k}_watch")
        if on == "port":
            a.cmd("wtab Suggested"); time.sleep(2); snap(f"{k}_suggested")
        a.cmd("wtab Comments"); time.sleep(4); snap(f"{k}_comments")
        a.cmd("wtab About")
        a.cmd("full"); time.sleep(3); snap(f"{k}_full"); a.cmd("full"); time.sleep(2)
        a.cmd("link https://example.com/"); time.sleep(4); snap(f"{k}_web"); a.cmd("dismiss"); time.sleep(1)
        a.cmd("root"); time.sleep(1)
    log(f"mem_{mode}", a.j("mem"))
json.dump(R, open(os.path.join(ART, f"theme_{TAG}.json"), "w"), indent=1)
