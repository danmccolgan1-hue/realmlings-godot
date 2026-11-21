"""Render the web game's art to PNG files for the Godot port.

Usage (from a folder holding a web build assembled with tools/web_dump_snippet.js, served on localhost:8777):
    python3 tools/export_art.py <repo>/assets/art

Starts a Realmling game in headless Chromium, runs tools/export_art.js inside it, writes every image to
assets/art/<category>/<race>/... and one manifest.json per category folder with each image's anchor and scale.
"""
import asyncio, base64, json, os, sys
from collections import defaultdict
from playwright.async_api import async_playwright

OUT = sys.argv[1] if len(sys.argv) > 1 else 'assets/art'
ONLY = [a[7:].split(',') for a in sys.argv[2:] if a.startswith('--jobs=')]   # --jobs=uiicons: only these, merged into the manifests
ONLY = ONLY[0] if ONLY else None
HERE = os.path.dirname(os.path.abspath(__file__))


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch()
        pg = await b.new_page()
        await pg.add_init_script("localStorage.setItem('realm-intro-seen','1')")
        await pg.goto('http://localhost:8777/realmlings_play.html')
        await pg.wait_for_timeout(1500)
        await pg.evaluate("document.querySelector('#mNew').click()")
        await pg.wait_for_timeout(200)
        await pg.evaluate("document.querySelector('#mRace [data-race=\"realm\"]').click()")
        await pg.wait_for_timeout(200)
        await pg.evaluate("document.querySelector('#mStart').click()")
        await pg.wait_for_timeout(3500)
        await pg.evaluate(open(os.path.join(HERE, 'export_art.js')).read())
        jobs = await pg.evaluate('window.__exportArtJobs')
        if ONLY:
            jobs = [j for j in jobs if j in ONLY]
        manifests = defaultdict(dict)
        errors = []
        for job in jobs:
            items = await pg.evaluate(f'window.__exportArt({json.dumps(job)})')
            for it in items:
                if it.get('error'):
                    errors.append(f"{it['file']}: {it['error']}")
                    continue
                path = os.path.join(OUT, it['file'])
                os.makedirs(os.path.dirname(path), exist_ok=True)
                data = it.pop('png').split(',', 1)[1]
                with open(path, 'wb') as f:
                    f.write(base64.b64decode(data))
                folder = os.path.dirname(it['file'])
                name = os.path.basename(it.pop('file'))
                manifests[folder][name] = it
            print(job, len(items))
        for folder, m in manifests.items():
            mf = os.path.join(OUT, folder, 'manifest.json')
            if ONLY and os.path.exists(mf):
                m = {**json.load(open(mf)).get('images', {}), **m}
            with open(os.path.join(OUT, folder, 'manifest.json'), 'w') as f:
                json.dump({'note': 'ax, ay: the anchor pixel (where the game places the art: province center, plot, feet). scale: image pixels per world unit.', 'images': dict(sorted(m.items()))}, f, indent=1)
        if errors:
            print('errors:', len(errors))
            for e in errors[:30]:
                print('  ', e)
        await b.close()

asyncio.run(main())
