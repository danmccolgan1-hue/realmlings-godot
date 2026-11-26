#!/usr/bin/env python3
"""Placeholder art for the quests (Godot only, docs/QUESTS_PLAN.md): the three races' Reliquaries with their rising
frames, their build icons, and an icon for every relic in data/quests.json. Drawn in the game's flat style (dark
outline, isometric ground tile) so it sits with the exported art until a real art pass replaces it.

    python3 tools/make_quest_art.py [repo root]

Writes into assets/art/ and adds the buildings to each race's manifest.json (anchor and scale like the Bank's)."""
import json, math, os, sys
from PIL import Image, ImageDraw

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..")
ART = os.path.join(ROOT, "assets", "art")
OL = (29, 26, 34, 255)
SS = 4  # supersampling


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (c[3],)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.im = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def P(self, pts):
        return [(x * SS, y * SS) for x, y in pts]

    def poly(self, pts, fill, ol=OL, w=2.4):
        self.d.polygon(self.P(pts), fill=fill)
        if ol is not None:
            self.d.line(self.P(pts + [pts[0]]), fill=ol, width=int(w * SS), joint="curve")

    def line(self, pts, col=OL, w=2.4):
        self.d.line(self.P(pts), fill=col, width=int(w * SS), joint="curve")

    def ell(self, cx, cy, rx, ry, fill, ol=OL, w=2.4):
        self.d.ellipse([(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=fill,
                       outline=ol, width=int(w * SS) if ol else 0)

    def save(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.im.resize((self.w, self.h), Image.LANCZOS).save(path)


# --- isometric helpers: x right, y down; a box on the ground at (cx, cy) with half-width a, half-depth a/2 ---

def tile(cv, cx, cy, a, col):
    cv.poly([(cx, cy - a / 2), (cx + a, cy), (cx, cy + a / 2), (cx - a, cy)], col)


def box(cv, cx, cy, a, h, col, top=True):
    """An iso box whose ground diamond has half-width a; h tall. Returns the top diamond's points."""
    b = a / 2
    left = [(cx - a, cy), (cx, cy + b), (cx, cy + b - h), (cx - a, cy - h)]
    right = [(cx, cy + b), (cx + a, cy), (cx + a, cy - h), (cx, cy + b - h)]
    cv.poly(left, shade(col, 0.86))
    cv.poly(right, shade(col, 0.70))
    topd = [(cx, cy - b - h), (cx + a, cy - h), (cx, cy + b - h), (cx - a, cy - h)]
    if top:
        cv.poly(topd, col)
    return topd


W, H, AX, AY = 200, 132, 100, 80


def reliquary_realm(f):
    """An ornate vault: pale stone, gold trim, a gilded dome and an arched iron door."""
    cv = Canvas(W, H)
    tile(cv, AX, AY, 92, hexc("#e8cf95"))
    hh = 38 * min(1.0, f / 0.75)
    if f <= 0.3:
        box(cv, AX, AY - 2, 52, 10, hexc("#d9d4c8"))
        return cv
    box(cv, AX, AY - 2, 56, 6, hexc("#c9c3b4"))  # plinth
    box(cv, AX, AY - 8, 50, hh, hexc("#ece7dc"))
    if f < 0.75:
        for x in (-46, 46):  # scaffold poles
            cv.line([(AX + x, AY - 4), (AX + x, AY - 60)], hexc("#8a5a34"), 3)
        return cv
    top = AY - 8 - hh
    # gold cornice band
    cv.line([(AX - 50, top + 6), (AX, top + 31), (AX + 50, top + 6)], hexc("#f4c44f"), 5)
    cv.line([(AX - 50, top + 6), (AX, top + 31), (AX + 50, top + 6)], OL, 1.4)
    # the arched door on the right face, iron with gold studs
    dx, dy = AX + 24, AY - 2
    door = [(dx - 10, dy + 4), (dx - 10, dy - 18), (dx - 5, dy - 25), (dx + 3, dy - 27), (dx + 10, dy - 22), (dx + 10, dy - 6)]
    cv.poly(door, hexc("#4a4f5a"))
    for sx, sy in ((dx - 4, dy - 6), (dx + 4, dy - 10), (dx - 4, dy - 16), (dx + 4, dy - 20)):
        cv.ell(sx, sy, 1.6, 1.6, hexc("#f4c44f"), OL, 0.8)
    # pillars on the left face
    for i, px in enumerate((-40, -24)):
        y0 = AY - 8 + (px + 50) * 0.5 - 25 * 0
        cv.poly([(AX + px - 3, AY - 8 + (50 + px) / 2 - 2), (AX + px + 3, AY - 8 + (50 + px) / 2 + 1),
                 (AX + px + 3, top + (50 + px) / 2 + 9), (AX + px - 3, top + (50 + px) / 2 + 6)], hexc("#f7f3ea"), OL, 1.6)
    # the gilded dome and its finial
    cv.ell(AX, top + 2, 30, 16, hexc("#f4c44f"))
    cv.d.pieslice([(AX - 30) * SS, (top - 26) * SS, (AX + 30) * SS, (top + 18) * SS], 180, 360, fill=hexc("#f4c44f"), outline=OL, width=int(2.4 * SS))
    cv.d.arc([(AX - 18) * SS, (top - 18) * SS, (AX + 6) * SS, (top + 8) * SS], 200, 260, fill=hexc("#fff3b8"), width=int(3 * SS))
    cv.line([(AX, top - 4), (AX, top - 16)], OL, 2.4)
    cv.ell(AX, top - 19, 4, 4, hexc("#ffd34d"))
    return cv


def reliquary_swamp(f):
    """A spiky bunker: a low mound of dark timber and mud, ringed with sharpened stakes, a slit of a door."""
    cv = Canvas(W, H)
    tile(cv, AX, AY, 92, hexc("#a8a070"))
    hh = 30 * min(1.0, f / 0.75)
    if f <= 0.3:
        box(cv, AX, AY - 2, 54, 8, hexc("#5f5238"))
        return cv
    topd = box(cv, AX, AY - 2, 54, hh, hexc("#5f5238"))
    top = AY - 2 - hh
    # the mud roof mound
    cv.ell(AX, top + 2, 46, 20, hexc("#6d7a3a"))
    if f < 0.75:
        return cv
    cv.ell(AX - 8, top - 2, 26, 9, hexc("#7f8c46"), None)
    # stakes all round the roof's edge, leaning out
    for i in range(13):
        a = math.pi * (0.06 + i / 12 * 0.88)
        bx = AX + math.cos(a) * 44
        by = top + 2 + math.sin(a) * 18 - 22
        bx2 = AX + math.cos(math.pi + a) * 44
        for (x, y, s) in ((bx, by + 22, 1), (bx2, top + 2 - math.sin(a) * 18, -1)):
            tip = (x + (x - AX) * 0.18, y - 20)
            cv.poly([(x - 3.2, y), (x + 3.2, y), tip], hexc("#c9b38a"), OL, 1.6)
    # a narrow door with a bone over it
    dx, dy = AX + 22, AY - 1
    cv.poly([(dx - 7, dy + 3), (dx - 7, dy - 16), (dx + 7, dy - 19), (dx + 7, dy)], hexc("#1d1a22"))
    cv.line([(dx - 10, dy - 22), (dx + 10, dy - 25)], hexc("#efe6cf"), 3.4)
    return cv


def reliquary_wood(f):
    """A fancy treehouse: a thick trunk, a railed platform and a little round-roofed house under a leafy crown."""
    cv = Canvas(W, H)
    tile(cv, AX, AY, 92, hexc("#b5d98a"))
    th = 30 * min(1.0, f / 0.75)
    # the trunk with roots
    cv.poly([(AX - 14, AY + 4), (AX - 9, AY - th), (AX + 9, AY - th), (AX + 14, AY + 4), (AX + 4, AY + 7), (AX - 4, AY + 7)], hexc("#8a5a34"))
    for rx in (-22, 20):
        cv.poly([(AX + rx * 0.4, AY), (AX + rx, AY + 6), (AX + rx * 0.5, AY + 4)], hexc("#7a4e2c"), OL, 1.6)
    if f <= 0.3:
        return cv
    py = AY - th
    # the platform
    box(cv, AX, py + 4, 44, 6, hexc("#b07a40"))
    if f < 0.75:
        return cv
    # the little house on it
    hy = py - 2
    box(cv, AX - 4, hy, 24, 22, hexc("#e8c58a"))
    cv.poly([(AX - 32, hy - 20), (AX - 4, hy - 46), (AX + 24, hy - 20), (AX - 4, hy - 8)], hexc("#4b9b4f"))
    cv.ell(AX + 6, hy - 10, 4, 6, hexc("#3a2a20"), OL, 1.6)  # round door
    # the leafy boughs either side of the house
    for (cx, cy, r) in ((AX - 36, hy - 26, 13), (AX + 30, hy - 30, 14)):
        cv.ell(cx, cy, r, r * 0.8, hexc("#5fb04a"))
        cv.ell(cx - 3, cy - 4, r * 0.45, r * 0.25, hexc("#8ccf6a"), None)
    # a gem-like lantern: it keeps relics
    cv.ell(AX + 26, py - 4, 4, 5, hexc("#ffd34d"), OL, 1.4)
    return cv


DRAW = {"realm": reliquary_realm, "swamp": reliquary_swamp, "wood": reliquary_wood}


def buildings():
    for race, fn in DRAW.items():
        d = os.path.join(ART, "buildings", race)
        man_path = os.path.join(d, "manifest.json")
        man = json.load(open(man_path, encoding="utf-8"))
        for suffix, f in (("", 1.0), ("_rise25", 0.25), ("_rise50", 0.5), ("_rise75", 0.75)):
            name = "reliquary_v0%s.png" % suffix
            fn(f).save(os.path.join(d, name))
            e = {"w": W, "h": H, "ax": AX, "ay": AY, "scale": 3, "type": "reliquary", "variant": "v0"}
            if suffix:
                e["rise"] = f
            man["images"][name] = e
        json.dump(man, open(man_path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
        # the build icon (84 px): the finished building, cropped and scaled
        full = fn(1.0)
        im = full.im.resize((W, H), Image.LANCZOS)
        bb = im.getbbox()
        crop = im.crop(bb)
        s = 76 / max(crop.size)
        crop = crop.resize((max(1, int(crop.size[0] * s)), max(1, int(crop.size[1] * s))), Image.LANCZOS)
        ic = Image.new("RGBA", (84, 84), (0, 0, 0, 0))
        ic.paste(crop, ((84 - crop.size[0]) // 2, (84 - crop.size[1]) // 2), crop)
        os.makedirs(os.path.join(ART, "icons", race), exist_ok=True)
        ic.save(os.path.join(ART, "icons", race, "build_reliquary.png"))
        if race == "realm":
            ic.save(os.path.join(ART, "icons", "common", "cmd_build_reliquary.png"))


# --- relic icons (84 px), one per item, from its "look" in data/quests.json ---

RAINBOW = ["#e0533f", "#f08a3c", "#f4d35e", "#5fb04a", "#4a8fe0", "#8a5ad0"]


def icon(look):
    cv = Canvas(84, 84)
    sh, c = look["shape"], look.get("c", "#888888")
    col = hexc(c) if c.startswith("#") else hexc("#5fb04a")
    if sh == "book":
        cv.poly([(18, 26), (56, 18), (68, 60), (30, 68)], col)
        cv.poly([(30, 68), (68, 60), (68, 64), (30, 72)], hexc("#f3ecd8"))
        cv.poly([(18, 26), (30, 68), (30, 72), (18, 30)], shade(col, 0.7))
        cv.poly([(34, 40), (62, 34), (64, 42), (36, 48)], hexc("#7a4a26"), OL, 1.8)  # the buckle strap
        cv.poly([(46, 37), (52, 36), (53, 42), (47, 43)], hexc("#e8c547"), OL, 1.4)
    elif sh == "ring":
        cv.ell(42, 50, 24, 22, None, OL, 11)
        cv.ell(42, 50, 24, 22, None, col, 7)
        cv.poly([(32, 26), (42, 14), (52, 26), (42, 34)], hexc(look["gem"]))
        cv.line([(36, 24), (42, 18)], (255, 255, 255, 200), 2)
    elif sh == "herb":
        cols = RAINBOW if c == "rainbow" else [c]
        for i, a in enumerate((-50, -25, 0, 25, 50)):
            r = math.radians(a - 90)
            tip = (42 + math.cos(r) * 32, 46 + math.sin(r) * 32)
            mid = (42 + math.cos(r) * 16, 46 + math.sin(r) * 16)
            n = (math.cos(r + 1.57) * 8, math.sin(r + 1.57) * 8)
            cv.poly([(42, 50), (mid[0] + n[0], mid[1] + n[1]), tip, (mid[0] - n[0], mid[1] - n[1])], hexc(cols[i % len(cols)]))
        w = hexc(look.get("w", "#4b9b4f"))
        for x in (34, 42, 50):
            cv.line([(42, 74), (x, 50)], OL, 5)
            cv.line([(42, 74), (x, 50)], w, 3)
        cv.poly([(34, 58), (50, 58), (48, 64), (36, 64)], hexc("#c9b38a"), OL, 1.6)
    elif sh == "bones":
        for a in (40, -40):
            r = math.radians(a)
            dx, dy = math.cos(r) * 24, math.sin(r) * 24
            cv.line([(42 - dx, 42 - dy), (42 + dx, 42 + dy)], OL, 10)
            cv.line([(42 - dx, 42 - dy), (42 + dx, 42 + dy)], hexc("#efe6cf"), 6)
            for s in (-1, 1):
                for k in (-1, 1):
                    cv.ell(42 + s * dx + k * dy * 0.18, 42 + s * dy - k * dx * 0.18, 5, 5, hexc("#efe6cf"), OL, 1.8)
        cv.ell(42, 42, 34, 34, None, col[:3] + (120,), 3)
    elif sh == "ribcage":
        cv.line([(42, 14), (42, 72)], OL, 8)
        cv.line([(42, 14), (42, 72)], hexc("#efe6cf"), 4)
        for i in range(5):
            y = 22 + i * 10
            for s in (-1, 1):
                pts = [(42, y), (42 + s * 20, y + 2), (42 + s * 24, y + 10)]
                cv.line(pts, OL, 6)
                cv.line(pts, hexc("#efe6cf"), 3)
        cv.ell(42, 42, 36, 36, None, col[:3] + (120,), 3)
    elif sh == "skull":
        cv.ell(42, 36, 22, 20, hexc("#efe6cf"))
        cv.poly([(28, 46), (56, 46), (52, 64), (32, 64)], hexc("#efe6cf"))
        cv.ell(34, 38, 6, 7, col)
        cv.ell(50, 38, 6, 7, col)
        cv.poly([(42, 46), (38, 54), (46, 54)], OL, None)
        for x in (36, 42, 48):
            cv.line([(x, 58), (x, 64)], OL, 1.6)
    elif sh in ("ingot", "gauntlet", "helm", "breastplate"):
        g = hexc(look.get("glow", "#ff8a2a"))
        if sh == "ingot":
            cv.poly([(14, 52), (30, 34), (70, 34), (56, 52)], col)
            cv.poly([(14, 52), (56, 52), (56, 62), (14, 62)], shade(col, 0.8))
            cv.poly([(56, 52), (70, 34), (70, 44), (56, 62)], shade(col, 0.6))
            cv.line([(26, 44), (36, 40), (42, 46), (54, 40)], g, 3)
        elif sh == "gauntlet":
            cv.poly([(26, 70), (26, 40), (22, 30), (30, 20), (38, 26), (44, 16), (52, 22), (56, 30), (62, 28), (62, 44), (56, 70)], col)
            cv.line([(30, 56), (52, 56)], g, 3)
            cv.line([(32, 44), (40, 36), (48, 42)], g, 3)
        elif sh == "helm":
            cv.poly([(22, 66), (20, 40), (30, 24), (54, 24), (64, 40), (62, 66), (48, 66), (48, 46), (36, 46), (36, 66)], col)
            cv.poly([(22, 30), (8, 16), (16, 34)], hexc("#efe6cf"))
            cv.poly([(62, 30), (76, 16), (68, 34)], hexc("#efe6cf"))
            cv.line([(28, 36), (42, 32), (56, 36)], g, 3)
        else:
            cv.poly([(18, 24), (34, 18), (42, 24), (50, 18), (66, 24), (62, 50), (52, 70), (32, 70), (22, 50)], col)
            cv.line([(42, 28), (42, 64)], g, 3)
            cv.line([(30, 40), (54, 40)], g, 3)
    elif sh == "scraps":
        for (x, y, a) in ((28, 34, 0), (52, 38, 1), (38, 56, 2)):
            cv.poly([(x - 14, y - 6), (x + 2, y - 12), (x + 14, y - 2), (x + 8, y + 10), (x - 10, y + 8)], shade(col, 1 - a * 0.1))
            cv.line([(x - 6, y), (x + 6, y - 2)], OL, 1.4)
    elif sh == "hide":
        cv.poly([(14, 30), (30, 18), (54, 20), (70, 32), (66, 58), (50, 68), (28, 66), (16, 52)], col)
        cv.line([(24, 38), (60, 38)], shade(col, 0.6), 2)
        cv.line([(24, 50), (60, 50)], shade(col, 0.6), 2)
    elif sh == "scroll":
        edge = col
        cv.poly([(18, 22), (66, 22), (66, 62), (18, 62)], hexc("#f3ecd8"), edge, 5)
        cv.poly([(18, 22), (66, 22), (66, 62), (18, 62)], None, OL, 1.6)
        cv.ell(18, 42, 6, 22, hexc("#e3d6b4"))
        cv.ell(66, 42, 6, 22, hexc("#e3d6b4"))
        for y in (32, 40, 48):
            cv.line([(28, y), (56, y)], hexc("#8a7a5a"), 1.6)
        if c == "#3a2a20":
            for (x, y) in ((26, 22), (48, 62), (62, 30)):
                cv.ell(x, y, 4, 3, hexc("#1d1a22"), None)
    elif sh == "belt":
        cv.ell(42, 46, 28, 18, None, OL, 12)
        cv.ell(42, 46, 28, 18, None, col, 8)
        cv.poly([(32, 56), (52, 56), (52, 70), (32, 70)], hexc("#c9ced6") if c != "#4aa8ff" else hexc("#a8e6ff"))
        cv.line([(42, 58), (42, 68)], OL, 2)
    elif sh == "hilt":
        cv.poly([(14, 34), (70, 34), (66, 42), (18, 42)], col)
        cv.poly([(36, 42), (48, 42), (46, 70), (38, 70)], hexc("#7a4a26"))
        cv.ell(42, 74, 6, 5, col)
        cv.ell(42, 38, 4, 3, hexc("#d23b5b"), OL, 1.2)
    elif sh == "shaft":
        cv.poly([(56, 10), (64, 14), (28, 76), (20, 72)], col)
        for k in (0.3, 0.6):
            x, y = 60 - 36 * k, 12 + 62 * k
            cv.line([(x - 6, y - 2), (x + 6, y + 3)], OL, 2)
    elif sh == "orb":
        cv.ell(42, 44, 26, 26, col)
        cv.ell(34, 36, 8, 6, (255, 255, 255, 220), None)
        cv.ell(42, 44, 14, 14, None, (255, 255, 255, 110), 2)
    elif sh == "map":
        pts = [(16, 20), (40, 16), (46, 26), (68, 22), (66, 46), (70, 66), (44, 68), (38, 60), (18, 64), (22, 42)]
        cv.poly(pts, col)
        cv.line([(26, 30), (34, 40), (46, 42), (56, 54)], hexc("#c8473d"), 2)
        cv.line([(52, 50), (60, 58)], hexc("#c8473d"), 3)
        cv.line([(60, 50), (52, 58)], hexc("#c8473d"), 3)
    elif sh == "cutlass":
        cv.poly([(22, 70), (28, 64), (60, 20), (70, 14), (66, 26), (34, 70)], col)
        cv.poly([(16, 60), (34, 76), (30, 80), (12, 64)], hexc("#f4c44f"))
        cv.line([(18, 78), (24, 72)], hexc("#7a4a26"), 6)
    elif sh == "axe":
        cv.poly([(24, 78), (54, 14), (60, 16), (30, 80)], hexc("#7a4a26"))
        for y in (40, 56):
            cv.line([(34, y + 6), (44, y + 10)], hexc("#f4c44f"), 2)
        cv.poly([(44, 18), (70, 8), (76, 34), (52, 38)], col)
        cv.poly([(50, 20), (34, 14), (30, 28), (46, 32)], shade(col, 0.85))
    elif sh == "maul":
        cv.poly([(38, 80), (40, 34), (46, 34), (44, 80)], hexc("#7a4a26"))
        cv.poly([(20, 14), (64, 14), (66, 40), (18, 40)], col)
        cv.ell(42, 27, 7, 7, hexc("#efe6cf"))
        cv.ell(39, 26, 1.6, 1.6, OL, None)
        cv.ell(45, 26, 1.6, 1.6, OL, None)
    elif sh == "shield":
        cv.poly([(18, 16), (66, 12), (70, 46), (44, 76), (16, 50)], col)
        for x in (28, 40, 52):
            cv.line([(x, 14), (x - 2, 66)], shade(col, 0.7), 3)
        cv.line([(16, 34), (68, 30)], hexc("#c9b38a"), 4)
        cv.line([(26, 52), (34, 48), (40, 54), (50, 46)], hexc("#a8e6ff"), 2)
    elif sh == "star":
        pts = []
        for i in range(14):
            r = 30 if i % 2 == 0 else 13
            a = math.pi * 2 * i / 14 - math.pi / 2
            pts.append((46 + math.cos(a) * r, 40 + math.sin(a) * r))
        for k in range(3):
            cv.line([(30 - k * 6, 60 + k * 4), (12 - k * 4, 76 + k * 2)], (230, 234, 240, 160 - k * 40), 3)
        cv.poly(pts, col)
        cv.ell(40, 34, 4, 3, (255, 255, 255, 230), None)
    return cv


def items():
    data = json.load(open(os.path.join(ROOT, "data", "quests.json"), encoding="utf-8"))
    for id, it in data["ITEMS"].items():
        icon(it["look"]).save(os.path.join(ART, "icons", "common", "item_%s.png" % id))


# --- the Mason card's page buttons (Godot 0.19): Advanced Buildings and Back ---

def card_icons():
    cv = Canvas(84, 84)  # a tall tower with a scroll of plans: the buildings research unlocks
    box(cv, 36, 66, 20, 34, hexc("#d9d4c8"))
    cv.poly([(16, 32), (36, 12), (56, 32), (36, 42)], hexc("#c8473d"))
    cv.ell(36, 22, 3, 3, hexc("#ffd34d"), OL, 1.2)
    cv.poly([(50, 50), (74, 44), (76, 70), (52, 76)], hexc("#f3ecd8"))
    for y in (54, 60, 66):
        cv.line([(56, y), (70, y - 4)], hexc("#4a8fe0"), 2)
    cv.poly([(60, 6), (70, 18), (64, 18), (64, 30), (56, 30), (56, 18), (50, 18)], hexc("#5fb04a"), OL, 2)
    cv.save(os.path.join(ART, "icons", "common", "cmd_advanced.png"))
    cv = Canvas(84, 84)  # a curved arrow back
    cv.d.arc([18 * SS, 20 * SS, 70 * SS, 70 * SS], 200, 70, fill=OL, width=12 * SS)
    cv.d.arc([18 * SS, 20 * SS, 70 * SS, 70 * SS], 200, 70, fill=hexc("#e8c547"), width=6 * SS)
    cv.poly([(8, 40), (30, 22), (32, 52)], hexc("#e8c547"))
    cv.save(os.path.join(ART, "icons", "common", "cmd_basic.png"))
    cv = Canvas(84, 84)  # Dig: a spade in a mound of earth, a red X beside it
    cv.ell(42, 66, 32, 12, hexc("#8a5a34"))
    for s_ in (-1, 1):
        cv.poly([(14, 56 + 6 * s_), (17, 53 + 6 * s_), (34, 62 - 6 * s_), (31, 65 - 6 * s_)], hexc("#d23b3b"), OL, 1.6)
    cv.poly([(50, 6), (58, 8), (50, 44), (44, 42)], hexc("#a0703c"))
    cv.poly([(40, 40), (56, 44), (54, 66), (44, 70), (36, 62)], hexc("#c9ced6"))
    cv.poly([(46, 4), (60, 7), (58, 12), (46, 9)], hexc("#7a4a26"), OL, 1.6)
    cv.save(os.path.join(ART, "icons", "common", "cmd_dig.png"))
    cv = Canvas(84, 84)  # the Quest Log: an unrolled scroll with a red seal and a quill
    cv.poly([(16, 14), (62, 14), (62, 70), (16, 70)], hexc("#f3ecd8"))
    cv.ell(16, 42, 6, 28, hexc("#e3d6b4"))
    cv.ell(62, 42, 6, 28, hexc("#e3d6b4"))
    for y in (26, 34, 42, 50):
        cv.line([(24, y), (54, y)], hexc("#8a7a5a"), 1.8)
    cv.ell(44, 60, 7, 7, hexc("#c8473d"))
    cv.poly([(76, 6), (80, 10), (52, 52), (48, 52), (48, 48)], hexc("#efe6cf"))
    cv.line([(50, 50), (44, 60)], OL, 2)
    cv.save(os.path.join(ART, "icons", "common", "ui_quests.png"))


if __name__ == "__main__":
    buildings()
    items()
    card_icons()
    print("quest art written to", ART)
