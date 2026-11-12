"""Capture the signed-in Home feed: raw TV browse answers (first page + 2 continuations) in Documents/dump, and the
list as the app shows it. Private account data: the Mac side copies it to local/ (git-ignored) only."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART
a = App()
time.sleep(2)
st = a.j("state")
if not st["signed_in"]:
    sys.exit("not signed in")
print("dump", a.j("dump on"))
a.cmd("orient 3")
a.cmd("tab 1"); time.sleep(1)
a.cmd("tab 0"); time.sleep(1)
# a fresh load of Home with the dump on
a.cmd("reloadtop"); time.sleep(6)
a.j("scroll 8 2500")  # scroll to load continuations
items = a.j("items")["items"]
a.j("dump off")
ids = [i[0] for i in items]
dups = sorted({x for x in ids if ids.count(x) > 1})
print("ITEMS", len(ids), "unique", len(set(ids)), "dups", len(dups))
os.makedirs(os.path.join(os.path.dirname(ART), "..", "..", "local", "capture"), exist_ok=True)
json.dump(items, open(os.path.join(os.path.dirname(__file__), "..", "..", "local", "capture", "home_items.json"), "w"), indent=1)
