"""Write tests/fixtures/dipl/<seed>.json: the player's diplomatic actions on a full-size map (flirting, a gift,
military access both ways, a Trade Network, an alliance, spies, a bribe), the computer nations' brains frozen except
for alliances and requests, Math.random pinned to 0.5. Web build on localhost:8777."""
import asyncio, json, sys
from pathlib import Path
from playwright.async_api import async_playwright

CASES = [('ember', ['moderate', 'easy', 'moderate'], 'cormac'), ('river', ['easy', 'moderate', 'difficult'], 'havva')]
FRAMES = 2601
OUT = Path(__file__).resolve().parent.parent / 'tests' / 'fixtures' / 'dipl'
JS = r"""(() => {
  Math.random = () => 0.5;
  const [seed, slots, lead, frames] = %s;
  menuOpts.practice = false; menuOpts.start = 'center'; leaderPick.realm = lead;
  regenerate(seed, 'normal'); S.explored = new Set(); S.visible = new Set(); S.sig = '';
  applyRace('realm'); setupGame(); spawnAINations(slots, slots.map(() => 'realm')); setupContent(); setupV78(); setupV96(false);
  S.units = S.units.filter(u => !u.bandit); S.travelers = [];
  S.started = true; S.last = 0; S.nextTick = 0; S.paused = false;
  stepAI = function (t) { if (!S.started) return; if (t >= (S.allyCheck || 0)) { S.allyCheck = t + 5; stepAlliances(); } };
  aiEnemyThink = function () {};
  for (const o of Object.keys(NATIONS).map(Number)) S.met.add(o);
  const ids = Object.keys(NATIONS).map(Number), foe = ids[0], fc = NATIONS[foe].capital;
  const q = openNbr[fc].map(n => n.q).filter(p => !S.buildings.has(p) && !uniqueBan(p))[0];
  const acts = [
    { t: 0.5, a: 'own', p: q }, { t: 0.6, a: 'gold', n: 2000 },
    { t: 1, a: 'dx', act: 'flirt', o: foe }, { t: 1.5, a: 'dx', act: 'gift', o: foe }, { t: 2, a: 'dx', act: 'ask', o: foe },
    { t: 2.5, a: 'dx', act: 'grant', o: foe }, { t: 3, a: 'dx', act: 'trade', o: foe }, { t: 3.5, a: 'dx', act: 'ally', o: foe },
    { t: 4, a: 'dx', act: 'spy', o: ids[1] }, { t: 4.5, a: 'dx', act: 'flirt', o: ids[2] },
    { t: 29, a: 'claimfor', o: ids[1] }, { t: 30, a: 'gold', n: 2000 }, { t: 31, a: 'bribe', o: ids[1] }, { t: 32, a: 'bribe', o: ids[2] },
    { t: 60, a: 'dx', act: 'giveback', o: foe }, { t: 61, a: 'dx', act: 'grant', o: foe }, { t: 62, a: 'dx', act: 'trade', o: foe },
    { t: 200, a: 'dx', act: 'ally', o: foe }];
  const r6 = v => Math.round(v * 1e6) / 1e6;
  const log = []; toast = function (m) { log.push([Math.round(S.t * 10) / 10, String(m).replace(/<[^>]+>/g, '')]); };
  const snaps = [];
  const snap = () => { const D = diplState(); snaps.push({ t: r6(S.t), stock: { ...S.stock }, income: { ...income },
    nations: ids.map(o => [o, { ...NATIONS[o].stock }, aliveNation(o) ? opinion(o, ME) : 0, NATIONS[o].giftVault || 0]),
    mods: D.mods.map(m => [m.o, m.t, m.kind, m.v, r6(m.until)]), access: D.access.map(g => [g.from, g.to]),
    trade: D.trade.map(P => [P.a, P.b]), allies: S.allies.map(A => [A.a, A.b]), wars: S.wars.map(w => [w.a, w.b]),
    news: D.news.map(n => [n.kind, n.a, n.b]), reqs: D.reqs.map(r => [r.from, r.kind]), spies: Object.keys(D.spies).map(Number),
    intel: Object.keys(D.intel).map(o => [+o, D.intel[o].power || 0, (D.intel[o].provs || []).length]) }); };
  let k = 0;
  for (let i = 0; i < frames; i++) {
    while (k < acts.length && S.t >= acts[k].t) {
      const A = acts[k++];
      if (A.a === 'own') { S.buildings.set(A.p, { stage: 0, born: 0, owner: ME }); S.surveyed.set(A.p, 0); territory = null; computeIncome(); computeFog(); }
      else if (A.a === 'gold') S.stock.gold = A.n;
      else if (A.a === 'claimfor') { const c = NATIONS[A.o].capital; A.p = openNbr[c].map(n => n.q).filter(p => !S.buildings.has(p) && !uniqueBan(p))[0]; if (A.p !== undefined) { S.buildings.set(A.p, { stage: 0, born: S.t, owner: A.o }); territory = null; } }
      else if (A.a === 'dx') dxAct(A.act, A.o);
      else if (A.a === 'bribe') { const ts = bribeTargets(A.o); A.why = bribeWhy(A.o); A.y = ts.length ? ts[0] : -1; if (A.y >= 0) dxAct('bribeon', A.o, A.y); }
    }
    update(1 + i * 0.1);
    if (i %% 10 === 0) snap();
  }
  return JSON.stringify({ seed, slots, leader: lead, foe, q, ids, actions: acts, frames, snaps, log });
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
            print(case[0], 'ids', d['ids'], 'bribes', [(a.get('why'), a.get('y')) for a in d['actions'] if a['a'] == 'bribe'], 'allies', last['allies'], 'wars', last['wars'], 'news', last['news'], 'intel', last['intel'])
            for l in d['log'][:30]: print('   ', l)
            await pg.close()
        await b.close()

asyncio.run(main())
