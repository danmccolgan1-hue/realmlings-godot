"""Write tests/fixtures/play/<seed>_<scenario>.json from the running web game (v106 + the v999 dump snippet on
localhost:8777; see tools/README.md).

A Practice-island game (no Bandit Gangs, no travelers; the Intact Ruins are recorded in `plan` and then removed) is played by a short script of orders, applied at the start of
the first frame whose game time has reached each order's time, with the game's own update() in 0.1 s frames.
A snapshot every second records units, fog, surveys, settlements, buildings and stock.

Scenarios
  orders: Havva (250 of each). The Wayfinder surveys a neighbour then explores past it; the Mason builds a Farm at
          the capital, then an outpost on the surveyed neighbour, which is upgraded to a Fort; the army walks out
          and back.
  auto:   Aithne: two Wayfinders on auto-scouting (survey everything known, then explore), Far Sight on."""
import asyncio, json
from pathlib import Path
from playwright.async_api import async_playwright

SEEDS = ['ember', 'oak', 'river', 'Practice']
OUT = Path(__file__).resolve().parent.parent / 'tests' / 'fixtures' / 'play'
FRAMES = 2401   # 240 s

SETUP = r"""(() => {
  const seed = %s, leader = %s;
  menuOpts.race = 'realm'; menuOpts.slots = menuOpts.slots.map(() => 'closed'); menuOpts.practice = true; menuOpts.start = 'center';
  leaderPick.realm = leader;
  regenerate(seed, 'practice');
  S.explored = new Set(); S.visible = new Set(); S.sig = '';
  applyRace('realm'); setupGame(); spawnAINations(menuOpts.slots, menuOpts.races); setupContent(); setupV78(); setupV96(false);
  S.started = true; S.last = 0; S.nextTick = 0; S.paused = false; S.t = 0;
  S.units = S.units.filter(u => u.owner === ME);   // no Bandit Gangs: milestone 1 has no battles
  S.travelers = [];                                 // travelers come later
  const ruins = [...S.finds].filter(([, f]) => f.id === 'ruins').map(([p]) => p);
  S.finds.clear();                                  // the ruins grant a random technology: placement is checked, the run goes without them
  const cap = S.capital, E0 = new Set(S.explored);
  const q1 = openNbr[cap][0].q;
  const q2c = openNbr[q1].map(n => n.q).find(q => q !== cap && !E0.has(q));
  const q2 = q2c === undefined ? -1 : q2c;
  window.__plan = { cap, q1, q2, ruins };
  return JSON.stringify(window.__plan);
})()"""

ACTIONS = {
  'orders': lambda P: [
    {'t': 0.5, 'a': 'survey', 'u': 'wf', 'p': P['q1']},
    {'t': 0.5, 'a': 'build', 'u': 'mason', 'p': P['cap'], 'type': 'farm'},
    {'t': 1.0, 'a': 'order', 'u': 'army', 'p': P['q1']},
    {'t': 40, 'a': 'order', 'u': 'army', 'p': P['cap']},
    {'t': 60, 'a': 'build', 'u': 'mason', 'p': P['q1'], 'type': 'outpost'},
  ] + ([{'t': 60, 'a': 'order', 'u': 'wf', 'p': P['q2']}, {'t': 80, 'a': 'survey', 'u': 'wf', 'p': P['q2']}] if P['q2'] >= 0 else []) + [
    {'t': 140, 'a': 'give', 'gold': 400, 'wood': 400, 'food': 0},
    {'t': 140, 'a': 'upgrade', 'p': P['q1']},
    {'t': 170, 'a': 'build', 'u': 'mason', 'p': P['q1'], 'type': 'farm'},
  ],
  'auto': lambda P: [],
}
LEADER = {'orders': 'havva', 'auto': 'aithne'}

RUN = r"""(() => {
  const acts = %s, frames = %d, snaps = [];
  const U = { wf: () => S.units.find(u => u.kind === WAYFINDER), mason: () => S.units.find(u => u.kind === MASON), army: () => S.units.find(u => u.kind === 'army') };
  const log = []; const t0 = toast; toast = function (m) { log.push([Math.round(S.t * 10) / 10, String(m).replace(/<[^>]+>/g, '')]); };
  const snap = () => snaps.push({ t: S.t, stock: { ...S.stock }, income: { ...income },
    units: S.units.map(u => ({ kind: u.kind, prov: u.prov, x: u.x, y: u.y, moving: !!u.moving, slot: u.slot, scouting: u.scouting === undefined ? null : u.scouting,
      survey: !!u.survey, build: u.build ? u.build.type : null, pending: u.pending ? u.pending.type : null, queue: u.surveyQueue.length })),
    explored: [...S.explored].sort((a, b) => a - b), visible: [...S.visible].sort((a, b) => a - b),
    surveyed: [...S.surveyed.keys()].sort((a, b) => a - b), wf: [...S.wf].sort((a, b) => a - b),
    buildings: [...S.buildings].map(([p, b]) => [p, b.stage]).sort((a, b) => a[0] - b[0]),
    extras: [...S.extras].map(([p, l]) => [p, l.map(e => [e.type, e.slot])]).sort((a, b) => a[0] - b[0]),
    upgrades: [...S.upgrades.keys()], techs: S.tech.gov.done.length + S.tech.mil.done.length + S.tech.mag.done.length,
    finds: [...S.finds].map(([p, f]) => [p, f.id, !!f.done]) });
  let k = 0;
  for (let i = 0; i < frames; i++) {
    while (k < acts.length && S.t >= acts[k].t) {
      const A = acts[k++], u = A.u ? U[A.u]() : null;
      if (A.a === 'survey') { u.surveyQueue.push(A.p); }
      else if (A.a === 'order') order(u, A.p);
      else if (A.a === 'build') orderBuild(u, A.p, A.type);
      else if (A.a === 'upgrade') startUpgrade(A.p);
      else if (A.a === 'give') { for (const r of RES) S.stock[r] += A[r]; }
    }
    update(1 + i * 0.1);
    if (i %% 10 === 0) snap();
  }
  toast = t0;
  return JSON.stringify({ snaps, log });
})()"""

async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as p:
        b = await p.chromium.launch(); pg = await b.new_page()
        await pg.add_init_script("localStorage.setItem('realm-intro-seen','1'); window.requestAnimationFrame = () => 0;")
        await pg.goto('http://localhost:8777/realmlings_play.html'); await pg.wait_for_timeout(800)
        for seed in SEEDS:
            for sc in ['orders', 'auto']:
                await pg.reload(); await pg.wait_for_timeout(600)
                plan = json.loads(await pg.evaluate("s => window.__evalIn(s)", SETUP % (json.dumps(seed), json.dumps(LEADER[sc]))))
                acts = ACTIONS[sc](plan)
                res = json.loads(await pg.evaluate("s => window.__evalIn(s)", RUN % (json.dumps(acts), FRAMES)))
                out = {'seed': seed, 'scenario': sc, 'leader': LEADER[sc], 'plan': plan, 'actions': acts, 'frames': FRAMES, **res}
                (OUT / f"{seed.replace(' ', '_')}_{sc}.json").write_text(json.dumps(out, indent=0))
                last = res['snaps'][-1]
                print(seed, sc, plan, 'stock', last['stock'], 'bld', last['buildings'], 'ex', last['extras'], 'surv', last['surveyed'], 'expl', last['explored'])
                for t, m in res['log'][:14]: print('   ', t, m[:110])
        await b.close()

asyncio.run(main())
