"""Render the nation flags' parts for the Godot port, which puts each flag together in the game
(scripts/view/art.gd Art.flag_texture): the cloth in each nation color, and each emblem twice, once filled black
and once filled white, so the game can fill it with any emblem color (fill = black + (white - black) * color).

The four emblems kept from the web game (eagle, crown, swords, shield: features.js flagSVG) and the races' own
emblems are SVG in tools/flag_emblems.json, drawn in the web game's flag style (48 x 34, emblem with an ink outline).
Writes assets/art/flags/nations/cloth_<color>.png, emblem_<name>_k.png, emblem_<name>_w.png (192 x 136) and manifest.json.

Usage: python3 tools/make_flags.py <repo>/assets/art [--sheet=/tmp/emblems.png]
"""
import asyncio, base64, json, os, sys, glob
from playwright.async_api import async_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith('--') else 'assets/art'
SHEET = ([a[8:] for a in sys.argv if a.startswith('--sheet=')] or [None])[0]
EMB = json.load(open(os.path.join(HERE, 'flag_emblems.json')))
DATA = {}
for f in glob.glob(os.path.join(HERE, '..', 'data', 'web', '*.json')):
    DATA.update(json.load(open(f)))
COLORS = sorted(set([c[0].lower() for c in DATA['NATION_COLORS']] + [p['color'].lower() for p in DATA['PLAYERS'].values()]))
SVG0 = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 34" width="192" height="136">%s</svg>'
CLOTH = ('<rect x="1.5" y="1.5" width="45" height="31" rx="3" fill="%s" stroke="#1d1a22" stroke-width="3"/>'
         '<rect x="4" y="4" width="40" height="3" fill="#000" opacity=".15"/>')


def emblem(em, fill):   # the parchment of the drawings becomes the fill color
    body = EMB[em].replace('#faf1dc', fill)
    return '<g fill="%s" stroke="#1d1a22" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round">%s</g>' % (fill, body)


JS = """async (items) => {
  const out = {};
  for (const [k, s] of items) {
    const img = new Image(); img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(s); await img.decode();
    const c = document.createElement('canvas'); c.width = 192; c.height = 136;
    c.getContext('2d').drawImage(img, 0, 0, 192, 136); out[k] = c.toDataURL('image/png');
  }
  return out;
}"""


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch()
        pg = await b.new_page()
        if SHEET:   # every emblem in a few emblem colors on a few cloths, for checking the drawings
            pairs = [('#2f6fe0', '#faf1dc'), ('#d23b3b', '#f4d35e'), ('#2f9e55', '#d7f5c8'), ('#4b4f5c', '#8cc4ff')]
            cells = ''
            for i, k in enumerate(EMB):
                cl, fi = pairs[i % len(pairs)]
                cells += '<div style="display:inline-block;text-align:center;margin:6px;font:12px sans-serif">%s<br>%s</div>' % (SVG0 % (CLOTH % cl + emblem(k, fi)), k)
            await pg.set_content('<body style="background:#f3ead4;width:1100px">' + cells + '</body>')
            await pg.screenshot(path=SHEET, full_page=True)
        else:
            items = [['cloth_' + c.lstrip('#'), SVG0 % (CLOTH % c)] for c in COLORS]
            for em in EMB:
                items.append(['emblem_%s_k' % em, SVG0 % emblem(em, '#000000')])
                items.append(['emblem_%s_w' % em, SVG0 % emblem(em, '#ffffff')])
            imgs = await pg.evaluate(JS, items)
            d = os.path.join(OUT, 'flags', 'nations')
            for f in glob.glob(os.path.join(d, '*.png*')):
                os.remove(f)
            man = {}
            for k, uri in sorted(imgs.items()):
                with open(os.path.join(d, k + '.png'), 'wb') as fh:
                    fh.write(base64.b64decode(uri.split(',', 1)[1]))
                man[k + '.png'] = {'ax': 0, 'ay': 0, 'scale': 1}
            json.dump({'images': man}, open(os.path.join(d, 'manifest.json'), 'w'), indent=1)
            print(len(man), 'flag parts')
        await b.close()

asyncio.run(main())
