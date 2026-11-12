"""Client for the self-test control port (iproxy 6124 -> iPad 127.0.0.1:5124) and screenshot helper."""
import json, os, socket, subprocess, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "tests", "artifacts", "device")


class App:
    def __init__(self, port=6124, timeout=120):
        for _ in range(40):
            try:
                self.s = socket.create_connection(("127.0.0.1", port), timeout=timeout)
                self.f = self.s.makefile("r")
                if self.cmd("ping") == "pong":
                    return
            except OSError:
                time.sleep(0.5)
        raise RuntimeError("no control port")

    def cmd(self, line):
        self.s.sendall((line + "\n").encode())
        return self.f.readline().strip()

    def j(self, line):
        r = self.cmd(line)
        try:
            return json.loads(r)
        except ValueError:
            raise RuntimeError(f"{line!r} -> {r!r}")


def shot(name):
    os.makedirs(ART, exist_ok=True)
    tiff = os.path.join(ART, name + ".tiff")
    png = os.path.join(ART, name + ".png")
    for _ in range(3):
        r = subprocess.run(["idevicescreenshot", tiff], capture_output=True, text=True)
        if os.path.exists(tiff):
            break
        time.sleep(2)
    else:
        print("screenshot failed:", r.stdout.strip(), r.stderr.strip())
        return None
    subprocess.run(["sips", "-s", "format", "png", tiff, "--out", png], capture_output=True)
    os.remove(tiff)
    return png


def _bmp(path):
    """Read a 24/32-bit BMP (sips output) -> (w, h, rows of (r, g, b)), top row first."""
    import struct
    d = open(path, "rb").read()
    off = struct.unpack_from("<I", d, 10)[0]
    w, h = struct.unpack_from("<ii", d, 18)
    bpp = struct.unpack_from("<H", d, 28)[0] // 8
    stride = (w * bpp + 3) & ~3
    top_down = h < 0
    h = abs(h)
    rows = []
    for y in range(h):
        sy = y if top_down else h - 1 - y
        base = off + sy * stride
        rows.append([(d[base + x * bpp + 2], d[base + x * bpp + 1], d[base + x * bpp]) for x in range(0, w)])
    return w, h, rows


def picture_stats(png, rect=None, step=4):
    """Mean luminance and spread of the pixels in rect=(x, y, w, h) (framebuffer pixels, portrait).
    A black or empty video area has mean < 12 and spread < 6."""
    bmp = png[:-4] + ".bmp"
    subprocess.run(["sips", "-s", "format", "bmp", png, "--out", bmp], capture_output=True)
    w, h, rows = _bmp(bmp)
    os.remove(bmp)
    x0, y0, rw, rh = rect or (0, 0, w, h)
    vals = []
    for y in range(int(y0), int(min(h, y0 + rh)), step):
        row = rows[y]
        for x in range(int(x0), int(min(w, x0 + rw)), step):
            r, g, b = row[x]
            vals.append(0.299 * r + 0.587 * g + 0.114 * b)
    if not vals:
        return {"mean": 0, "spread": 0, "n": 0}
    m = sum(vals) / len(vals)
    sd = (sum((v - m) ** 2 for v in vals) / len(vals)) ** 0.5
    return {"mean": round(m, 1), "spread": round(sd, 1), "n": len(vals), "size": [w, h]}


def is_picture(stats):
    return stats["mean"] >= 12 or stats["spread"] >= 6


def lum_grid(png, step=8):
    """Luminance samples on a grid (framebuffer pixels, portrait) for frame-to-frame comparison."""
    bmp = png[:-4] + ".bmp"
    subprocess.run(["sips", "-s", "format", "bmp", png, "--out", bmp], capture_output=True)
    w, h, rows = _bmp(bmp)
    os.remove(bmp)
    return w, h, {(x, y): 0.299 * rows[y][x][0] + 0.587 * rows[y][x][1] + 0.114 * rows[y][x][2]
                  for y in range(0, h, step) for x in range(0, w, step)}


def diff_outside(grid_a, grid_b, rect):
    """Mean absolute luminance difference of two lum_grid results outside rect=(x, y, w, h).
    Small (< 15) when the same app screen is in front; large for the home screen or a zoom animation."""
    if grid_a[:2] != grid_b[:2]:
        return 255.0  # another orientation: the home screen, not the app
    x0, y0, rw, rh = rect
    d = [abs(v - grid_b[2][k]) for k, v in grid_a[2].items() if not (x0 <= k[0] < x0 + rw and y0 <= k[1] < y0 + rh)]
    return round(sum(d) / max(1, len(d)), 1)
