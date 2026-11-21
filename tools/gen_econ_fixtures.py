"""Write tests/fixtures/econ/<seed>_<leader>.json from the running web game (v106 + the v999 dump snippet,
served on localhost:8777; see tools/README.md).

For each seed and Realmling leader it starts a Practice-island game the way menu.js startGame() does (no other
nations, no Bandit Gangs) and auto-scouting off, records the starting state, then drives the game's own update() in 0.1 s frames for 200 s of game time
(the page's animation loop is switched off) and records the stock after every payday."""
import asyncio, json, sys
from pathlib import Path
from playwright.async_api import async_playwright

SEEDS = ['ember', 'oak', 'river', 'Practice']
LEADERS = ['havva', 'alma', 'niall', 'hisola', 'cormac', 'finn', 'weylyn', 'aithne']
SW_LEADERS = ['phlyo', 'aarg', 'nihaarg', 'taal', 'marl', 'glurg', 'roxx', 'zaarg']   # Swamplings (--swamp)
WD_LEADERS = ['sariel', 'eliwen', 'naobrien', 'cerathon', 'paladomis', 'alathandrious', 'ultanitous', 'zariel']   # Woodlings (--wood)
if '--swamp' in sys.argv:
    SEEDS, LEADERS = ['ember', 'oak'], SW_LEADERS
if '--wood' in sys.argv:
    SEEDS, LEADERS = ['ember', 'oak'], WD_LEADERS
OUT = Path(__file__).resolve().parent.parent / 'tests' / 'fixtures' / 'econ'

SETUP = r"""(() => {
  const seed = %s, leader = %s;
  const race = LEADERS[leader] ? LEADERS[leader].race : 'realm';
  menuOpts.race = race; menuOpts.slots = menuOpts.slots.map(() => 'closed'); menuOpts.practice = true; menuOpts.start = 'center';
  leaderPick[race] = leader;
  regenerate(seed, 'practice');
  S.explored = new Set(); S.visible = new Set(); S.sig = '';
  applyRace(race); setupGame(); spawnAINations(menuOpts.slots, menuOpts.races); setupContent(); setupV78(); setupV96(false);
  S.started = true; S.last = 0; S.nextTick = 0; S.paused = false; S.t = 0;
  for (const u of S.units) if (u.kind === WAYFINDER) u.auto = false;   // no auto-scouting: this fixture is about the economy
  S.units = S.units.filter(u => u.owner === ME);   // no Bandit Gangs: milestone 1 has no battles
  window.__pays = [];
  const p0 = payday; payday = function (t) { p0(t); window.__pays.push({ t, stock: { ...S.stock }, income: { ...income }, exhaust: S.exhaust, soldiers: soldierCount() }); };
  return 'ok';
})()"""

DUMP = r"""JSON.stringify({
  leader: NATION.leader, capital: S.capital, stock: S.stock, income, gross: incomeParts.gross, up: incomeParts.up,
  terrain: world.provinces.map(p => p.terrain),
  ic: G.provs.map(p => p.ic), coastal: G.provs.map(p => p.coastal), lakeside: G.provs.map(p => p.lakeside), bounds: G.bounds,
  yields: yields.map(y => ({ gold: y.gold, wood: y.wood, food: y.food, bonus: y.bonus, deposit: y.deposit })),
  treeBorder, capTrees: treeBorder[S.capital],
  units: S.units.map(u => ({ id: u.id, owner: u.owner, kind: u.kind, prov: u.prov, slot: u.slot, x: u.x, y: u.y, troops: u.troops || null })),
  extras: [...S.extras].map(([p, l]) => [p, l.map(e => ({ type: e.type, slot: e.slot, freeFor: e.freeFor === undefined ? null : e.freeFor }))]),
  buildings: [...S.buildings].map(([p, b]) => [p, b.stage, b.owner]),
  techDone: { gov: S.tech.gov.done, mil: S.tech.mil.done, mag: S.tech.mag.done },
  caps: RES.map(k => storageCap(k))
})"""

async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as p:
        b = await p.chromium.launch(); pg = await b.new_page()
        await pg.add_init_script("localStorage.setItem('realm-intro-seen','1'); window.requestAnimationFrame = () => 0;")
        await pg.goto('http://localhost:8777/realmlings_play.html'); await pg.wait_for_timeout(800)
        for seed in SEEDS:
            for L in LEADERS:
                await pg.reload(); await pg.wait_for_timeout(600)
                await pg.evaluate("s => window.__evalIn(s)", SETUP % (json.dumps(seed), json.dumps(L)))
                start = json.loads(await pg.evaluate("s => window.__evalIn(s)", DUMP))
                await pg.evaluate("s => window.__evalIn(s)", "(() => { for (let i = 0; i <= 2000; i++) update(1 + i * 0.1); })()")
                pays = json.loads(await pg.evaluate("s => window.__evalIn(s)", "JSON.stringify(window.__pays)"))
                end_t = await pg.evaluate("s => window.__evalIn(s)", "S.t")
                out = {'seed': seed, 'leader': L, 'frames': 2001, 'frame_dt': 0.1, 'end_t': end_t, 'start': start, 'paydays': pays}
                (OUT / f"{seed.replace(' ', '_')}_{L}.json").write_text(json.dumps(out, indent=1))
                print(seed, L, start['capital'], start['income'], len(pays), pays[-1]['stock'] if pays else None)
        await b.close()

asyncio.run(main())
