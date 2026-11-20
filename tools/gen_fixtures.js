// Writes the web generator's output for a list of seeds, for tests/test_world_gen.gd to compare against.
// node tools/gen_fixtures.js  (run from the repository root)
const fs = require('fs'), path = require('path');
const G = require(path.join(__dirname, '..', 'reference', 'web-v106', 'gen.js'));
const seeds = ['ember', 'oak', 'river', 'banner', 'moss', 'crown', 'lantern', 'stone', 'harbor', 'thistle', 'Practice', 'a', 'zz9', 'Realm 42', 'kettle', 'saffron'];
const out = path.join(__dirname, '..', 'tests', 'fixtures');
fs.mkdirSync(out, { recursive: true });
for (const s of seeds) {
  const t0 = Date.now(), w = G.generatePractice(s), ms = Date.now() - t0;
  const keep = { seed: s, attempts: w.attempts, center: w.center, W: w.W, H: w.H,
    provinces: w.provinces.map(p => ({ site: p.site, verts: p.verts, terrain: p.terrain, nbr: p.nbr, edges: p.edges, coast: p.coast })),
    edges: w.edges, junctions: w.junctions,
    vertices: [...new Set(w.provinces.flatMap(p => p.verts))].sort((a, b) => a - b).map(v => [v, w.vertices[v]]) };
  fs.writeFileSync(path.join(out, 'practice_' + s.replace(/[^A-Za-z0-9]/g, '_') + '.json'), JSON.stringify(keep));
  console.log(s, 'attempts', w.attempts, ms + 'ms', 'verts', w.vertices.length);
}

// full-size worlds (the normal game): rivers, lakes and the unique provinces too
for (const s of ['ember', 'oak', 'river', 'banner', 'moss', 'crown']) {
  const t0 = Date.now(), w = G.generateWorld(s), ms = Date.now() - t0;
  const keep = { seed: s, attempts: w.attempts, center: w.center, W: w.W, H: w.H,
    provinces: w.provinces.map(p => ({ site: p.site, verts: p.verts, terrain: p.terrain, nbr: p.nbr, edges: p.edges, coast: p.coast })),
    edges: w.edges, junctions: w.junctions, rivers: w.rivers, lakes: w.lakes, unique: w.unique || null,
    vertices: [...new Set(w.provinces.flatMap(p => p.verts))].sort((a, b) => a - b).map(v => [v, w.vertices[v]]) };
  fs.mkdirSync(path.join(out, 'world'), { recursive: true });
  fs.writeFileSync(path.join(out, 'world', s + '.json'), JSON.stringify(keep));
  console.log('world', s, 'attempts', w.attempts, ms + 'ms', 'provinces', w.provinces.length, 'unique', JSON.stringify(w.unique));
}
