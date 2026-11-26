"""The Woodlings' houses (0.19.1): the web game's isometric tree houses (woodbld.js treeHouse, as content.js
houseSprite draws them), with their leafy crowns in the owner's colors so they stand out from the forest's trees:
two of every building's three homes wear the nation's main color (crown and door), the third its accent color
(the crown; a plain wood door). Six looks; each plain, in the 8 nation colors, and in the 48 accent colors.

Runs the web code itself in Node (tools/record_wood_houses.js records every canvas call) and draws the calls with
tools/canvas_replay.py. Writes assets/art/houses/wood/house_v<k>.png, house_v<k>_r<hex>.png (main color) and
house_v<k>_a<hex>.png (accent), and their manifest.
Run from the repository root: python3 tools/make_wood_houses.py
"""
import glob
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from canvas_replay import replay  # noqa: E402
from PIL import Image  # noqa: E402

OUT = 'assets/art/houses/wood'
WEB = 'reference/web-v106'
LOOKS = 6
SS = 8                    # drawn 8x larger, then shrunk, for smooth edges
PX = 1.2                  # image pixels per sprite unit: HOUSE_K 0.4 x 3 pixels to a map unit, like the other houses
AX, AY = 50 * PX, 70 * PX  # the sprite's origin (content.js houseSprite: translate(50, 70))


def main():
    mains = [c[0].lower() for c in json.load(open('data/web/features.json'))['NATION_COLORS']]
    rows = re.search(r'const EMBLEM_COLORS := \[(.*?)\n\]', open('scripts/sim/races.gd').read(), re.S).group(1)
    accents = sorted(set(c.lower() for c in re.findall(r'"(#[0-9a-fA-F]{6})"', rows)))
    jobs, names = [], []
    for v in range(LOOKS):
        jobs.append([v, None, None])
        names.append((f'house_v{v}.png', {'variant': v, 'roof': None}))
        for c in mains:
            jobs.append([v, c, None])
            names.append((f'house_v{v}_r{c[1:]}.png', {'variant': v, 'roof': c}))
        for c in accents:
            jobs.append([v, None, c])
            names.append((f'house_v{v}_a{c[1:]}.png', {'variant': v, 'accent': c}))
    rec = '/tmp/wood_houses_cmds.json'
    subprocess.run(['node', 'tools/record_wood_houses.js', WEB, rec, json.dumps(jobs)], check=True)
    cmds = json.load(open(rec))
    for f in glob.glob(os.path.join(OUT, 'house_v*.png')):   # (the 0.18 cottages and their .import files)
        os.remove(f)
        if os.path.exists(f + '.import'):
            os.remove(f + '.import')
    images = {}
    n = int(100 * PX)
    for (name, meta), cl in zip(names, cmds):
        big = replay(cl, n * SS, n * SS, (PX / 4 * SS, 0, 0, PX / 4 * SS, 0, 0))
        im = big.convert('RGBa').resize((n, n), Image.LANCZOS).convert('RGBA')
        x0, y0, x1, y1 = im.getbbox()
        x0, y0, x1, y1 = max(0, x0 - 1), max(0, y0 - 1), min(n, x1 + 1), min(n, y1 + 1)
        im = im.crop((x0, y0, x1, y1))
        im.save(os.path.join(OUT, name))
        images[name] = {'w': im.width, 'h': im.height, 'ax': round(AX - x0), 'ay': round(AY - y0), 'scale': 3, **meta}
    mf = os.path.join(OUT, 'manifest.json')
    note = json.load(open(mf)).get('note', '') if os.path.exists(mf) else ''
    with open(mf, 'w') as f:
        json.dump({'note': note or 'ax, ay: the anchor pixel. scale: image pixels per world unit.', 'images': dict(sorted(images.items()))}, f, indent=1)
    print(len(images), 'Woodling houses')


if __name__ == '__main__':
    main()
