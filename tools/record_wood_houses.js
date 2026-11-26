// Record the web game's Woodling tree houses (woodbld.js treeHouse, drawn as content.js houseSprite does) as canvas
// command lists, for tools/make_wood_houses.py to draw. Runs the web code itself, unchanged but for one thing: the
// leafy crown may take a color of its own (root.__CROWN), so a home can wear its nation's accent color on its leaves.
// usage: node tools/record_wood_houses.js <web folder> <out.json> '<jobs json: [[look, door|null, crown|null], ...]>'
const fs = require('fs'), vm = require('vm');
const [WEB, OUT, JOBS] = process.argv.slice(2);
function recorder() {
  const log = [];
  return new Proxy({}, {
    get(t, k) {
      if (k === '_log') return log;
      if (k === 'createLinearGradient')
        return (...a) => { const gr = { gradient: 'linear', args: a, stops: [] }; gr.addColorStop = (o, c) => gr.stops.push([o, c]); return gr; };
      if (k in t) return t[k];
      return (...a) => { log.push([k, ...a]); };
    },
    set(t, k, v) { t[k] = v; log.push(['set', k, typeof v === 'object' ? { gradient: v.gradient, args: v.args, stops: v.stops } : v]); return true; }
  });
}
const sb = { Math, console, parseInt, Number, String, Array, Object, JSON, isNaN, isFinite };
sb.window = sb; sb.root = sb; sb.globalThis = sb; sb.self = sb;
sb.document = { createElement: () => ({ getContext: () => recorder() }) };
vm.createContext(sb);
vm.runInContext(fs.readFileSync(WEB + '/buildings.js', 'utf8'), sb);
let wood = fs.readFileSync(WEB + '/woodbld.js', 'utf8');
const was = 'clump(g, cx2, cy2 - T.s * 0.45, T.s, 100 + v, door || T.leaf, door ? shade(door, 0.35) : T.hi, t);';
if (!wood.includes(was)) throw new Error('woodbld.js treeHouse has changed: update record_wood_houses.js');
wood = wood.replace(was, 'const crown = root.__CROWN || door; clump(g, cx2, cy2 - T.s * 0.45, T.s, 100 + v, crown || T.leaf, crown ? shade(crown, 0.35) : T.hi, t);');
vm.runInContext(wood, sb);
const out = [];
for (const [v, door, crown] of JSON.parse(JOBS)) {
  const g = recorder();
  sb.__CROWN = crown || null;
  // content.js houseSprite: a 100 x 100 canvas at 4x, origin (50, 70); a Woodling home moved down 4 and at 0.82
  g.scale(4, 4); g.translate(50, 70); g.lineJoin = 'round'; g.lineCap = 'round';
  g.translate(0, 4); g.scale(0.82, 0.82);
  sb.WoodBuild.treeHouse(g, 0, 0, v, door || null, 0);
  out.push(g._log);
}
fs.writeFileSync(OUT, JSON.stringify(out));
