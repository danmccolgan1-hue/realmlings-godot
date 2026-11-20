"""Render the web game's map decoration sprites (page.html SPR: trees, pines, cypresses, palms, mountains, ruins,
rocks, desert and swamp details, and their large `_L` copies for the border bands) to PNG files.

Usage (the web build served on localhost:8777, as for tools/export_art.py):
    python3 tools/export_map_sprites.py <repo>/assets/art

Writes assets/art/map/common/<name>.png and manifest.json (anchor ax / ay in image pixels, scale = pixels per world unit).
"""
import asyncio, base64, json, os, sys
from playwright.async_api import async_playwright

OUT = os.path.join(sys.argv[1] if len(sys.argv) > 1 else 'assets/art', 'map', 'common')
SCALE = 4

JS = r"""(() => {
  const K = %d, out = [];
  for (const [name, s] of Object.entries(SPR)) {
    const c = document.createElement('canvas');
    c.width = Math.ceil(s.w * K); c.height = Math.ceil(s.h * K);
    const g = c.getContext('2d'); g.scale(K, K); g.translate(s.ax, s.ay); s.fn(g);
    out.push({ name, w: c.width, h: c.height, ax: s.ax * K, ay: s.ay * K, data: c.toDataURL('image/png') });
  }
  return JSON.stringify(out);
})()"""


async def main():
    os.makedirs(OUT, exist_ok=True)
    async with async_playwright() as p:
        b = await p.chromium.launch()
        pg = await b.new_page()
        await pg.goto('http://localhost:8777/realmlings_play.html')
        await pg.wait_for_timeout(1500)
        items = json.loads(await pg.evaluate("s => window.__evalIn(s)", JS % SCALE))
        manifest = {}
        for it in items:
            f = it['name'] + '.png'
            with open(os.path.join(OUT, f), 'wb') as fh:
                fh.write(base64.b64decode(it['data'].split(',', 1)[1]))
            manifest[f] = {'w': it['w'], 'h': it['h'], 'ax': it['ax'], 'ay': it['ay'], 'scale': SCALE}
        with open(os.path.join(OUT, 'manifest.json'), 'w') as fh:
            json.dump({'source': 'page.html SPR (via assemble_game.py)', 'images': manifest}, fh, indent=1)
        print(len(items), 'sprites ->', OUT)
        await b.close()

asyncio.run(main())
