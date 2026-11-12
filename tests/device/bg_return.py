# IDs: AC-BG-RETURN BR-PLAY-BG-PICTURE
"""Owner bug 2026-11-12: after a return from another app or the home screen the video stayed on "loading" for
about 30 s. Cases: away 1 min and 5 min, video playing or paused when leaving. Measures from the return: time to
the picture (screenshots, front check against a reference shot), time until the clock moves (playing), and the
PadTube log lines with time stamps (tb_stream / tb_hls / PadTube) for the first 40 s.
Gate: picture back within 2 s of the return (the app itself is in front about 1 s after it: iOS zoom).
usage: bg_return.py [minutes ...]   default: 1 5"""
import json, os, re, subprocess, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, ART, shot, picture_stats, is_picture, lum_grid, diff_outside

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CON = open(os.path.join(ROOT, "build/ipad/container.txt")).read().strip()
MINUTES = [float(x) for x in sys.argv[1:]] or [1, 5]
R = {}
a = App()
def log(k, v):
    R[k] = v
    print(k, json.dumps(v)[:700], flush=True)
def rect():
    m = re.findall(r"[-\d.]+", a.j("state").get("player_rect", ""))
    return tuple(float(x) for x in m) if len(m) == 4 else None
time.sleep(2)
a.j("orient 1"); a.cmd("setq 720"); a.cmd("root")
a.cmd("open BDqvzFY72mg"); log("start", {k: v for k, v in a.j("waitplay 40").items() if k in ("start_ms", "playing")})
time.sleep(5)
for mins in MINUTES:
    for state in ["playing", "paused"]:
        k = f"{state}_{mins:g}min"
        p = a.j("player")
        if state == "paused" and p["playing"]: a.cmd("pause"); time.sleep(1)
        if state == "playing" and not p["playing"]: a.cmd("pause"); time.sleep(2)
        r = rect(); ref = lum_grid(shot(f"ret_{k}_ref"))
        a.cmd("suspend"); t_bg = time.time()
        time.sleep(mins * 60)
        mark = time.strftime("%H:%M:%S")
        subprocess.run([os.path.join(ROOT, "build/ipad/ptlaunch"), CON + "/PadTube.app/PadTube", CON], capture_output=True)
        t_fg = time.time()
        shots, first_pic = [], None
        while time.time() - t_fg < 8 and first_pic is None:
            t0 = time.time() - t_fg; png = shot(f"ret_{k}_{len(shots):02d}"); t1 = time.time() - t_fg
            front = diff_outside(ref, lum_grid(png), r); pic = picture_stats(png, r)
            shots.append((round(t0, 2), round(t1, 2), front, pic["mean"], pic["spread"]))
            if front < 15 and is_picture(pic): first_pic = [round(t0, 2), round(t1, 2)]
        if state == "paused": a.cmd("pause")           # the owner presses play again
        t_play = None; c0 = a.j("player")["t"]
        for i in range(80):                              # 40 s
            time.sleep(0.5); c = a.j("player")
            if c["playing"] and c["t"] > c0 + 0.4: t_play = round(time.time() - t_fg, 2); break
        log(k, {"away_s": round(t_fg - t_bg), "return_at": mark, "first_picture_s": first_pic, "clock_moves_s": t_play,
                "shots": shots, **a.j("stalls")})
        time.sleep(3)
json.dump(R, open(os.path.join(ART, "bg_return.json"), "w"), indent=1)
