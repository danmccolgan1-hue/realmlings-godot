"""Write tests/fixtures/war/<seed>.json: a scripted war on a full-size map against a frozen computer nation (its brain
off, alliances still checked), Math.random pinned to 0.5. The player takes a province next to the nation's capital,
declares war, marches an army onto the capital, occupies it, and makes peace. Web build on localhost:8777."""
import asyncio, json, sys
from pathlib import Path
from playwright.async_api import async_playwright

CASES = [('ember', ['moderate', 'easy'], 'cormac', 'gold'), ('river', ['difficult', 'moderate'], 'hisola', 'provs')]
FRAMES = 2201
OUT = Path(__file__).resolve().parent.parent / 'tests' / 'fixtures' / 'war'
JS = r"""(() => {
  Math.random = () => 0.5;
  const [seed, slots, lead, peace, frames] = %s;
  menuOpts.practice = false; menuOpts.start = 'center'; leaderPick.realm = lead;
  regenerate(seed, 'normal'); S.explored = new Set(); S.visible = new Set(); S.sig = '';
  applyRace('realm'); setupGame(); spawnAINations(slots, slots.map(() => 'realm')); setupContent(); setupV78(); setupV96(false);
  S.units = S.units.filter(u => !u.bandit); S.travelers = [];
  S.started = true; S.last = 0; S.nextTick = 0; S.paused = false;
  stepAI = function (t) { if (!S.started) return; if (t >= (S.allyCheck || 0)) { S.allyCheck = t + 5; stepAlliances(); } };
  aiEnemyThink = function () {};   // the computer nations' own diplomacy is part of their brain
  for (const o of Object.keys(NATIONS).map(Number)) S.met.add(o);
  const foe = Object.keys(NATIONS).map(Number)[0], fc = NATIONS[foe].capital;
  const q = openNbr[fc].map(n => n.q).filter(p => !S.buildings.has(p) && !uniqueBan(p))[0];
  const acts = [
    { t: 0.5, a: 'own', p: q }, { t: 0.5, a: 'give', gold: 500, food: 3000 }, { t: 1, a: 'declare', o: foe },
    { t: 1.5, a: 'army', p: q, troops: { 'd-sword': 10 } }, { t: 2, a: 'order', p: fc },
    { t: 190, a: 'peace', o: foe, kind: peace }];
  const r6 = v => Math.round(v * 1e6) / 1e6;
  const log = []; toast = function (m) { log.push([Math.round(S.t * 10) / 10, String(m).replace(/<[^>]+>/g, '')]); };
  const snaps = [];
  const snap = () => snaps.push({ t: r6(S.t), stock: { ...S.stock }, foeStock: { ...NATIONS[foe].stock },
    wars: S.wars.map(w => [w.id, w.a, w.b, r6(w.base), !!w.active, warscore(w, ME), r6(w.peak), r6(w.nextTick), w.parent || 0]),
    occ: [...S.occ].sort((a, b) => a[0] - b[0]), prog: [...S.occProg].map(([p, x]) => [p, x.by, r6(x.f)]).sort((a, b) => a[0] - b[0]),
    buildings: [...S.buildings].map(([p, b]) => [p, b.stage, b.owner, !!b.cc]).sort((a, b) => a[0] - b[0]),
    battles: S.battles.map(b => [b.prov, { ...b.lost }]), truces: [...S.truces].map(([k, v]) => [k, r6(v)]),
    units: S.units.filter(u => u.kind === 'army').map(u => [u.id, u.owner, u.prov, !!u.moving, !!u.exiting, { ...u.troops }]) });
  let k = 0;
  for (let i = 0; i < frames; i++) {
    while (k < acts.length && S.t >= acts[k].t) {
      const A = acts[k++];
      if (A.a === 'own') { S.buildings.set(A.p, { stage: 0, born: 0, owner: ME }); S.surveyed.set(A.p, 0); territory = null; computeIncome(); computeFog(); }
      else if (A.a === 'give') { S.stock.gold += A.gold; S.stock.food += A.food; }
      else if (A.a === 'declare') declareWar(ME, A.o);
      else if (A.a === 'army') newArmy(A.p, { ...A.troops });
      else if (A.a === 'order') { const a = S.units.filter(u => u.kind === 'army' && u.owner === ME).pop(); order(a, A.p); }
      else if (A.a === 'peace') { const w = warBetween(ME, A.o); if (w) { const terms = A.kind === 'provs' ? { kind: 'provs', provs: provsOf(A.o) } : { kind: A.kind }; A.terms = terms; A.why = peaceCheck(w, terms.kind, terms.provs); makePeace(w, ME, terms); } }
    }
    update(1 + i * 0.1);
    if (i %% 10 === 0) snap();
  }
  return JSON.stringify({ seed, slots, leader: lead, foe, q, fc, actions: acts, frames, snaps, log });
})()"""

async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as p:
        b = await p.chromium.launch()
        for case in CASES:
            pg = await b.new_page()
            await pg.add_init_script("window.requestAnimationFrame = () => 0;")
            await pg.goto('http://localhost:8777/realmlings_play.html'); await pg.wait_for_timeout(1200)
            d = json.loads(await pg.evaluate("s => window.__evalIn(s)", JS % json.dumps(list(case) + [FRAMES])))
            (OUT / f'{case[0]}.json').write_text(json.dumps(d))
            last = d['snaps'][-1]
            print(case[0], 'foe', d['foe'], 'q', d['q'], 'cap', d['fc'], 'peace', d['actions'][-1].get('why'), d['actions'][-1].get('terms'), 'wars', last['wars'], 'occ', last['occ'])
            for l in d['log'][:14]: print('   ', l)
            await pg.close()
        await b.close()

asyncio.run(main())
