// Runs inside a started Realmlings web game (v106 + the v999 dump snippet), through window.__evalIn so it can
// reach the game's own drawing functions. Renders each piece of art onto a transparent canvas, crops it, and
// returns { file, png (data URL), w, h, ax, ay, scale, ... } where (ax, ay) is the anchor pixel: the point the
// game draws the art at (province center, building plot, unit feet), and scale is image pixels per world unit.
// Driven by tools/export_art.py.
(() => {
  const PROBE = 2400;
  const cv = document.createElement('canvas'); cv.width = cv.height = PROBE;
  const g = cv.getContext('2d', { willReadFrequently: true });
  // draw fn (in world units, origin = anchor) at `scale` px per world unit, crop to the painted pixels
  function shoot(file, scale, fn, extra) {
    g.setTransform(1, 0, 0, 1, 0, 0); g.clearRect(0, 0, PROBE, PROBE);
    g.translate(PROBE / 2, PROBE * 0.62); g.scale(scale, scale); g.lineJoin = 'round'; g.lineCap = 'round';
    try { fn(g); } catch (e) { return { file, error: String(e) }; }
    g.setTransform(1, 0, 0, 1, 0, 0);
    const d = g.getImageData(0, 0, PROBE, PROBE).data;
    let x0 = PROBE, y0 = PROBE, x1 = -1, y1 = -1;
    for (let y = 0; y < PROBE; y++) for (let x = 0; x < PROBE; x++) if (d[(y * PROBE + x) * 4 + 3] > 2) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    if (x1 < 0) return { file, error: 'empty' };
    x0 = Math.max(0, x0 - 2); y0 = Math.max(0, y0 - 2); x1 = Math.min(PROBE - 1, x1 + 2); y1 = Math.min(PROBE - 1, y1 + 2);
    const w = x1 - x0 + 1, h = y1 - y0 + 1, out = document.createElement('canvas'); out.width = w; out.height = h;
    out.getContext('2d').drawImage(cv, x0, y0, w, h, 0, 0, w, h);
    return Object.assign({ file, png: out.toDataURL('image/png'), w, h, ax: PROBE / 2 - x0, ay: Math.round(PROBE * 0.62) - y0, scale }, extra || {});
  }
  const icon = (file, c, extra) => Object.assign({ file, png: c.toDataURL('image/png'), w: c.width, h: c.height, ax: c.width / 2, ay: c.height / 2, scale: 1 }, extra || {});
  const snake = s => String(s).replace(/[^A-Za-z0-9]+/g, '_').replace(/^_|_$/g, '').toLowerCase();
  const E = s => window.__evalIn(s);
  const KB = E('KB'), EB = E('EB'), UK = E('UK'), HOUSE_K = E('HOUSE_K'), BUILD_DEFS = E('BUILD_DEFS'), RES = E('RES');
  const settleArt = E('settleArt'), bldArt = E('bldArt'), drawUnitFor = E('drawUnitFor'), houseSprite = E('houseSprite');
  const resIcon = E('resIcon'), techIcon = E('techIcon'), buildThumb = E('buildThumb'), xIcon = E('xIcon'), TECHS = E('TECHS');
  const MONSTERS = E('typeof MONSTERS !== "undefined" ? MONSTERS : {}'), drawMonster = E('typeof drawMonster === "function" ? drawMonster : null');
  const ME = E('ME'), UNITK = UK * 1.5;
  const R = window.__RACE || 'realm', mine = x => !x || x === R || (Array.isArray(x) && x.includes(R));
  const UNIT_IDS = { realm: ['pioneer:B', 'mason:A', 'mage:A', 'd-sword', 'd-spear', 'd-club', 'd-rider', 'rng-realm', 'thug:A'], swamp: ['pioneer:B', 'mason:A', 'mage:A', 'd-sw-spear', 'd-sw-axe', 'd-sw-club', 'd-sw-ogre', 'rng-swamp', 'thug:A'], wood: ['pioneer:B', 'mason:A', 'mage:A', 'd-wd-sword', 'd-wd-spear', 'd-wd-club', 'd-wd-champ', 'rng-wood', 'wd-elem'] }[R];
  const DIRS = [['d0', 0], ['d1', -Math.PI / 4], ['d2', -Math.PI / 2], ['d3', -3 * Math.PI / 4], ['d4', Math.PI], ['d5', 3 * Math.PI / 4], ['d6', Math.PI / 2], ['d7', Math.PI / 4]];
  const jobs = {
    settlements: () => {
      const out = [];
      for (const st of [0, 1, 2]) for (const ter of ['grassland', 'forest', 'desert', 'swamp']) for (let v = 0; v < 10; v++)
        out.push(shoot(`settlements/${R}/${['outpost', 'fort', 'capital'][st]}_${ter}_v${v}.png`, 3, c => { c.scale(KB, KB); settleArt(c, st, 0, { variant: v, terrain: ter }, R); }, { stage: st, terrain: ter, variant: v }));
      return out;
    },
    buildings: () => {
      const out = [];
      for (const [type, D] of Object.entries(BUILD_DEFS)) {
        if (!mine(D.race)) continue;
        const vs = D.levels ? D.levels.map((_, i) => ['lv' + (i + 1), i]) : [['v' + (D.variant || 0), D.variant || 0]];
        for (const [vn, vi] of vs) {
          out.push(shoot(`buildings/${R}/${snake(type)}_${vn}.png`, 3, c => { c.scale(EB, EB); bldArt(c, type, vi, 0, 1, R); }, { type, variant: vn }));
          for (const r of [0.25, 0.5, 0.75]) out.push(shoot(`buildings/${R}/${snake(type)}_${vn}_rise${Math.round(r * 100)}.png`, 3, c => { c.scale(EB, EB); bldArt(c, type, vi, 0, r, R); }, { type, variant: vn, rise: r }));
        }
      }
      return out;
    },
    // building animation frames (smoke, flags, water wheels, orbiting crystals, sparkles): BLD_FRAMES frames over
    // BLD_LOOP seconds (two puffs of chimney smoke; the Mage Tower's crystals go round once)
    bldanim: () => {
      const out = [], N = 32, LOOP = 2 * (1 / 0.35);
      for (const [type, D] of Object.entries(BUILD_DEFS)) {
        if (!mine(D.race)) continue;
        const vs = D.levels ? D.levels.map((_, i) => ['lv' + (i + 1), i]) : [['v' + (D.variant || 0), D.variant || 0]];
        for (const [vn, vi] of vs) for (let f = 0; f < N; f++)
          out.push(shoot(`buildings/${R}/${snake(type)}_${vn}_a${String(f).padStart(2, '0')}.png`, 3, c => { c.scale(EB, EB); bldArt(c, type, vi, f * LOOP / N, 1, R); }, { type, variant: vn, frame: f, frames: N, loop: LOOP }));
      }
      return out;
    },
    units: () => {
      const out = [], ids = UNIT_IDS;
      for (const id of ids) for (const [dn, th] of DIRS) out.push(shoot(`units/${R}/${snake(id)}_${dn}.png`, 4, c => drawUnitFor(c, id, ME, false, th, 0, 0, 0, UNITK), { id, dir: dn, th }));
      return out;
    },
    monsters: () => {
      const out = []; if (!drawMonster) return out;
      // monsters only flip left/right: d2 (facing left) and d6 (facing right)
      for (const id of Object.keys(E('MON_ART'))) for (const [dn, th] of [DIRS[2], DIRS[6]]) out.push(shoot(`units/common/monster_${snake(id)}_${dn}.png`, 4, c => drawMonster(c, id, th, 0, 0, 0, UNITK), { id, dir: dn, th }));
      return out;
    },
    houses: () => {
      const out = [], n = E('HOUSE_LOOKS').length;
      for (let v = 0; v < n; v++) for (const roof of [null, '#3f72d9']) {
        const s = houseSprite(v, roof, R), k = HOUSE_K;
        out.push(shoot(`houses/${R}/house_v${v}${roof ? '_owned' : ''}.png`, 3, c => c.drawImage(s, -50 * k, -70 * k, 100 * k, 100 * k), { variant: v, owned: !!roof }));
      }
      return out;
    },
    icons: () => {
      const out = [];
      if (R === 'realm') for (const k of RES) { const c = document.createElement('canvas'); c.width = c.height = 80; resIcon(c.getContext('2d'), k, 40, 42, 3.4); out.push(icon(`icons/common/res_${k}.png`, c, { res: k })); }
      for (const t of TECHS) { if (!mine(t.race)) continue;   // (a race list such as ['realm', 'wood'] includes the Realmlings)
        try { const c = techIcon(t.id); if (c && c.toDataURL) out.push(icon(`icons/${R}/tech_${snake(t.id)}.png`, c, { tech: t.id })); else if (typeof c === 'string') out.push({ file: `icons/${R}/tech_${snake(t.id)}.png`, png: c.startsWith('data:image/png') ? c : (() => { const im = new Image(); im.src = c; const k = document.createElement('canvas'); k.width = k.height = 88; k.getContext('2d').drawImage(im, 0, 0, 88, 88); return k.toDataURL(); })(), ax: 44, ay: 44, scale: 1, tech: t.id }); else out.push({ file: `icons/${R}/tech_${snake(t.id)}.png`, error: 'type ' + typeof c }); } catch (e) { out.push({ file: `icons/${R}/tech_${snake(t.id)}.png`, error: String(e) }); } }
      for (const type of Object.keys(BUILD_DEFS)) { if (!mine(BUILD_DEFS[type].race)) continue; try { const u = buildThumb(type); out.push({ file: `icons/${R}/build_${snake(type)}.png`, png: typeof u === 'string' ? u : u.toDataURL(), ax: 0, ay: 0, scale: 1, type }); } catch (e) { out.push({ file: `icons/${R}/build_${snake(type)}.png`, error: String(e) }); } }
      if (R === 'realm') for (const kind of Object.keys(E('XICON')).concat(['dismiss', 'destroy', 'road', 'wall', 'rally', 'survey', 'gate', 'bridge', 'rewalls', 'demolish', 'upgrade'])) {
        try { const u = xIcon(kind); if (u) out.push({ file: `icons/common/cmd_${snake(kind)}.png`, png: typeof u === 'string' ? u : u.toDataURL(), ax: 0, ay: 0, scale: 1, kind }); } catch (e) {}
      }
      return out;
    }
  };
  // the interface's icons, as the web game's command card, outliner and province panel show them: unit portraits,
  // settlement and building thumbnails, and every command's icon (cmdInfo(id).icon with a unit of that kind selected)
  jobs.uiicons = async () => {
    const out = [];
    const toPng = async u => {
      if (!u) return null;
      if (u.toDataURL) return u.toDataURL();
      if (typeof u === 'string' && u.startsWith('data:image/png')) return u;
      const im = new Image(); im.src = u; await im.decode();
      const w = im.naturalWidth || 88, h = im.naturalHeight || 88, s = Math.max(1, 176 / Math.max(w, h));
      const k = document.createElement('canvas'); k.width = Math.round(w * s); k.height = Math.round(h * s); k.getContext('2d').drawImage(im, 0, 0, k.width, k.height); return k.toDataURL();
    };
    const put = async (file, get, extra) => {
      try { const png = await toPng(get()); if (!png) return out.push({ file, error: 'none' }); out.push(Object.assign({ file, png, ax: 0, ay: 0, scale: 1 }, extra || {})); }
      catch (e) { out.push({ file, error: String(e) }); }
    };
    const portrait = E('portrait'), settlementThumb = E('settlementThumb'), buildThumb = E('buildThumb'), xIcon = E('xIcon'), cmdInfo = E('cmdInfo');
    for (const k of ['army', ...UNIT_IDS, 'm-ent', 'm-zombie', 'm-jackal'])
      await put(`icons/${R}/unit_${snake(k)}.png`, () => portrait(k), { kind: k });
    for (const st of [0, 1, 2]) await put(`icons/${R}/settle_${st}.png`, () => settlementThumb(st), { stage: st });
    for (const type of Object.keys(BUILD_DEFS)) {
      const d = BUILD_DEFS[type]; if (!mine(d.race) || !d.levels) continue;
      for (let lv = 1; lv <= d.levels.length; lv++) await put(`icons/${R}/build_${snake(type)}_l${lv}.png`, () => buildThumb(type, lv), { type, level: lv });
    }
    if (R === 'realm') for (const [file, fn] of [['dev', 'devIcon()'], ['rally', 'rallyIcon()'], ['autobld_off', 'autoBldIcon(null)'], ['follow', 'followIco()'], ['rows', 'rowsIcon()'],
      ['slippers', "artIcon('slippers')"], ['crop_all', 'cropAllIcon()'], ['crop_ok', 'cropOkIcon()'], ['crop_staple', "cropIcon('staple')"], ['crop_cash', "cropIcon('cash')"], ['crop_fiber', "cropIcon('fiber')"], ['thug', 'thugIcon()']])
      await put(`icons/common/ui_${file}.png`, () => E(fn), {});
    if (R === 'realm') for (const kind of ['retrofit', 'rest', 'path', 'inspect', 'shock', 'quake', 'rewall', 'split', 'combine', 'retreat', 'cancel', 'fly'])
      await put(`icons/common/cmd_${snake(kind)}.png`, () => xIcon(kind), { kind });
    // the leaders' portraits (New Game page, country window)
    const LEADERS = E('LEADERS'), portraitOf = E('portraitOf');
    for (const id of Object.keys(LEADERS)) if (LEADERS[id].race === R) await put(`icons/${R}/leader_${snake(id)}.png`, () => portraitOf(id), { leader: id });
    // the Armory's gear (every weapon, Mage weapon, shield, armor and horse), the Diplomacy window's action icons,
    // the artifacts
    const equipIcon = E('equipIcon');
    for (const [kind, table] of [['weapon', 'WEAPONS'], ['weapon', 'MAGE_WEAPONS'], ['shield', 'SHIELD_DEFS'], ['armor', 'ARMORS'], ['horse', 'HORSES']])
      for (const k of Object.keys(E(table))) { const it = E(table)[k]; if (it.race && R === 'realm' && !mine(it.race)) continue; await put(`icons/common/gear_${kind === 'horse' && R === 'swamp' ? 'ogre' : kind}_${snake(k)}.png`, () => equipIcon(kind, k), { kind, key: k }); }
    const DX_ICON = E('DX_ICON'), dxIconURL = E('dxIconURL');
    if (R === 'realm') for (const k of Object.keys(DX_ICON)) await put(`icons/common/dx_${snake(k)}.png`, () => dxIconURL(k), { dx: k });
    const ARTIFACTS = E('ARTIFACTS'), artIcon = E('artIcon');
    if (R === 'realm') for (const k of Object.keys(ARTIFACTS)) await put(`icons/common/art_${snake(k)}.png`, () => artIcon(k), { artifact: k });
    // every command of the card, with a unit of its kind selected
    const CMD = E('CMD'), S = E('S'), ME = E('ME');
    const keep = S.selected;
    for (const kind of Object.keys(CMD)) {
      let u = S.units.find(v => v.owner === ME && v.kind === kind);
      if (!u) { const m = S.units.find(v => v.owner === ME && v.kind === E('MASON')); u = Object.assign({}, m, { kind }); }
      S.selected = [u];
      for (const a of CMD[kind]) await put(`icons/${R === 'realm' ? 'common' : R}/cmd_${snake(a.id)}.png`, () => cmdInfo(a.id).icon, { id: a.id });
    }
    S.selected = keep;
    return out;
  };
  window.__exportArt = name => jobs[name]();
  window.__exportArtJobs = Object.keys(jobs);
})();
