"""Write tests/fixtures/setup/<seed>.json: a full-size game as the web game sets it up (menu.js startGame) with
computer nations in some slots, Math.random pinned to 0.5. Needs the web build on localhost:8777 (tools/README.md)."""
import asyncio, json
from pathlib import Path
from playwright.async_api import async_playwright

CASES = [('ember', ['moderate', 'easy', 'difficult'], 'cormac', 'center'),
         ('oak', ['easy', 'closed', 'moderate', 'difficult', 'easy'], 'hisola', 'edge'),
         ('river', ['difficult', 'moderate'], 'aithne', 'center')]
OUT = Path(__file__).resolve().parent.parent / 'tests' / 'fixtures' / 'setup'
JS = r"""(() => {
  Math.random = () => 0.5;
  const [seed, slots, lead, start] = %s;
  menuOpts.practice = false; menuOpts.start = start; leaderPick.realm = lead;
  regenerate(seed, 'normal');
  S.explored = new Set(); S.visible = new Set(); S.sig = '';
  applyRace('realm');
  setupGame();
  spawnAINations(slots, slots.map(() => 'realm'));
  setupContent();
  setupV78();
  setupV96(false);
  const r6 = v => Math.round(v * 1e6) / 1e6;
  return JSON.stringify({
    seed, slots, leader: lead, start, capital: S.capital,
    nations: Object.values(NATIONS).map(N => ({ id: N.id, diff: N.diff, name: N.name, emblem: N.emblem, capital: N.capital, family: N.family,
      armorLine: N.armorLine, wantSchool: N.wantSchool, leader: N.leader, design: N.design, warCheck: r6(N.warCheck), think: r6(N.think),
      stock: N.stock, techDone: Object.fromEntries(TREE_KEYS.map(t => [t, N.tech[t].done])) })),
    players: Object.fromEntries(Object.entries(PLAYERS).filter(([k]) => +k === 1 || NATIONS[k]).map(([k, v]) => [k, { name: v.name, color: v.color, light: v.light }])),
    units: S.units.map(u => ({ id: u.id, owner: u.owner, kind: u.kind, prov: u.prov, slot: u.slot, troops: u.troops ? { ...u.troops } : null, boss: u.boss || null, bandit: !!u.bandit, name: u.kind === 'army' && u.owner !== 1 ? u.name : null })),
    buildings: [...S.buildings].map(([p, b]) => [p, b.stage, b.owner]),
    extras: [...S.extras].map(([p, l]) => [p, l.map(e => [e.type, e.slot, e.freeFor || 0])]),
    setpieces: [...S.setpieces].sort((a, b) => a[0] - b[0]), finds: [...S.finds].map(([p, f]) => [p, f.id]),
    travelers: S.travelers.map(T => [T.prov, T.n]), yields: yields.map(y => [y.gold, y.wood, y.food]),
    stock: S.stock, techDone: Object.fromEntries(TREE_KEYS.map(t => [t, S.tech[t].done])),
    dstats: Object.fromEntries(Object.entries(DSTATS).filter(([k]) => /^ai\d/.test(k)).map(([k, d]) => [k, [d.atk, d.hp, r6(d.red), d.speed]])) });
})()"""

async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as p:
        b = await p.chromium.launch()
        for case in CASES:
            pg = await b.new_page()
            await pg.goto('http://localhost:8777/realmlings_play.html'); await pg.wait_for_timeout(1200)
            d = json.loads(await pg.evaluate("s => window.__evalIn(s)", JS % json.dumps(list(case))))
            (OUT / f'{case[0]}.json').write_text(json.dumps(d))
            print(case[0], 'capital', d['capital'], [(n['id'], n['capital'], n['name'], n['leader']) for n in d['nations']], len(d['units']), 'units')
            await pg.close()
        await b.close()

asyncio.run(main())
