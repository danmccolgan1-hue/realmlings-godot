"""The Woodlings' houses (0.18): little cottages grown into tree stumps, with a door, a lit window and a roof of leaves
or a mushroom cap, so they read as houses among the trees (the web game's Woodling house was a tree with a door,
which looked like any other tree on the map). Six looks; each also in the eight nation colors on its roof, like the
other races' houses. Writes assets/art/houses/wood/house_v<k>[_r<hex>].png and their manifest entries.
Run from the repository root: python3 tools/make_wood_houses.py
"""
import json
import math
from PIL import Image, ImageDraw

OL = (29, 26, 34, 255)
K = 6                    # drawn 6x larger, then shrunk, for smooth edges
W, H = 66, 78            # the image (3 pixels to a map unit, like the other houses)
AX, AY = 33, 66          # where it stands on the map
ROOFS = ["1f9fa5", "2f6fe0", "2f9e55", "4b4f5c", "8a4fd0", "c23f8f", "d23b3b", "e08a1e"]
LEAF = (86, 160, 72, 255)
CAP = (196, 72, 58, 255)
BARK = (122, 84, 52, 255)
BARK_D = (92, 62, 38, 255)
WOOD = (165, 120, 74, 255)
GLOW = (255, 214, 102, 255)


def P(x, y):
    return (x * K, y * K)


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (255,)


def stump(d, cx, base, w, h):
    """the stump that is the house's walls, with bark lines"""
    x0, x1 = cx - w / 2, cx + w / 2
    d.rounded_rectangle([P(x0, base - h), P(x1, base)], radius=w * K * 0.18, fill=BARK, outline=OL, width=int(K * 1.4))
    for k in range(3):
        bx = x0 + w * (0.22 + 0.28 * k)
        d.line([P(bx, base - h + 3), P(bx + 0.8, base - 2)], fill=BARK_D, width=int(K * 0.9))
    # roots
    for sg in (-1, 1):
        d.polygon([P(cx + sg * w / 2 - sg * 2, base - 3), P(cx + sg * (w / 2 + 4), base + 1), P(cx + sg * w / 2 - sg * 5, base)], fill=BARK, outline=OL)


def door(d, cx, base, w=8, h=11):
    d.rounded_rectangle([P(cx - w / 2 - 1, base - h - 1), P(cx + w / 2 + 1, base)], radius=w * K / 2, fill=WOOD, outline=OL, width=int(K * 1.1))
    d.rounded_rectangle([P(cx - w / 2 + 1, base - h + 1), P(cx + w / 2 - 1, base)], radius=w * K / 2 - K, fill=shade(WOOD, 0.6))
    d.ellipse([P(cx + w / 2 - 2.6, base - h / 2 - 0.6), P(cx + w / 2 - 1.4, base - h / 2 + 0.6)], fill=GLOW)


def window(d, x, y, r=2.6):
    d.ellipse([P(x - r - 0.8, y - r - 0.8), P(x + r + 0.8, y + r + 0.8)], fill=WOOD, outline=OL, width=int(K * 0.9))
    d.ellipse([P(x - r, y - r), P(x + r, y + r)], fill=GLOW)
    d.line([P(x - r, y), P(x + r, y)], fill=OL, width=int(K * 0.6))
    d.line([P(x, y - r), P(x, y + r)], fill=OL, width=int(K * 0.6))


def leaf_roof(d, cx, top, base, w, col):
    """a cone of overlapping leaves"""
    d.polygon([P(cx, top), P(cx + w / 2, base), P(cx - w / 2, base)], fill=col, outline=OL, width=int(K * 1.4))
    for row in range(3):
        y = top + (base - top) * (0.35 + 0.25 * row)
        half = w / 2 * (0.35 + 0.25 * row)
        n = 2 + row
        for k in range(n):
            x = cx - half + (2 * half) * (k + 0.5) / n
            d.arc([P(x - 3, y - 2.5), P(x + 3, y + 2.5)], 10, 170, fill=shade(col, 0.68), width=int(K * 0.9))


def cap_roof(d, cx, base, w, h, col, dots=True):
    """a mushroom cap"""
    d.chord([P(cx - w / 2, base - h), P(cx + w / 2, base + h)], 180, 360, fill=col, outline=OL, width=int(K * 1.4))
    d.line([P(cx - w / 2, base), P(cx + w / 2, base)], fill=OL, width=int(K * 1.4))
    if dots:
        for (dx, dy, r) in ((-0.25, 0.55, 2.2), (0.12, 0.75, 1.8), (0.3, 0.42, 1.6), (-0.05, 0.3, 1.4)):
            x, y = cx + dx * w, base - dy * h
            d.ellipse([P(x - r, y - r), P(x + r, y + r)], fill=(250, 241, 220, 255), outline=OL, width=int(K * 0.5))


def chimney(d, x, base, h):
    d.rectangle([P(x - 2, base - h), P(x + 2, base)], fill=(140, 140, 150, 255), outline=OL, width=int(K * 1.0))


def lantern(d, x, y):
    d.line([P(x, y - 6), P(x, y)], fill=OL, width=int(K * 0.8))
    d.rounded_rectangle([P(x - 2, y), P(x + 2, y + 4)], radius=K, fill=GLOW, outline=OL, width=int(K * 0.7))


def house(v, roof):
    im = Image.new("RGBA", (W * K, H * K), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, base = AX, AY
    col = hexc(roof) if roof else None
    if v == 0:   # stump with a mushroom cap
        stump(d, cx, base, 26, 22)
        door(d, cx - 3, base)
        window(d, cx + 7, base - 14)
        cap_roof(d, cx, base - 20, 40, 18, col or CAP)
    elif v == 1:   # stump with a leaf cone
        stump(d, cx, base, 24, 24)
        door(d, cx + 2, base)
        window(d, cx - 6, base - 15)
        leaf_roof(d, cx, base - 52, base - 20, 38, col or LEAF)
    elif v == 2:   # a two-storey stump: leaf cone with a small cap window
        stump(d, cx, base, 28, 30)
        door(d, cx - 4, base)
        window(d, cx + 7, base - 12)
        window(d, cx - 4, base - 23, 2.2)
        leaf_roof(d, cx, base - 60, base - 27, 40, col or LEAF)
    elif v == 3:   # mushroom cap with a stone chimney
        chimney(d, cx + 10, base - 30, 16)
        stump(d, cx, base, 24, 20)
        door(d, cx, base)
        cap_roof(d, cx, base - 18, 36, 16, col or (214, 160, 92, 255), dots=False)
        window(d, cx - 8, base - 9, 2.0)
    elif v == 4:   # a wide stump, leaf roof, a lantern by the door
        stump(d, cx, base, 32, 20)
        door(d, cx - 6, base)
        window(d, cx + 8, base - 12)
        leaf_roof(d, cx, base - 46, base - 18, 44, col or LEAF)
        lantern(d, cx + 1, base - 14)
    else:   # a tall thin stump with a small cap and vines
        stump(d, cx, base, 20, 30)
        door(d, cx, base, 7, 10)
        window(d, cx, base - 20, 2.2)
        cap_roof(d, cx, base - 28, 32, 15, col or CAP)
        for k in range(4):   # vines
            y = base - 24 + k * 5
            d.arc([P(cx - 11, y - 2), P(cx - 5, y + 2)], 0, 180, fill=(60, 130, 60, 255), width=int(K * 1.0))
    return im.resize((W, H), Image.LANCZOS)


def main():
    path = "assets/art/houses/wood/"
    man = json.load(open(path + "manifest.json"))
    for v in range(6):
        for roof in [None] + ROOFS:
            name = "house_v%d%s.png" % (v, "" if roof is None else "_r" + roof)
            house(v, roof).save(path + name)
            man["images"][name] = {"w": W, "h": H, "ax": AX, "ay": AY, "scale": 3, "variant": v, "roof": roof}
    man["note"] = man["note"] + " Woodling houses: tools/make_wood_houses.py (0.18)." if "make_wood_houses" not in man["note"] else man["note"]
    json.dump(man, open(path + "manifest.json", "w"), indent=2)
    print("wrote 54 Woodling houses")


if __name__ == "__main__":
    main()
