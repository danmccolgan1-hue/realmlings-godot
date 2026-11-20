"""Write tests/fixtures/play/<seed>_<scenario>.json from the running web game (v106 + the v999 dump snippet on
localhost:8777; see tools/README.md).

A Practice-island game (no Bandit Gangs, no travelers; the Intact Ruins are recorded in `plan` and then removed) is played by a short script of orders, applied at the start of
the first frame whose game time has reached each order's time, with the game's own update() in 0.1 s frames.
A snapshot every second records units, fog, surveys, settlements, buildings and stock.

Scenarios
  orders: Havva (250 of each). The Wayfinder surveys a neighbour then explores past it; the Mason builds a Farm at
          the capital, then an outpost on the surveyed neighbour, which is upgraded to a Fort; the army walks out
          and back.
  auto:   Aithne: two Wayfinders on auto-scouting (survey everything known, then explore), Far Sight on.
  train:  Cormac (Barracks): Masons, a Wayfinder and soldiers trained at the capital and the Barracks, the army
          leaves so new soldiers form a new army, a Forge unlocks the ranged unit.
  research: Finn (Forge): Government and Military picks, switching, research points added (as the Intact Ruins
          do), Battle Forge, the Forge upgraded to a Battle Forge (Military Tier II).
  magic:  Havva: her locked school, then a Magic and a Government technology.
  roads:  Havva: an outpost next door, a road to the capital, Wooden Walls (the capital walls itself in, with
          gates), the army walks through its own gate, the Mason builds a wall.
  develop: Finn: the capital developed twice (Math.random fixed at 0.99: no lucky finds), the army split, combined
          and split again, the Forge torn down. 620 s.
  battle: Cormac: a Bandit Gang of 4 Footmen placed next door, attacked and broken (bounty); soldiers trained, a
          gang of 12, attacked, then a retreat. battlemagic: Havva's Mage with five soldiers, Hardened Skin, a gang of 7.
          Math.random is pinned to 0.5 for these (blow strength, who is hit, rows, patrols).
  life / arcane / death: the three Realmling schools' spells (Havva, Alma, Niall): mana set by the script where a
          spell needs more than the Mages have; Harvest, Mending, Eyes of the Forest, a forest path; Interdimensional
          Trading, Clear Thoughts, Teleportation Rift; Grave Robbing, Haunt, a tunnel. '?' and '@path' targets are
          recorded in `actions`.
The web game offers technologies at random; a pick of '?' takes the first on offer by id (recorded in `actions`)
and the chosen technology is added to the offer when missing, so the test can do exactly the same."""
import asyncio, json, sys
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
  const travelers = S.travelers.map(B => [B.prov, B.n, B.x, B.y, B.wait]);
  const setpieces = [...S.setpieces].sort((a, b) => a[0] - b[0]);
  S.travelers = [];                                 // travelers stop the game to ask: placement is checked, the run goes without them
  const ruins = [...S.finds].filter(([, f]) => f.id === 'ruins').map(([p]) => p);
  S.finds.clear();                                  // the ruins grant a random technology: placement is checked, the run goes without them
  const cap = S.capital, E0 = new Set(S.explored);
  const q1 = openNbr[cap][0].q;
  const q2c = openNbr[q1].map(n => n.q).find(q => q !== cap && !E0.has(q));
  const q2 = q2c === undefined ? -1 : q2c;
  window.__plan = { cap, q1, q2, ruins, travelers, setpieces };
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
  'train': lambda P: [
    {'t': 0.5, 'a': 'give', 'gold': 1500, 'wood': 300, 'food': 300},
    {'t': 0.5, 'a': 'train', 'src': 'capital', 'p': P['cap'], 'kind': 'mason:A'},
    {'t': 0.5, 'a': 'train', 'src': 'capital', 'p': P['cap'], 'kind': 'pioneer:B'},
    {'t': 0.5, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'd-sword'},
    {'t': 0.5, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'd-spear'},
    {'t': 0.5, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'd1'},
    {'t': 20, 'a': 'order', 'u': 'army', 'p': P['q1']},
    {'t': 30, 'a': 'train', 'src': 'capital', 'p': P['cap'], 'kind': 'mason:A'},
    {'t': 30, 'a': 'train', 'src': 'capital', 'p': P['cap'], 'kind': 'mason:A'},
    {'t': 30, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'd-club'},
    {'t': 30, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'd-rider'},
    {'t': 60, 'a': 'build', 'u': 'mason', 'p': P['cap'], 'type': 'forge'},
    {'t': 125, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'rng-realm'},
  ],
  'research': lambda P: [
    {'t': 0.5, 'a': 'give', 'gold': 3000, 'wood': 3000, 'food': 500},
    {'t': 0.5, 'a': 'pick', 'tree': 'gov', 'id': '?'},
    {'t': 0.5, 'a': 'pick', 'tree': 'mil', 'id': '?'},
    {'t': 15, 'a': 'points', 'tree': 'gov', 'n': 200},
    {'t': 20, 'a': 'pick', 'tree': 'gov', 'id': '?'},
    {'t': 20, 'a': 'points', 'tree': 'mil', 'n': 500},
    {'t': 25, 'a': 'pick', 'tree': 'mil', 'id': '?'},
    {'t': 26, 'a': 'pick', 'tree': 'gov', 'id': '?'},
    {'t': 27, 'a': 'points', 'tree': 'mil', 'n': 500},
    {'t': 30, 'a': 'pick', 'tree': 'mil', 'id': 'battleforge'},
    {'t': 31, 'a': 'points', 'tree': 'mil', 'n': 3000},
    {'t': 35, 'a': 'xup', 'p': P['cap'], 'type': 'forge'},
    {'t': 70, 'a': 'pick', 'tree': 'mil', 'id': '?'},
  ],
  'magic': lambda P: [
    {'t': 0.5, 'a': 'pick', 'tree': 'mag', 'id': 'school-life'},
    {'t': 1, 'a': 'points', 'tree': 'mag', 'n': 1000},
    {'t': 12, 'a': 'pick', 'tree': 'mag', 'id': '?'},
    {'t': 13, 'a': 'pick', 'tree': 'gov', 'id': '?'},
  ],
  'roads': lambda P: [
    {'t': 0.5, 'a': 'give', 'gold': 3000, 'wood': 3000, 'food': 500},
    {'t': 0.5, 'a': 'grant', 'id': 'roads'},
    {'t': 0.5, 'a': 'survey', 'u': 'wf', 'p': P['q1']},
    {'t': 40, 'a': 'build', 'u': 'mason', 'p': P['q1'], 'type': 'outpost'},
    {'t': 90, 'a': 'link', 'u': 'mason', 'p': P['cap'], 'type': 'road'},
    {'t': 101, 'a': 'grant', 'id': 'walls'},
    {'t': 102, 'a': 'order', 'u': 'army', 'p': P['q1']},
    {'t': 104, 'a': 'link', 'u': 'mason', 'p': '?', 'type': 'wall'},
  ] + [
    {'t': 125, 'a': 'order', 'u': 'army', 'p': P['cap']},
    {'t': 130, 'a': 'order', 'u': 'mason', 'p': P['cap']},
  ],
  'develop': lambda P: [
    {'t': 0.5, 'a': 'give', 'gold': 3000, 'wood': 3000, 'food': 3000},
    {'t': 0.5, 'a': 'develop', 'p': P['cap']},
    {'t': 5, 'a': 'split'},
    {'t': 10, 'a': 'combine'},
    {'t': 15, 'a': 'split'},
    {'t': 60, 'a': 'destroy', 'p': P['cap'], 'type': 'forge'},
    {'t': 305, 'a': 'develop', 'p': P['cap']},
  ],
  'life': lambda P: [
    {'t': 0.5, 'a': 'give', 'gold': 500, 'wood': 500, 'food': 0},
    {'t': 0.5, 'a': 'grant', 'id': 'school-life'},
    {'t': 0.6, 'a': 'grant', 'id': 'harvest'}, {'t': 0.6, 'a': 'grant', 'id': 'mending'},
    {'t': 0.6, 'a': 'grant', 'id': 'forest'}, {'t': 0.6, 'a': 'grant', 'id': 'eyesforest'},
    {'t': 0.6, 'a': 'build', 'u': 'mason', 'p': P['cap'], 'type': 'farm'},
    {'t': 35, 'a': 'cast', 'k': 'harvest'},
    {'t': 70, 'a': 'mana', 'n': 200}, {'t': 71, 'a': 'cast', 'k': 'mending'},
    {'t': 80, 'a': 'aim', 'k': 'eyes', 'p': '?'},
    {'t': 90, 'a': 'mana', 'n': 250}, {'t': 91, 'a': 'path', 'kind': 'forest', 'p': '?'},
    {'t': 120, 'a': 'order', 'u': 'army', 'p': '@path'},
    {'t': 150, 'a': 'order', 'u': 'army', 'p': P['cap']},
  ],
  'arcane': lambda P: [
    {'t': 0.5, 'a': 'grant', 'id': 'school-arcane'},
    {'t': 0.6, 'a': 'grant', 'id': 'trading'}, {'t': 0.6, 'a': 'grant', 'id': 'clearthoughts'}, {'t': 0.6, 'a': 'grant', 'id': 'rift'},
    {'t': 1, 'a': 'mana', 'n': 100}, {'t': 2, 'a': 'cast', 'k': 'trading'},
    {'t': 10, 'a': 'mana', 'n': 100}, {'t': 11, 'a': 'cast', 'k': 'mind'},
    {'t': 20, 'a': 'mana', 'n': 150}, {'t': 21, 'a': 'aim', 'k': 'rift', 'p': P['q1']},
    {'t': 40, 'a': 'cast', 'k': 'trading'},
  ],
  'death': lambda P: [
    {'t': 0.5, 'a': 'grant', 'id': 'school-death'},
    {'t': 0.6, 'a': 'grant', 'id': 'graverob'}, {'t': 0.6, 'a': 'grant', 'id': 'underworld'}, {'t': 0.6, 'a': 'grant', 'id': 'haunt'},
    {'t': 1, 'a': 'mana', 'n': 100}, {'t': 2, 'a': 'cast', 'k': 'graverob'},
    {'t': 10, 'a': 'cast', 'k': 'haunt'},
    {'t': 20, 'a': 'mana', 'n': 250}, {'t': 21, 'a': 'path', 'kind': 'tunnel', 'p': '?'},
    {'t': 50, 'a': 'order', 'u': 'army', 'p': '@path'},
  ],
  'battle': lambda P: [
    {'t': 0.5, 'a': 'spawn', 'p': P['q1'], 'troops': {'d-sword': 4}},
    {'t': 1, 'a': 'order', 'u': 'army', 'p': P['q1']},
    {'t': 40, 'a': 'give', 'gold': 2000, 'wood': 500, 'food': 500},
    {'t': 40, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'd-sword'},
    {'t': 40, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'd-spear'},
    {'t': 41, 'a': 'spawn', 'p': P['q1'], 'troops': {'d-sword': 12}},
    {'t': 100, 'a': 'order', 'u': 'army', 'p': P['q1']},
    {'t': 125, 'a': 'retreat'},
  ],
  'armory': lambda P: [
    {'t': 0.5, 'a': 'give', 'gold': 3000, 'wood': 500, 'food': 500},
    {'t': 1, 'a': 'design', 'spec': {'name': 'Round Spearman', 'type': 'inf', 'weapon': 'spear', 'shield': 'round', 'armor': 'leather1'}},
    {'t': 2, 'a': 'tord', 'mix': {'d-sword': 2, 'd-spear': 1, 'd2': 2}, 'p': 'cap'},
    {'t': 3, 'a': 'retrofit', 'to': 'd2'},
    {'t': 150, 'a': 'wounds', 'n': 40},
    {'t': 170, 'a': 'tord', 'mix': {'d-club': 1}, 'p': P['q1']},
  ],
  'battlemagic': lambda P: [
    {'t': 0.5, 'a': 'grant', 'id': 'school-life'}, {'t': 0.5, 'a': 'grant', 'id': 'skin'},
    {'t': 0.5, 'a': 'give', 'gold': 3000, 'wood': 1000, 'food': 1000},
    {'t': 0.6, 'a': 'build', 'u': 'mason', 'p': P['cap'], 'type': 'barracks'},
    {'t': 32, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'd-sword'},
    {'t': 32, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'd-sword'},
    {'t': 32, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'd-spear'},
    {'t': 32, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'd-club'},
    {'t': 32, 'a': 'train', 'src': 'barracks', 'p': P['cap'], 'kind': 'd-sword'},
    {'t': 110, 'a': 'spawn', 'p': P['q1'], 'troops': {'d-sword': 7}},
    {'t': 111, 'a': 'mana', 'n': 100},
    {'t': 112, 'a': 'order', 'u': 'army', 'p': P['q1']},
  ],
}
LEADER = {'armory': 'cormac', 'battle': 'cormac', 'battlemagic': 'havva', 'life': 'havva', 'arcane': 'alma', 'death': 'niall', 'orders': 'havva', 'auto': 'aithne', 'train': 'cormac', 'research': 'finn', 'magic': 'havva', 'roads': 'havva', 'develop': 'finn'}
FRAMES_OF = {'develop': 6201}

RUN = r"""(() => {
  const acts = %s, frames = %d, snaps = [];
  const U = { wf: () => S.units.find(u => u.kind === WAYFINDER), mason: () => S.units.find(u => u.kind === MASON), army: () => S.units.find(u => u.kind === 'army' && u.owner === ME) };
  const log = []; const t0 = toast; toast = function (m) { log.push([Math.round(S.t * 10) / 10, String(m).replace(/<[^>]+>/g, '')]); };
  const snap = () => snaps.push({ t: S.t, stock: { ...S.stock }, income: { ...income },
    battles: S.battles.map(b => [b.prov, b.defender, { ...b.lost }]), wounds: S.units.map(u => u.wounds === undefined ? null : Math.round(u.wounds * 1e6) / 1e6),
    units: S.units.map(u => ({ owner: u.owner, kind: u.kind, prov: u.prov, x: u.x, y: u.y, moving: !!u.moving, slot: u.slot, scouting: u.scouting === undefined ? null : u.scouting,
      survey: !!u.survey, build: u.build ? u.build.type : null, pending: u.pending ? u.pending.type : null, queue: u.surveyQueue.length, troops: u.troops ? { ...u.troops } : null })),
    queues: Object.keys(S.queues).sort().map(k => [k, S.queues[k].map(q => [q.kind, q.t0])]),
    explored: [...S.explored].sort((a, b) => a - b), visible: [...S.visible].sort((a, b) => a - b),
    surveyed: [...S.surveyed.keys()].sort((a, b) => a - b), wf: [...S.wf].sort((a, b) => a - b),
    buildings: [...S.buildings].map(([p, b]) => [p, b.stage]).sort((a, b) => a[0] - b[0]),
    extras: [...S.extras].map(([p, l]) => [p, l.map(e => [e.type, e.slot])]).sort((a, b) => a[0] - b[0]),
    upgrades: [...S.upgrades.keys()], techs: S.tech.gov.done.length + S.tech.mil.done.length + S.tech.mag.done.length,
    tech: Object.fromEntries(TREE_KEYS.map(k => [k, { cur: S.tech[k].cur, prog: S.tech[k].prog, bank: S.tech[k].bank, done: S.tech[k].done.slice(), tier: S.tech[k].tier }])),
    mana: S.units.map(u => u.mana === undefined ? null : u.mana), casts: S.units.map(u => u.cast ? u.cast.spell : null),
    cd: Object.keys(S.cd).sort().map(k => [k, S.cd[k]]), paths: Object.keys(S.paths).sort().map(k => [+k, S.paths[k]]),
    eyes: (S.eyes || []).map(r => [r.a, r.b, r.until]), haunts: (S.haunts || []).map(h => [h.prov, h.until]), reveals: (S.reveals || []).length, harvest: !!S.harvest,
    rep: { ...S.rep }, xup: [...S.xup.keys()], roads: [...S.roads].sort(), walls: [...S.walls].sort((a, b) => a - b),
    devel: [...S.devel].map(([p, r]) => [p, r.lv, r.job ? Math.round(r.job.done * 1000) / 1000 : null]), yields: yields.map(y => [y.gold, y.wood, y.food, !!y.deposit]), levels: [...S.extras].map(([p, l]) => [p, l.map(e => e.level || 1)]).sort((a, b) => a[0] - b[0]),
    finds: [...S.finds].map(([p, f]) => [p, f.id, !!f.done]),
    orders: (S.trainOrders || []).map(O => [O.id, O.done, O.total, O.rally.prov]),
    retro: S.units.map(u => u.retro ? [u.retro.kind, u.retro.t0, u.retro.dur] : u.retroWant ? ['want', u.retroWant.to, u.retroWant.prov] : null),
    rest: S.units.map(u => u.rest ? [u.rest.t0, u.rest.dur] : null),
    designs: S.designs.filter(d => (d.race || 'realm') === 'realm').map(d => [d.id, d.name, DSTATS[d.id].atk, DSTATS[d.id].hp, Math.round(DSTATS[d.id].red * 1e9) / 1e9, DSTATS[d.id].speed]) });
  let k = 0;
  for (let i = 0; i < frames; i++) {
    while (k < acts.length && S.t >= acts[k].t) {
      const A = acts[k++], u = A.u ? U[A.u]() : null;
      if (A.a === 'survey') { u.surveyQueue.push(A.p); }
      else if (A.a === 'order') { if (A.p === '@path') A.p = window.__pathTo; if (A.p >= 0) order(u, A.p); }
      else if (A.a === 'build') orderBuild(u, A.p, A.type);
      else if (A.a === 'upgrade') startUpgrade(A.p);
      else if (A.a === 'give') { for (const r of RES) S.stock[r] += A[r]; }
      else if (A.a === 'train') { S.selKind = A.src; S.selBuilding = A.p; train(A.kind); }
      else if (A.a === 'pick') {
        // '?': the first technology on the tree's list (by id) that costs no gold; the choice is recorded for the test
        const st = S.tech[A.tree];
        if (A.id === '?') { const c = availTechs(A.tree).filter(x => !x.gold && x.id !== 'abandon').map(x => x.id).sort()[0]; A.id = c === undefined ? null : c; }
        if (A.id) { if (!st.opts.includes(A.id)) st.opts.push(A.id); pickTech(A.id); }
      }
      else if (A.a === 'points') addResearch(A.tree, A.n);
      else if (A.a === 'grant') grantTech(A.id);
      else if (A.a === 'mana') { U.army().mana = A.n; }
      else if (A.a === 'spawn') { const g = spawnBandit(A.p); g.troops = { ...A.troops }; }
      else if (A.a === 'retreat') { const a = S.units.find(v => v.kind === 'army' && v.owner === ME && v.battle); if (a) retreat(a); }
      else if (A.a === 'cast') castSpell(U.army(), A.k);
      else if (A.a === 'aim') {
        const c = U.army();
        if (A.p === '?') { const l = A.k === 'eyes' ? seeNbrs(c, 'eyes') : []; A.p = l.length ? l[0] : -1; }
        if (A.p >= 0) AIMED[A.k](c, A.p);
      }
      else if (A.a === 'path') {
        // '?': the first neighbour across a border of trees (forest) or mountains (tunnel), recorded for the test
        const c = U.army(), st = A.kind === 'forest' ? 'trees' : 'mountains';
        if (A.p === '?') { const q = allNbr[c.prov].find(q => edgeBetween(c.prov, q, st, false) >= 0); A.p = q === undefined ? -1 : q; }
        window.__pathTo = A.p;
        if (A.p >= 0) startPath(c, A.p, A.kind, false);
      }
      else if (A.a === 'link') {
        // '?': the first explored open neighbour of the Mason's province other than the capital (recorded for the test)
        if (A.p === '?') { const c = openNbr[u.prov].map(n => n.q).find(q => q !== S.capital && S.explored.has(q)); A.p = c === undefined ? -1 : c; }
        if (A.p >= 0) startLink(u, A.p, A.type);
      }
      else if (A.a === 'develop') startDevelop(A.p);
      else if (A.a === 'design') { const d = addDesign({ ...A.spec }); A.id = d.id; }
      else if (A.a === 'tord') { TO.draft = { ...A.mix }; TO.rally = A.p === 'cap' ? S.capital : A.p; purchaseOrder(); }
      else if (A.a === 'retrofit') retrofitArmies([U.army()], A.to);
      else if (A.a === 'wounds') { U.army().wounds = A.n; }
      else if (A.a === 'split') splitArmy(U.army());
      else if (A.a === 'combine') combineArmies(S.units.filter(v => v.kind === 'army' && v.owner === ME && v.prov === U.army().prov));
      else if (A.a === 'destroy') { const e = extrasIn(A.p).find(x => x.type === A.type); S.extras.set(A.p, extrasIn(A.p).filter(x => x !== e)); S.xup.delete(A.p + '@' + e.slot); computeIncome(); }
      else if (A.a === 'xup') { const e = extrasIn(A.p).find(x => x.type === A.type); S.selProv = A.p; S.selPart = A.type + '@' + e.slot; startXup(A.p, S.selPart); }
    }
    update(1 + i * 0.1);
    if (i %% 10 === 0) snap();
  }
  toast = t0;
  return JSON.stringify({ snaps, log, applied: acts });
})()"""

async def main():
    OUT.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as p:
        b = await p.chromium.launch(); pg = await b.new_page()
        await pg.add_init_script("localStorage.setItem('realm-intro-seen','1'); window.requestAnimationFrame = () => 0;")
        await pg.goto('http://localhost:8777/realmlings_play.html'); await pg.wait_for_timeout(800)
        for seed in SEEDS:
            for sc in [a for a in (sys.argv[1:] or ['orders', 'auto', 'train', 'research', 'magic', 'roads', 'develop', 'life', 'arcane', 'death'])]:
                await pg.reload(); await pg.wait_for_timeout(600)
                plan = json.loads(await pg.evaluate("s => window.__evalIn(s)", SETUP % (json.dumps(seed), json.dumps(LEADER[sc]))))
                acts = ACTIONS[sc](plan)
                if sc == 'develop':   # development's lucky finds use Math.random: never lucky here
                    await pg.evaluate("s => window.__evalIn(s)", "Math.random = () => 0.99")
                if sc.startswith('battle'):   # battles roll Math.random: pinned to 0.5 (the Godot test does the same)
                    await pg.evaluate("s => window.__evalIn(s)", "Math.random = () => 0.5")
                res = json.loads(await pg.evaluate("s => window.__evalIn(s)", RUN % (json.dumps(acts), FRAMES_OF.get(sc, FRAMES))))
                res['actions'] = res.pop('applied')   # with the '?' picks filled in
                out = {'seed': seed, 'scenario': sc, 'leader': LEADER[sc], 'plan': plan, 'frames': FRAMES_OF.get(sc, FRAMES), **res}
                (OUT / f"{seed.replace(' ', '_')}_{sc}.json").write_text(json.dumps(out, indent=0))
                last = res['snaps'][-1]
                print(seed, sc, plan, 'stock', last['stock'], 'bld', last['buildings'], 'ex', last['extras'], 'surv', last['surveyed'], 'expl', last['explored'])
                for t, m in res['log'][:14]: print('   ', t, m[:110])
        await b.close()

asyncio.run(main())
