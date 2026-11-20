"""Write tests/fixtures/siege/<case>.json: sieges, Shockwave, Earthquake and a boss fight on a full-size map, the
computer nations' brains frozen (as in gen_war_fixtures.py), Math.random pinned to 0.5. Web build on localhost:8777.
  siege: the frozen nation has Wooden Walls; 20 Footmen batter the palisade into its capital and occupy it
  quake: a Mage casts a Shockwave at the wall, the army walks in and occupies, then the Mage casts an Earthquake
  boss:  a huge army walks into a boss's province, beats it and claims its artifact"""
import asyncio, json, sys
from pathlib import Path
from playwright.async_api import async_playwright

CASES = ['siege', 'quake', 'boss']
FRAMES = {'siege': 2201, 'quake': 4201, 'boss': 1201}
OUT = Path(__file__).resolve().parent.parent / 'tests' / 'fixtures' / 'siege'
JS = r"""(() => {
  Math.random = () => 0.5;
  const [kase, frames] = %s;
  const seed = 'ember', slots = ['moderate', 'easy'], lead = 'cormac';
  menuOpts.practice = false; menuOpts.start = 'center'; leaderPick.realm = lead;
  regenerate(seed, 'normal'); S.explored = new Set(); S.visible = new Set(); S.sig = '';
  applyRace('realm'); setupGame(); spawnAINations(slots, slots.map(() => 'realm')); setupContent(); setupV78(); setupV96(false);
  S.units = S.units.filter(u => !u.bandit || u.boss); S.travelers = [];
  S.started = true; S.last = 0; S.nextTick = 0; S.paused = false;
  stepAI = function (t) { if (!S.started) return; if (t >= (S.allyCheck || 0)) { S.allyCheck = t + 5; stepAlliances(); } };
  aiEnemyThink = function () {};
  for (const o of Object.keys(NATIONS).map(Number)) S.met.add(o);
  const foe = Object.keys(NATIONS).map(Number)[0], fc = NATIONS[foe].capital;
  const q = openNbr[fc].map(n => n.q).filter(p => !S.buildings.has(p) && !uniqueBan(p))[0];
  let acts;
  if (kase === 'siege') acts = [
    { t: 0.3, a: 'foetech', id: 'walls' }, { t: 0.5, a: 'own', p: q }, { t: 0.5, a: 'give', gold: 500, food: 3000 }, { t: 1, a: 'declare', o: foe },
    { t: 1.5, a: 'army', p: q, troops: { 'd-sword': 20 } }, { t: 2, a: 'order', p: fc }];
  else if (kase === 'quake') acts = [
    { t: 0.3, a: 'foetech', id: 'walls' }, { t: 0.5, a: 'own', p: q }, { t: 0.5, a: 'give', gold: 500, food: 3000 }, { t: 0.5, a: 'tech', id: 'magicwell' },
    { t: 0.5, a: 'tech', id: 'magicabund' }, { t: 0.5, a: 'tech', id: 'earthquake' }, { t: 1, a: 'declare', o: foe },
    { t: 1.5, a: 'army', p: q, troops: { 'd-sword': 20, [MAGE]: 1 }, mana: 200 }, { t: 2, a: 'shock', p: fc },
    { t: 130, a: 'order', p: fc }, { t: 260, a: 'mana', n: 200 }, { t: 261, a: 'quake' }];
  else {
    const B = S.units.find(v => v.boss);
    const nb = openNbr[B.prov].map(n => n.q).filter(p => !S.buildings.has(p) && !isDeathMtn(p) && p !== B.guards && !nationOf(p))[0];
    acts = [{ t: 0.5, a: 'own', p: nb }, { t: 0.5, a: 'give', gold: 500, food: 30000 }, { t: 1.5, a: 'army', p: nb, troops: { 'd-sword': 900 } }, { t: 2, a: 'order', p: B.prov }];
  }
  const r6 = v => Math.round(v * 1e6) / 1e6;
  const log = []; toast = function (m) { log.push([Math.round(S.t * 10) / 10, String(m).replace(/<[^>]+>/g, '')]); };
  queueFind = function () {};
  const snaps = [];
  const snap = () => snaps.push({ t: r6(S.t), stock: { ...S.stock }, foeStock: { ...NATIONS[foe].stock },
    wars: S.wars.map(w => [w.a, w.b, warscore(w, ME)]), occ: [...S.occ].sort((a, b) => a[0] - b[0]),
    walls: [...S.walls].sort((a, b) => a - b).map(i => [i, r6(S.wallHp[i] ?? -1), (S.gateOwn.get(linkKey(world.edges[i].a, world.edges[i].b)) || {}).owner || 0]),
    extras: (S.extras.get(fc) || []).map(e => e.type), artifacts: JSON.parse(JSON.stringify(S.artifacts || {})),
    battles: S.battles.map(b => [b.prov, { ...b.lost }]),
    units: S.units.filter(u => u.kind === 'army').map(u => [u.id, u.owner, u.prov, !!u.moving, u.sieging == null ? -1 : u.sieging, u.quake ? u.quake.kind : '', r6(u.x), r6(u.y), { ...u.troops }, r6(u.mana ?? -1)]) });
  let k = 0;
  const mine = () => S.units.filter(u => u.kind === 'army' && u.owner === ME).pop();
  for (let i = 0; i < frames; i++) {
    while (k < acts.length && S.t >= acts[k].t) {
      const A = acts[k++];
      if (A.a === 'own') { S.buildings.set(A.p, { stage: 0, born: 0, owner: ME }); S.surveyed.set(A.p, 0); territory = null; computeIncome(); computeFog(); }
      else if (A.a === 'give') { S.stock.gold += A.gold; S.stock.food += A.food; }
      else if (A.a === 'foetech') NATIONS[foe].tech.gov.done.push(A.id);
      else if (A.a === 'tech') grantTech(A.id);
      else if (A.a === 'declare') declareWar(ME, A.o);
      else if (A.a === 'army') { const a = newArmy(A.p, { ...A.troops }); if (A.mana !== undefined) mine().mana = A.mana; }
      else if (A.a === 'mana') mine().mana = A.n;
      else if (A.a === 'order') A.ok = order(mine(), A.p);
      else if (A.a === 'shock') A.ok = startShock(mine(), A.p);
      else if (A.a === 'quake') { A.why = quakeWhy(mine()); A.ok = startQuake(mine()); }
    }
    update(1 + i * 0.1);
    if (i %% 10 === 0) snap();
  }
  return JSON.stringify({ kase, seed, slots, leader: lead, foe, q, fc, actions: acts, frames, snaps, log });
})()"""

async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    only = sys.argv[1].split(',') if len(sys.argv) > 1 else CASES
    async with async_playwright() as p:
        b = await p.chromium.launch()
        for case in only:
            pg = await b.new_page()
            await pg.add_init_script("window.requestAnimationFrame = () => 0;")
            await pg.goto('http://localhost:8777/realmlings_play.html'); await pg.wait_for_timeout(1200)
            d = json.loads(await pg.evaluate("s => window.__evalIn(s)", JS % json.dumps([case, FRAMES[case]])))
            (OUT / f'{case}.json').write_text(json.dumps(d))
            last = d['snaps'][-1]
            print(case, 'acts', [(a['a'], a.get('ok'), a.get('why')) for a in d['actions']], 'occ', last['occ'], 'arts', last['artifacts'], 'extras', last['extras'])
            for l in d['log'][:25]: print('   ', l)
            await pg.close()
        await b.close()

asyncio.run(main())
