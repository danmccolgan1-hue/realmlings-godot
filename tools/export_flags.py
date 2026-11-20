"""Render the web game's notification flags (FLAG_IMG: flags.js and the banners later versions add with bannerSVG)
to PNG files for the Godot port, at twice their size (128 x 160).

Usage (from a folder holding a web build assembled with tools/web_dump_snippet.js, served on localhost:8777):
    python3 tools/export_flags.py <repo>/assets/art

Writes assets/art/flags/common/flag_<name>.png and its manifest.json.
"""
import asyncio, base64, json, os, sys
from playwright.async_api import async_playwright

OUT = sys.argv[1] if len(sys.argv) > 1 else 'assets/art'
SCALE = 2

JS = """async (scale) => {
  const out = {};
  for (const [k, uri] of Object.entries(window.__evalIn("FLAG_IMG"))) {
    const img = new Image(); img.src = uri; await img.decode();
    const c = document.createElement('canvas'); c.width = 64 * scale; c.height = 80 * scale;
    c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
    out[k] = c.toDataURL('image/png');
  }
  return out;
}"""


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch()
        pg = await b.new_page()
        await pg.add_init_script("localStorage.setItem('realm-intro-seen','1')")
        await pg.goto('http://localhost:8777/realmlings_play.html')
        await pg.wait_for_timeout(1500)
        imgs = await pg.evaluate(JS, SCALE)
        await b.close()
    d = os.path.join(OUT, 'flags', 'common')
    os.makedirs(d, exist_ok=True)
    man = {}
    for k, uri in sorted(imgs.items()):
        f = f'flag_{k}.png'
        with open(os.path.join(d, f), 'wb') as fh:
            fh.write(base64.b64decode(uri.split(',', 1)[1]))
        man[f] = {'ax': 0, 'ay': 0, 'scale': SCALE}
    with open(os.path.join(d, 'manifest.json'), 'w') as fh:
        json.dump({'images': man}, fh, indent=1)
    print(len(man), 'flags')

asyncio.run(main())
