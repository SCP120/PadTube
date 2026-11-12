# IDs: owner bug 2026-11-13 "thumbnails blurred for a few seconds after the app opens"
"""Two launches of the app on Home (the owner's case): the one ipad_session.sh made (fresh install) and one more
after a quit (thumbnails on disk). Reads the in-app sampler (PTTHUMBS, every 100 ms: visible tiles, tiles with an
image, images with fewer pixels than the tile) and the image-load log (PTIMG) from the device log, and takes
screenshots as fast as idevicescreenshot allows. Screenshots of the owner's Home feed are deleted after the run:
only the numbers stay."""
import json, os, re, subprocess, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, ROOT, shot

LOG = os.path.join(ROOT, "build", "ipad", "device_syslog.txt")
R = {"launches": []}


def pid_lines(pid, tag):
    out = []
    for l in open(LOG, errors="replace"):
        if f"PadTube[{pid}]" in l and tag in l:
            out.append(l.rstrip())
    return out


def last_pid():
    pids = re.findall(r"PadTube\[(\d+)\] <\w+>: PTSELFTEST port", open(LOG, errors="replace").read())
    return pids[-1] if pids else None


def burst(tag, secs=6):
    t0, shots = time.time(), []
    while time.time() - t0 < secs:
        p = shot(f"thumb_{tag}_{len(shots):02d}")
        shots.append({"t_mac_s": round(time.time() - t0, 2), "png": p})
    return shots


def summary(pid):
    rows = []
    for l in pid_lines(pid, "PTTHUMBS"):
        m = re.search(r"t=(\d+) tiles=(\d+) img=(\d+) small=(\d+) min_img_px=(\d+) tile_px=(\d+)", l)
        if m:
            rows.append(dict(zip(("t", "tiles", "img", "small", "min_img_px", "tile_px"), map(int, m.groups()))))
    first_img = next((r["t"] for r in rows if r["img"] > 0), None)
    blurred = [r for r in rows if r["small"] > 0]
    sharp = next((r["t"] for r in rows if r["tiles"] > 0 and r["img"] == r["tiles"] and r["small"] == 0), None)
    imgs = pid_lines(pid, "PTIMG")
    sizes = {}
    for l in imgs:
        m = re.search(r"px (\d+)x(\d+) src (\d+) (\w+) (\d+) ms", l)
        if m:
            k = f"{m.group(1)}x{m.group(2)} from {m.group(3)} px ({m.group(4)})"
            sizes[k] = sizes.get(k, 0) + 1
    return {"pid": pid, "first_image_ms": first_img, "all_sharp_ms": sharp,
            "blurred_from_ms": blurred[0]["t"] if blurred else None, "blurred_until_ms": sharp if blurred else None,
            "max_small_tiles": max((r["small"] for r in rows), default=0), "image_loads": sizes, "samples": rows[:40]}


a = App()
a.cmd("tab 0")
pid = last_pid()
time.sleep(14)    # the sampler runs 15 s from launch
R["launches"].append({"name": "first launch after install", **summary(pid)})
a.cmd("quit")
time.sleep(2)
con = open(os.path.join(ROOT, "build", "ipad", "container.txt")).read().strip()
subprocess.run([os.path.join(ROOT, "build", "ipad", "ptlaunch"), f"{con}/PadTube.app/PadTube", con], capture_output=True)
t_launch = time.time()
shots = burst("relaunch")
time.sleep(max(0, 16 - (time.time() - t_launch)))
pid2 = last_pid()
R["launches"].append({"name": "relaunch (thumbnails on disk)", **summary(pid2), "screenshots": [s["t_mac_s"] for s in shots]})
for l in R["launches"]:
    print(l["name"], json.dumps({k: l[k] for k in ("first_image_ms", "all_sharp_ms", "blurred_from_ms", "blurred_until_ms", "max_small_tiles", "image_loads")}))
json.dump(R, open(os.path.join(ART, "thumb_launch.json"), "w"), indent=1)
keep = [s["png"] for s in shots if s["png"]]
print("screenshots:", keep)
