"""Draw the 0.18 terrain-variant sprites into assets/art/map/common/ and add them to its manifest.

goldgrass  - a clump of tall golden grass (Drylands; it sways like the border trees)
bigpuddle  - a wide, uneven pool (Bogs)
mangrove   - a mangrove on arching prop roots (the trees round a Bog), plus mangrove_L for border bands
crossing0-7 - a border's stepping stone at 8 turns (drawn from the map's own shapes, so it batches with the rest)

Same look as the web game's map sprites: drawn 4x, thick dark ink outline, flat fills with one highlight.
Run: python3 tools/make_variant_art.py
"""
import json
import math
import os
import random

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "art", "map", "common")
INK = (31, 27, 36, 255)
SS = 4  # supersampling on top of the sprites' own 4x


def canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def done(im, w, h):
    return im.resize((w, h), Image.LANCZOS)


def blade(d, x0, y0, x1, y1, bend, width, fill, ink=True):
    pts = []
    for i in range(13):
        t = i / 12
        x = x0 + (x1 - x0) * t + bend * math.sin(t * math.pi * 0.9) * t
        y = y0 + (y1 - y0) * t
        pts.append((x, y))
    if ink:
        d.line(pts, fill=INK, width=int(width + 4 * SS), joint="curve")
    d.line(pts, fill=fill, width=int(width), joint="curve")


def goldgrass():
    w, h = 64, 96
    im = canvas(w, h)
    d = ImageDraw.Draw(im)
    rnd = random.Random(7)
    base = (w * SS / 2, (h - 8) * SS)
    blades = []
    for i in range(7):
        ang = -0.42 + i * 0.14 + rnd.uniform(-0.04, 0.04)
        ln = rnd.uniform(44, 62) * SS
        blades.append((ang, ln))
    cols = [(226, 184, 74, 255), (240, 205, 104, 255), (201, 154, 46, 255)]
    for ink in (True, False):
        for i, (ang, ln) in enumerate(blades):
            x1 = base[0] + math.sin(ang) * ln
            y1 = base[1] - math.cos(ang) * ln
            bx = base[0] + (i - 3) * 2.2 * SS
            blade(d, bx, base[1], x1, y1, ang * 10 * SS, 3.5 * SS, cols[i % 3], ink) if ink else blade(d, bx, base[1], x1, y1, ang * 10 * SS, 3.5 * SS, cols[i % 3], False)
    # seed heads: slim golden ears on every other blade
    for i, (ang, ln) in enumerate(blades):
        if i % 2 == 0:
            x1 = base[0] + math.sin(ang) * ln + ang * 10 * SS * math.sin(math.pi * 0.9)
            y1 = base[1] - math.cos(ang) * ln
            r = 4 * SS
            d.ellipse((x1 - r, y1 - r * 2.6, x1 + r, y1 + r * 0.5), fill=(247, 222, 140, 255), outline=INK, width=int(2 * SS))
    return done(im, w, h), {"w": w, "h": h, "ax": w // 2, "ay": h - 8, "scale": 2}   # (drawn twice the size of a tuft)


def blob(cx, cy, rx, ry, n, rnd, wob):
    pts = []
    for i in range(n):
        a = i / n * math.tau
        k = 1 + rnd.uniform(-wob, wob)
        pts.append((cx + math.cos(a) * rx * k, cy + math.sin(a) * ry * k))
    return pts


def smooth(pts, n):
    """Chaikin-round a closed polygon n times."""
    for _ in range(n):
        out = []
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            out.append((a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25))
            out.append((a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75))
        pts = out
    return pts


def bigpuddle():
    w, h = 184, 96
    im = canvas(w, h)
    d = ImageDraw.Draw(im)
    rnd = random.Random(3)
    cx, cy = w * SS / 2, h * SS / 2
    outer = blob(cx, cy, 82 * SS, 38 * SS, 10, rnd, 0.12)
    outer = smooth(outer, 6)
    d.polygon(outer, fill=INK)
    inner = [(cx + (x - cx) * 0.93, cy + (y - cy) * 0.86) for x, y in outer]
    d.polygon(inner, fill=(58, 112, 112, 255))
    deep = [(cx + (x - cx) * 0.7 + 6 * SS, cy + (y - cy) * 0.6 + 4 * SS) for x, y in outer]
    d.polygon(deep, fill=(47, 94, 98, 255))
    d.ellipse((cx - 56 * SS, cy - 26 * SS, cx - 18 * SS, cy - 16 * SS), fill=(140, 196, 196, 255))
    d.ellipse((cx + 20 * SS, cy + 10 * SS, cx + 40 * SS, cy + 16 * SS), fill=(110, 170, 170, 255))
    return done(im, w, h), {"w": w, "h": h, "ax": w // 2, "ay": h // 2, "scale": 2}


def mangrove(big):
    w, h = (352, 432) if big else (176, 216)
    k = 2 if big else 1
    im = canvas(w, h)
    d = ImageDraw.Draw(im)
    rnd = random.Random(11)
    S = SS * k
    cx = w * SS / 2
    gy = (h - 16 * k) * SS   # the ground line
    # shadow
    d.ellipse((cx - 50 * S, gy - 8 * S, cx + 50 * S, gy + 10 * S), fill=(0, 0, 0, 40))
    # prop roots: arches from the trunk's foot out to the mud
    trunk_y = gy - 60 * S
    roots = [(-46, 0), (-30, 4), (-12, 6), (12, 6), (30, 4), (46, 0)]
    for ink in (True, False):
        for dx, dy in roots:
            pts = []
            for i in range(17):
                t = i / 16
                x = cx + dx * S * t
                y = trunk_y + (gy + dy * S - trunk_y) * (t ** 1.6) - math.sin(t * math.pi) * 10 * S * (1 if abs(dx) > 20 else 0.4)
                pts.append((x, y))
            d.line(pts, fill=INK if ink else (125, 92, 62, 255), width=int((11 if ink else 5) * S), joint="curve")
    # trunk
    d.polygon([(cx - 11 * S, trunk_y + 4 * S), (cx + 11 * S, trunk_y + 4 * S), (cx + 7 * S, gy - 150 * S), (cx - 7 * S, gy - 150 * S)], fill=INK)
    d.polygon([(cx - 6 * S, trunk_y), (cx + 6 * S, trunk_y), (cx + 3 * S, gy - 150 * S), (cx - 3 * S, gy - 150 * S)], fill=(125, 92, 62, 255))
    # canopy: a wide low dome of leaf clumps
    clumps = [(-34, -150, 30), (34, -150, 30), (0, -168, 34), (-56, -128, 22), (56, -128, 22), (-18, -136, 26), (18, -136, 26)]
    for c in clumps:
        x, y, r = cx + c[0] * S, gy + c[1] * S, c[2] * S
        d.ellipse((x - r - 6 * S, y - r * 0.8 - 6 * S, x + r + 6 * S, y + r * 0.8 + 6 * S), fill=INK)
    for c in clumps:
        x, y, r = cx + c[0] * S, gy + c[1] * S, c[2] * S
        d.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.8), fill=(52, 118, 74, 255))
    for c in clumps[:3]:
        x, y, r = cx + c[0] * S, gy + c[1] * S, c[2] * S
        d.ellipse((x - r * 0.55 - 6 * S, y - r * 0.55, x + r * 0.2 - 6 * S, y - r * 0.05), fill=(86, 158, 98, 255))
    # hanging aerial roots
    for i in range(5):
        x = cx + (-40 + i * 20) * S + rnd.uniform(-3, 3) * S
        y0 = gy - 128 * S
        d.line([(x, y0), (x + 2 * S, y0 + rnd.uniform(26, 40) * S)], fill=(150, 120, 86, 255), width=int(3 * S))
    return done(im, w, h), {"w": w, "h": h, "ax": w // 2, "ay": h - 16 * k, "scale": 4}


def crossing(k):
    """A border's stepping stone (the map drew it with polygons: now a picture, 8 turns across half a circle)."""
    w = h = 136
    im = canvas(w, h)
    d = ImageDraw.Draw(im)
    a = k * math.pi / 8
    S = 4 * SS
    cx, cy = w * SS / 2, h * SS / 2

    def ell(ex, ey, rx, ry):
        pts = []
        for i in range(48):
            t = i / 48 * math.tau
            x, y = ex + math.cos(t) * rx, ey + math.sin(t) * ry
            pts.append((cx + (x * math.cos(a) - y * math.sin(a)) * S, cy + (x * math.sin(a) + y * math.cos(a)) * S))
        return pts
    ink = (29, 26, 34, 255)
    d.polygon(ell(0, 0, 10.8, 15.8), fill=ink)
    d.polygon(ell(0, 0, 10, 15), fill=(217, 183, 122, 255))
    for dy in (-6.0, 6.0):
        d.polygon(ell(dy * 0.3, dy, 4.15, 3.15), fill=ink)
        d.polygon(ell(dy * 0.3, dy, 3.6, 2.6), fill=(176, 138, 85, 255))
    return done(im, w, h), {"w": w, "h": h, "ax": w // 2, "ay": h // 2, "scale": 4}


def main():
    man_path = os.path.join(OUT, "manifest.json")
    man = json.load(open(man_path))
    for name, (im, info) in {"goldgrass.png": goldgrass(), "bigpuddle.png": bigpuddle(),
                             "mangrove.png": mangrove(False), "mangrove_L.png": mangrove(True),
                             **{"crossing%d.png" % k: crossing(k) for k in range(8)}}.items():
        im.save(os.path.join(OUT, name))
        man["images"][name] = info
    json.dump(man, open(man_path, "w"), indent=1)
    print("ok")


if __name__ == "__main__":
    main()
