"""Write tests/fixtures/decor/<seed>.json: the web game's map decoration for Practice islands (page.html prep as
assembled: province details, border bands, junction fillers, lake ripples, waves, clouds), from the running web
build on localhost:8777 (see tools/README.md)."""
import asyncio, json
from pathlib import Path
from playwright.async_api import async_playwright

SEEDS = ['ember', 'oak', 'river', 'Practice']
OUT = Path(__file__).resolve().parent.parent / 'tests' / 'fixtures' / 'decor'
JS = r"""(() => {
  regenerate(%s, 'practice');
  const r6 = v => Math.round(v * 1e6) / 1e6;
  return JSON.stringify({
    items: G.provs.map(p => p.items.map(it => [r6(it.x), r6(it.y), it.s])),
    sway: G.sway.map(it => [r6(it.x), r6(it.y), it.s, r6(it.ph)]), still: G.still.map(it => [r6(it.x), r6(it.y), it.s]),
    lakeMarks: G.lakeMarks.map(m => [r6(m.x), r6(m.y)]), waves: G.waves.map(v => [r6(v.x), r6(v.y), r6(v.ph), r6(v.s)]),
    clouds: G.clouds.map(c => [r6(c.x), r6(c.y), r6(c.v), r6(c.s)]), bounds: G.bounds });
})()"""

async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as p:
        b = await p.chromium.launch(); pg = await b.new_page()
        await pg.goto('http://localhost:8777/realmlings_play.html'); await pg.wait_for_timeout(1200)
        for seed in SEEDS:
            d = json.loads(await pg.evaluate("s => window.__evalIn(s)", JS % json.dumps(seed)))
            d['seed'] = seed
            (OUT / f'{seed}.json').write_text(json.dumps(d))
            print(seed, sum(len(i) for i in d['items']), 'items', len(d['sway']), 'sway', len(d['still']), 'still', len(d['waves']), 'waves')
        await b.close()

asyncio.run(main())
