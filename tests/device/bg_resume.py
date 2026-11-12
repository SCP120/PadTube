# IDs: AC-BG-1 AC-BG-2 BR-PLAY-BG-INTENT BR-PLAY-BG-PICTURE
"""Background audio and return (owner 2026-11-12): play, send PadTube to the background (home-button path), wait,
bring it back. Records: sound kept (clock moves, audio-only switch), main stalls and CPU after return, time to the
first real picture after return (screenshots + pixel test), memory. Cases: 30 s and 120 s in the background."""
import json, os, subprocess, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import re
from tb import App, ART, shot, picture_stats, is_picture, lum_grid, diff_outside

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CON = open(os.path.join(ROOT, "build/ipad/container.txt")).read().strip()
R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:600], flush=True)
time.sleep(2)
a.cmd("orient 1"); a.cmd("setq 720"); a.cmd("root")
a.cmd("open aircAruvnKk"); log("start", {k: v for k, v in a.j("waitplay 30").items() if k in ("start_ms", "playing")})
time.sleep(5)
def player_rect():
    m = re.findall(r"[-\d.]+", a.j("state").get("player_rect", ""))
    return tuple(float(x) for x in m) if len(m) == 4 else None

for secs in [30, 120]:
    rect = player_rect()
    ref = lum_grid(shot(f"before_bg_{secs}"))   # the watch page in front, video playing
    p0 = a.j("player"); c0 = a.j("cpu")
    a.cmd("suspend"); t_bg = time.time()
    samples = []
    while time.time() - t_bg < secs:
        time.sleep(5)
        try:
            p = a.j("player"); samples.append((round(time.time() - t_bg, 1), round(p["t"], 1), p["playing"], p["audio_only"], round(p["mem_mb"], 1)))
        except Exception as e:
            samples.append((round(time.time() - t_bg, 1), "no answer", str(e)[:40]))
    # the clock must move about 5 s per 5 s sample; a gap shows as a smaller step
    steps = [round(samples[i][1] - samples[i - 1][1], 1) for i in range(1, len(samples)) if isinstance(samples[i][1], float) and isinstance(samples[i - 1][1], float)]
    c1 = a.j("cpu")
    log(f"bg_{secs}s", {"samples": samples, "clock_steps": steps, "cpu_s_in_bg": round(c1["cpu_s"] - c0["cpu_s"], 2)})
    a.cmd("stallreset")
    subprocess.run([os.path.join(ROOT, "build/ipad/ptlaunch"), CON + "/PadTube.app/PadTube", CON], capture_output=True)
    t_fg = time.time()
    shots, first_pic = [], None
    while time.time() - t_fg < 6 and first_pic is None:
        t_a = time.time() - t_fg
        png = shot(f"resume_{secs}_{len(shots):02d}")
        t_b = time.time() - t_fg
        g = lum_grid(png)
        front = diff_outside(ref, g, rect)          # the app screen (not the home screen or the zoom) is in front
        pic = picture_stats(png, rect)
        shots.append((round(t_a, 2), round(t_b, 2), front, pic["mean"], pic["spread"]))
        if front < 15 and is_picture(pic):
            first_pic = [round(t_a, 2), round(t_b, 2)]   # the frame was taken between these two times
    trans = a.j("stalls")                             # includes iOS's return transition
    wait = 1.0 - (time.time() - t_fg)
    if wait > 0: time.sleep(wait)
    a.cmd("stallreset"); time.sleep(5)                # the gate window: from 1 s after return
    p = a.j("player")
    log(f"resume_{secs}s", {"first_picture_s": first_pic, "shots(t0,t1,front_diff,mean,spread)": shots,
                            "max_main_ms_with_transition": trans.get("max_main_ms"), "after_1s": a.j("stalls"),
                            "playing": p["playing"], "audio_only": p["audio_only"], "t": p["t"], **a.j("cpu")})
    time.sleep(5)
json.dump(R, open(os.path.join(ART, "bg_resume.json"), "w"), indent=1)
