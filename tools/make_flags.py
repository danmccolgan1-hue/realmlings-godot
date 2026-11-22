"""Render the nation flags (each nation color with each emblem) for the Godot port.

The four emblems kept from the web game (eagle, crown, swords, shield: features.js flagSVG) and the races' own new
emblems are SVG in tools/flag_emblems.json, drawn in the web game's flag style (48 x 34, parchment emblem with an
ink outline). Writes assets/art/flags/nations/flag_<color>_<emblem>.png (192 x 136) and its manifest.json.

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


def svg(color, em):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 34" width="192" height="136"><rect x="1.5" y="1.5" width="45" height="31" rx="3" fill="%s" '
            'stroke="#1d1a22" stroke-width="3"/><rect x="4" y="4" width="40" height="3" fill="#000" opacity=".15"/><g fill="#faf1dc" stroke="#1d1a22" '
            'stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round">%s</g></svg>') % (color, EMB[em])


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
        if SHEET:   # a contact sheet of every emblem on blue, for checking the drawings
            cells = ''.join('<div style="display:inline-block;text-align:center;margin:6px;font:12px sans-serif">%s<br>%s</div>' % (svg('#2f6fe0', k), k) for k in EMB)
            await pg.set_content('<body style="background:#f3ead4;width:1100px">' + cells + '</body>')
            await pg.screenshot(path=SHEET, full_page=True)
        else:
            items = [[c.lstrip('#') + '_' + em, svg(c, em)] for c in COLORS for em in EMB]
            imgs = await pg.evaluate(JS, items)
            d = os.path.join(OUT, 'flags', 'nations')
            for f in glob.glob(os.path.join(d, 'flag_*.png*')):
                os.remove(f)
            man = {}
            for k, uri in sorted(imgs.items()):
                with open(os.path.join(d, 'flag_%s.png' % k), 'wb') as fh:
                    fh.write(base64.b64decode(uri.split(',', 1)[1]))
                man['flag_%s.png' % k] = {'ax': 0, 'ay': 0, 'scale': 1}
            json.dump({'images': man}, open(os.path.join(d, 'manifest.json'), 'w'), indent=1)
            print(len(man), 'nation flags')
        await b.close()

asyncio.run(main())
