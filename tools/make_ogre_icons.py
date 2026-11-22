"""The Swamplings' Swift Ogres and Hardy Ogres technology icons: an Ogre's head (web: techicons.js ogreIcon) with
speed lines, or with a heart, in the way the Woodlings' Champion Swiftness / Toughness icons are made (wood.js).
The web game drew a horse for both; asked for in 0.17. Writes assets/art/icons/swamp/tech_rep_horsespeed.png and
tech_rep_cavhp.png (64 x 64, like the other tech icons). Run from the repository root: python3 tools/make_ogre_icons.py
"""
from PIL import Image, ImageDraw

OL = (29, 26, 34, 255)
K = 8          # drawn 8x larger, then shrunk, for smooth edges
SIZE = 64


def s(v):
    return v * K


def ogre_head(d: ImageDraw.ImageDraw, skin, cx=24.0, cy=33.0, k=0.78):
    """web: techicons.js ogreIcon, centered at (cx, cy) and scaled by k (its own drawing is 64 wide around 32, 32)."""
    def p(x, y):
        return (s(cx + (x - 32) * k), s(cy + (y - 32) * k))
    lw = int(s(3 * k))
    # ears
    for sg in (-1, 1):
        d.polygon([p(32 + sg * 18, 26), p(32 + sg * 30, 20), p(32 + sg * 18, 34)], fill=skin, outline=OL, width=lw)
    # the head
    x0, y0 = p(12, 12)
    x1, y1 = p(52, 48)
    d.ellipse([x0, y0, x1, y1], fill=skin, outline=OL, width=lw)
    # the jaw: a wide curve under the head
    jaw = []
    for i in range(21):
        t = i / 20
        x = 16 + 32 * t
        jaw.append(p(x, 38 + 18 * (1 - (2 * t - 1) ** 2)))
    for i in range(20, -1, -1):
        t = i / 20
        x = 16 + 32 * t
        jaw.append(p(x, 38 + 6 * (1 - (2 * t - 1) ** 2)))
    d.polygon(jaw, fill=skin, outline=OL, width=lw)
    # tusks
    for x in (25, 39):
        d.polygon([p(x - 3, 42), p(x, 32), p(x + 3, 42)], fill=(246, 239, 216, 255), outline=OL, width=max(1, int(s(1.8 * k))))
    # glowing red eyes
    for x in (25, 39):
        ex, ey = p(x, 27)
        r = s(3.2 * k)
        d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=(255, 59, 47, 255))


def heart(d, cx, cy, r):
    pts = []
    import math
    for i in range(60):
        t = math.pi * 2 * i / 60
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((s(cx + x * r / 16), s(cy + y * r / 16)))
    d.polygon(pts, fill=(224, 82, 106, 255), outline=OL, width=int(s(1.6)))


def make(kind: str, path: str):
    im = Image.new("RGBA", (s(SIZE), s(SIZE)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if kind == "swift":
        ogre_head(d, (147, 181, 92, 255))   # Swampfeet Ogre's skin
        for y in (24, 34, 44):   # speed lines, as on Champion Swiftness
            d.line([(s(51), s(y)), (s(62), s(y))], fill=OL, width=int(s(4.2)))
            d.line([(s(51), s(y)), (s(62), s(y))], fill=(111, 211, 234, 255), width=int(s(2.6)))
    else:
        ogre_head(d, (90, 122, 128, 255))   # Leviathan Ogre's skin
        heart(d, 53, 47, 9)
    im = im.resize((SIZE, SIZE), Image.LANCZOS)
    im.save(path)
    print("wrote", path)


if __name__ == "__main__":
    make("swift", "assets/art/icons/swamp/tech_rep_horsespeed.png")
    make("hardy", "assets/art/icons/swamp/tech_rep_cavhp.png")
