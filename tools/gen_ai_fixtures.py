"""Write tests/fixtures/ai/<seed>.json: computer nations playing on their own on a full-size map (the player idle at his
capital), Math.random pinned to 0.5, snapshots of every nation every 5 s. Web build on localhost:8777."""
import asyncio, json, sys
from pathlib import Path
from playwright.async_api import async_playwright

CASES = [('ember', ['moderate', 'easy', 'difficult'], 'cormac'), ('river', ['difficult', 'moderate'], 'hisola'),
         ('crowd', ['difficult', 'difficult', 'moderate', 'difficult', 'moderate', 'difficult'], 'finn')]
ONLY = sys.argv[2].split(',') if len(sys.argv) > 2 else None
FRAMES = int(sys.argv[1]) if len(sys.argv) > 1 else 6001
OUT = Path(__file__).resolve().parent.parent / 'tests' / 'fixtures' / 'ai'
JS = r"""(() => {
  Math.random = () => 0.5;
  const [seed, slots, lead, frames] = %s;
  menuOpts.practice = false; menuOpts.start = 'center'; leaderPick.realm = lead;
  regenerate(seed, 'normal'); S.explored = new Set(); S.visible = new Set(); S.sig = '';
  applyRace('realm'); setupGame(); spawnAINations(slots, slots.map(() => 'realm')); setupContent(); setupV78(); setupV96(false);
  S.units = S.units.filter(u => !u.bandit); S.travelers = [];
  S.started = true; S.last = 0; S.nextTick = 0; S.paused = false;
  for (const o of Object.keys(NATIONS).map(Number)) S.met.add(o);
  const r6 = v => Math.round(v * 1e6) / 1e6;
  const log = []; toast = function (m) { log.push([Math.round(S.t * 10) / 10, String(m).replace(/<[^>]+>/g, '')]); };
  const snaps = [];
  const snap = () => snaps.push({ t: r6(S.t), nations: Object.values(NATIONS).map(N => ({ id: N.id, alive: N.alive, stock: { ...N.stock }, income: { ...N.income },
      stage: __v103.stageText(N), stance: N.stance || 'normal', rival: N.rival == null ? 0 : N.rival, school: N.school || '', exhaust: N.exhaust,
      tech: TREE_KEYS.map(t => [N.tech[t].cur || '', N.tech[t].done.join(','), Math.round(N.tech[t].prog), N.tech[t].opts.join(',')]), rep: { ...N.rep },
      queue: N.queue.map(q => [q.kind, q.prov]), ups: [...N.ups.keys()].sort((a, b) => a - b), surveyed: N.surveyed.size })),
    buildings: [...S.buildings].map(([p, b]) => [p, b.stage, b.owner]).sort((a, b) => a[0] - b[0]),
    extras: [...S.extras].filter(([p, l]) => l.length && nationOf(p) !== ME).map(([p, l]) => [p, l.map(e => e.type + (e.level > 1 ? e.level : '') + (e.crop && e.crop !== 'staple' ? ':' + e.crop : '')).join(',')]).sort((a, b) => a[0] - b[0]),
    units: S.units.filter(u => u.owner !== ME && isNation(u.owner)).map(u => [u.id, u.owner, u.kind, u.prov, !!u.moving, u.kind === 'army' ? { ...u.troops } : (u.build ? u.build.type + '@' + u.build.prov : u.aiJob ? 'job:' + u.aiJob.type + '@' + u.aiJob.prov : '')]),
    wars: S.wars.map(w => [w.a, w.b]), allies: S.allies.map(A => [A.a, A.b]) });
  for (let i = 0; i < frames; i++) {
    update(1 + i * 0.1);
    if (i %% 100 === 0) snap();
  }
  return JSON.stringify({ seed, slots, leader: lead, frames, snaps, log });
})()"""

async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as p:
        b = await p.chromium.launch()
        for case in CASES:
            if ONLY and case[0] not in ONLY: continue
            pg = await b.new_page()
            await pg.add_init_script("window.requestAnimationFrame = () => 0;")
            await pg.goto('http://localhost:8777/realmlings_play.html'); await pg.wait_for_timeout(1200)
            d = json.loads(await pg.evaluate("s => window.__evalIn(s)", JS % json.dumps(list(case) + [FRAMES])))
            (OUT / f'{case[0]}.json').write_text(json.dumps(d))
            last = d['snaps'][-1]
            print(case[0], 't', last['t'], [(n['id'], n['stage'], len([b for b in last['buildings'] if b[2] == n['id']]), n['stock']) for n in last['nations']], 'wars', last['wars'], 'allies', last['allies'])
            for l in d['log'][:10]: print('   ', l)
            await pg.close()
        await b.close()

asyncio.run(main())
