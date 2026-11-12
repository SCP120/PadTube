# IDs: Shorts preload strategy (owner 2026-11-13): swipe -> first frame p50/p95 (target <= 500 ms), 1st..5th swipe in a
# row, fast flicks, back swipes, fps in the swipe (>= 55), main-thread passes (<= 50 ms), RAM, data and CPU per minute
"""One benchmark run of the Shorts tab (portrait). Usage: shorts_bench.py <step name>. Writes
tests/artifacts/device/shorts_bench_<step>.json; the numbers go to docs/STATUS.md (one row per optimisation step)."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART

STEP = sys.argv[1] if len(sys.argv) > 1 else "run"
SLOTS = int(sys.argv[2]) if len(sys.argv) > 2 else 0     # 0: the app's default
GATE = int(sys.argv[3]) if len(sys.argv) > 3 else 0      # 1: the server's preload gate (segment 0 only for the next)
PREROLL = int(sys.argv[4]) if len(sys.argv) > 4 else 0   # 1: prerollAtRate: on the prepared player
a = App(timeout=60)


def pct(v, p):   # nearest rank
    s = sorted(v)
    return s[max(0, min(len(s) - 1, int(round(p / 100 * len(s) + 0.5)) - 1))] if s else None


def swipe(d=1):
    a.cmd("stallreset")
    r = a.j(f"sswipe {d}")
    return {"ms": round(r["settle_to_frame_ms"]), "timed_out": r["timed_out"], "prepared": r["prepared"], "fps": round(r["fps"], 1),
            "main": round(max(r["swipe_max_main_ms"], r["to_frame_max_main_ms"])), "swipe_main": round(r["swipe_max_main_ms"])}


def watch(sec):
    a.cmd("stallreset")
    time.sleep(sec)
    return round(a.j("stalls")["max_main_ms"])


time.sleep(2)
a.cmd("root")
a.j("orient 1")
time.sleep(1)
a.cmd(f"sab 1 720 {SLOTS} {GATE} {PREROLL}")   # before the Shorts tab is made
a.cmd("mempeakreset")
o = a.j("shorts")
time.sleep(4)
n0, t0 = a.j("net"), time.time()
R = {"step": STEP, "open_ms": round(o.get("open_to_frame_ms") or -1)}
A, Aw = [], []
for i in range(12):           # normal watching: 3 s per Short
    A.append(swipe())
    Aw.append(watch(3))
B = []
for i in range(5):            # in a row: 1 s per Short
    B.append(swipe())
    time.sleep(1)
time.sleep(3)
C = []
for i in range(3):            # fast flick: two swipes 0.15 s apart, the second one lands
    a.j("sswipe 1")
    time.sleep(0.15)
    C.append(swipe())
    time.sleep(3)
D = []
for i in range(3):            # back
    D.append(swipe(-1))
    time.sleep(3)
E = []
for i in range(2):            # the reload button: a new feed, the first new Short at once
    r = a.j("sreload")
    E.append({"ms": round(r["reload_to_frame_ms"]), "new": r["video"] != r["old_video"], "main": round(r["max_main_ms"]), "timed_out": r["timed_out"]})
    time.sleep(3)
n1, t1 = a.j("net"), time.time()
m = a.j("mem")
fwd = [x["ms"] for x in A + B if not x["timed_out"]]
mins = (t1 - t0) / 60
R.update({
    "forward_p50_ms": pct(fwd, 50), "forward_p95_ms": pct(fwd, 95), "forward_max_ms": max(fwd) if fwd else None,
    "in_a_row_ms": [x["ms"] for x in B], "fast_flick_ms": [x["ms"] for x in C], "back_ms": [x["ms"] for x in D],
    "timeouts": sum(x["timed_out"] for x in A + B + C + D),
    "swipe_fps_min": min(x["fps"] for x in A + B + C + D),
    "swipe_main_max_ms": max(x["swipe_main"] for x in A + B + C + D),
    "swipe_to_frame_main_p95_ms": pct([x["main"] for x in A + B + C + D], 95), "swipe_to_frame_main_max_ms": max(x["main"] for x in A + B + C + D),
    "watching_main_p95_ms": pct(Aw, 95), "watching_main_max_ms": max(Aw),
    "ram_mb": round(m["mb"], 1), "ram_peak_mb": round(m["peak_mb"], 1),
    "mb_per_min": round((n1["bytes_in"] - n0["bytes_in"]) / 1048576 / mins, 1), "cpu_s_per_min": round((n1["cpu_s"] - n0["cpu_s"]) / mins, 1),
    "reload_ms": [x["ms"] for x in E], "reload_new_feed": all(x["new"] for x in E), "reload_main_max_ms": max(x["main"] for x in E),
    "player_calls_per_min": round((n1["player_calls"] - n0["player_calls"]) / mins, 1), "login_required": n1["login_required"] - n0["login_required"],
    "visitor_resets": n1["visitor_resets"] - n0["visitor_resets"], "shorts_viewed": len(A + B + C + D) + 3,
    "battery_state": n1["battery_state"], "minutes": round(mins, 2),
    "raw": {"A": A, "A_watch": Aw, "B": B, "C": C, "D": D, "E": E}})
print(json.dumps({k: v for k, v in R.items() if k != "raw"}))
json.dump(R, open(os.path.join(ART, f"shorts_bench_{STEP}.json"), "w"), indent=1)
a.cmd("sab 1 720 0")
a.cmd("tab 0")
