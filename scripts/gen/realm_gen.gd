class_name RealmGen
extends RefCounted
## The world generator, ported from the web game's gen.js (v106). Same seed, same island: tests/test_world_gen.gd
## compares the output with tests/fixtures/ written by the web generator. Keep every step, random draw and
## iteration order exactly as in gen.js; the section numbers below match its comments.
##
## Output dictionaries use the web field names: provinces [{id, site, verts, terrain, adj, nbr, edges, coast}],
## vertices [[x, y]], edges [{id, a, b, v, open, style}], rivers, junctions, lakes, center, W, H, ...
## Not ported yet: placeUniques (Death Mountain, Oasis, Heart of the Forest) and validate(); the Practice island
## needs neither.

const W := 9390.0
const H := 6976.0
const S := 286.0
const NPROV := 200
const MIN_EDGE := 40.0
const TERRAINS := ["grassland", "forest", "desert", "swamp"]
const DEFAULT_OPTS := {"shape": "classic", "pens": 2, "coves": 2, "trees": 0}


# ---------- Delaunay (Bowyer-Watson) ----------
# web: triangulate(). Same triangles in the same order as the web version: the web keeps survivors in order and
# appends new triangles, which is the order of creation, so a triangle's index here is its place in that order.
# A grid over circumcircles only narrows which triangles are tested; the test itself is the web's.
static func triangulate(px: PackedFloat64Array, py: PackedFloat64Array) -> Dictionary:
	var n := px.size()
	var T := _Tri.new(px, py)
	T.add(n, n + 1, n + 2)
	for i in n:
		T.insert(i)
	var out := {"a": PackedInt32Array(), "b": PackedInt32Array(), "c": PackedInt32Array(), "x": PackedFloat64Array(), "y": PackedFloat64Array()}
	for t in T.ta.size():
		if T.alive[t] == 1 and T.ta[t] < n and T.tb[t] < n and T.tc[t] < n:
			out.a.append(T.ta[t]); out.b.append(T.tb[t]); out.c.append(T.tc[t]); out.x.append(T.tx[t]); out.y.append(T.ty[t])
	return out


class _Tri:
	extends RefCounted
	const CS := 300.0
	var X: PackedFloat64Array
	var Y: PackedFloat64Array
	var ta := PackedInt32Array()
	var tb := PackedInt32Array()
	var tc := PackedInt32Array()
	var tx := PackedFloat64Array()
	var ty := PackedFloat64Array()
	var tr := PackedFloat64Array()
	var alive := PackedByteArray()
	var gx0: float
	var gy0: float
	var gw: int
	var gh: int
	var grid := []
	var bigs := PackedInt32Array()

	func _init(px: PackedFloat64Array, py: PackedFloat64Array) -> void:
		X = px.duplicate()
		Y = py.duplicate()
		var big := maxf(RealmGen.W, RealmGen.H) * 20.0
		X.append(RealmGen.W / 2 - big); Y.append(RealmGen.H / 2 - big)
		X.append(RealmGen.W / 2 + big); Y.append(RealmGen.H / 2 - big)
		X.append(RealmGen.W / 2); Y.append(RealmGen.H / 2 + big)
		var S := RealmGen.S
		gx0 = -S * 1.8 - CS
		gy0 = -S * 1.8 - CS
		gw = int(ceil((RealmGen.W + S * 3.6 + CS * 2) / CS)) + 1
		gh = int(ceil((RealmGen.H + S * 3.6 + CS * 2) / CS)) + 1
		grid.resize(gw * gh)
		for k in grid.size():
			grid[k] = PackedInt32Array()

	func add(a: int, b: int, c: int) -> void:
		var ax := X[a]; var ay := Y[a]; var bx := X[b]; var by := Y[b]; var cx := X[c]; var cy := Y[c]
		var d := 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
		var a2 := ax * ax + ay * ay
		var b2 := bx * bx + by * by
		var c2 := cx * cx + cy * cy
		var x := (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / d
		var y := (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / d
		var r2 := (ax - x) * (ax - x) + (ay - y) * (ay - y)
		var id := ta.size()
		ta.append(a); tb.append(b); tc.append(c); tx.append(x); ty.append(y); tr.append(r2); alive.append(1)
		var r := sqrt(r2) + 1.0
		if is_nan(r) or r > CS * 10.0:
			bigs.append(id)
			return
		var i0 := clampi(int(floor((x - r - gx0) / CS)), 0, gw - 1)
		var i1 := clampi(int(floor((x + r - gx0) / CS)), 0, gw - 1)
		var j0 := clampi(int(floor((y - r - gy0) / CS)), 0, gh - 1)
		var j1 := clampi(int(floor((y + r - gy0) / CS)), 0, gh - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var k := j * gw + i
				var cell: PackedInt32Array = grid[k]
				cell.append(id)
				grid[k] = cell

	func insert(i: int) -> void:
		var x := X[i]
		var y := Y[i]
		var k := clampi(int(floor((y - gy0) / CS)), 0, gh - 1) * gw + clampi(int(floor((x - gx0) / CS)), 0, gw - 1)
		var cell: PackedInt32Array = grid[k]
		var bad := PackedInt32Array()
		var live := PackedInt32Array()
		var live_big := PackedInt32Array()
		for t in bigs:
			if alive[t] == 0:
				continue
			live_big.append(t)
			var dx := x - tx[t]
			var dy := y - ty[t]
			if dx * dx + dy * dy < tr[t]:
				bad.append(t)
		bigs = live_big
		for t in cell:
			if alive[t] == 0:
				continue
			live.append(t)
			var dx := x - tx[t]
			var dy := y - ty[t]
			if dx * dx + dy * dy < tr[t]:
				bad.append(t)
		if live.size() < cell.size():
			grid[k] = live   # drop dead triangles from the cell we just scanned
		bad.sort()
		var em := {}
		for t in bad:
			alive[t] = 0
			var u := ta[t]; var v := tb[t]; var w := tc[t]
			_flip(em, u, v)
			_flip(em, v, w)
			_flip(em, w, u)
		for uv in em.values():
			add(uv[0], uv[1], i)

	static func _flip(em: Dictionary, u: int, v: int) -> void:
		var k := u * 100000 + v if u < v else v * 100000 + u
		if em.has(k):
			em.erase(k)
		else:
			em[k] = [u, v]


static func ekey(u: int, v: int) -> int:
	return u * 100000 + v if u < v else v * 100000 + u


# web: buildMesh()
static func build_mesh(px: PackedFloat64Array, py: PackedFloat64Array) -> Dictionary:
	var tris := triangulate(px, py)
	var nt: int = tris.a.size()
	var edge_tris := {}
	var pt_tris := []
	pt_tris.resize(px.size())
	for i in px.size():
		pt_tris[i] = []
	for ti in nt:
		var a: int = tris.a[ti]; var b: int = tris.b[ti]; var c: int = tris.c[ti]
		pt_tris[a].append(ti); pt_tris[b].append(ti); pt_tris[c].append(ti)
		for uv in [[a, b], [b, c], [c, a]]:
			var k := ekey(uv[0], uv[1])
			if not edge_tris.has(k):
				edge_tris[k] = []
			edge_tris[k].append(ti)
	for i in px.size():
		var x := px[i]
		var y := py[i]
		var l: Array = pt_tris[i]
		var keys := PackedFloat64Array()
		for t in l:
			keys.append(DMath.atan2(tris.y[t] - y, tris.x[t] - x))
		# stable insertion sort by angle (same order as the web's stable sort)
		for p in range(1, l.size()):
			var kv := keys[p]
			var tv = l[p]
			var q := p - 1
			while q >= 0 and keys[q] > kv:
				keys[q + 1] = keys[q]
				l[q + 1] = l[q]
				q -= 1
			keys[q + 1] = kv
			l[q + 1] = tv
	return {"tris": tris, "edge_tris": edge_tris, "pt_tris": pt_tris}


# web: polyCentroid(pts) -> [cx, cy, |area|]
static func poly_centroid(pts: Array) -> Array:
	var a := 0.0
	var cx := 0.0
	var cy := 0.0
	var m := pts.size()
	for i in m:
		var p0: Array = pts[i]
		var p1: Array = pts[(i + 1) % m]
		var f: float = p0[0] * p1[1] - p1[0] * p0[1]
		a += f
		cx += (p0[0] + p1[0]) * f
		cy += (p0[1] + p1[1]) * f
	a *= 0.5
	return [cx / (6.0 * a), cy / (6.0 * a), absf(a)]


static func dist_seg(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	var l2 := dx * dx + dy * dy
	var t := ((px - ax) * dx + (py - ay) * dy) / l2 if l2 != 0.0 else 0.0
	t = maxf(0.0, minf(1.0, t))
	return JS.hypot(px - ax - t * dx, py - ay - t * dy)


static func dist_polyline(px: float, py: float, pl: Array) -> float:
	var d := INF
	for i in pl.size() - 1:
		d = minf(d, dist_seg(px, py, pl[i][0], pl[i][1], pl[i + 1][0], pl[i + 1][1]))
	return d


static func ang_diff(a: float, b: float) -> float:
	var d := fmod(absf(a - b), 2.0 * PI)
	return 2.0 * PI - d if d > PI else d


## web: generateWorld(seed, opts, withUniques) without the validation report. With uniques (every normal game): Death
## Mountain, the Desert Oasis and the Heart of the Forest, and the next island is tried if any of them doesn't fit.
static func generate_world(seed: String, opts = null, with_uniques := false) -> Dictionary:
	var o := DEFAULT_OPTS.duplicate()
	if opts is Dictionary:
		o.merge(opts, true)
	var classic: bool = o.shape == "classic" and o.pens == 2 and o.coves == 2 and not o.trees
	var key := seed if classic else "%s|%s:%s:%s:%s" % [seed, o.shape, o.pens, o.coves, o.trees]
	var tries := 80 if classic else 160
	var reasons := {}
	for attempt in tries:
		var g := _Attempt.new(Mulberry32.from_string(key + "#" + str(attempt)), o)
		var r := g.run()
		if not r.ok:
			reasons[r.reason] = reasons.get(r.reason, 0) + 1
			continue
		r.world.seed = seed
		r.world.attempts = attempt + 1
		r.world.opts = o
		if with_uniques:
			place_uniques(r.world, seed)
			var U: Dictionary = r.world.unique
			if U.death < 0 or U.oasis < 0 or U.heart < 0:
				reasons["unique provinces"] = reasons.get("unique provinces", 0) + 1
				continue
		return r.world
	push_error("Could not generate a valid world: " + str(reasons))
	return {}


# web: gen.js placeUniques
static func place_uniques(w: Dictionary, seed: String) -> void:
	var rng := Mulberry32.from_string("unique:" + seed)
	var ps: Array = w.provinces
	var E: Array = w.edges
	var n := ps.size()
	var other := func(e: Dictionary, i: int) -> int: return e.b if e.a == i else e.a
	var inland := func(i: int) -> bool: return ps[i].coast.is_empty()
	var banned := {}
	var U := {"death": -1, "deathGuard": -1, "oasis": -1, "oasisGuard": -1, "heart": -1, "heartGuard": -1}
	var connected := func(closed: Dictionary, dead: int) -> bool:
		var start := 0 if dead != 0 else 1
		var seen := {start: true}
		var q := [start]
		while not q.is_empty():
			var u: int = q.pop_back()
			for id in ps[u].edges:
				var e: Dictionary = E[id]
				if not e.open or closed.has(id):
					continue
				var v: int = other.call(e, u)
				if v == dead or seen.has(v):
					continue
				seen[v] = true
				q.append(v)
		return seen.size() == n - (1 if dead >= 0 else 0)
	var order := func(list: Array) -> Array: return rng.shuffle(list.duplicate())
	# 1. Death Mountain: inland, not a desert, ideally with no desert or coastal neighbor
	var base := []
	for i in n:
		if inland.call(i) and ps[i].terrain != "desert" and ps[i].nbr.size() >= 4:
			base.append(i)
	base = order.call(base)
	var score := func(i: int) -> int:
		var s := 0
		for j in ps[i].nbr:
			if ps[j].terrain == "desert":
				s += 10
			if not inland.call(j):
				s += 1
		return s
	base = JS.stable_sort(base, func(x, y): return score.call(x) - score.call(y))
	for i in base:
		var closed := {}
		for id in ps[i].edges:
			closed[id] = true
		if not connected.call(closed, i):
			continue
		U.death = i
		for id in ps[i].edges:
			E[id].open = false
			E[id].style = "mountains"
		# a river along its side runs under the mountain there: cut that stretch out so the border shows mountains
		var dm := {}
		for id in ps[i].edges:
			var v: Array = E[id].v
			dm["%d_%d" % [mini(v[0], v[1]), maxi(v[0], v[1])]] = true
		var rivers := []
		for r in w.rivers:
			var cur := [r.verts[0]]
			for k in range(1, r.verts.size()):
				var a: int = r.verts[k - 1]
				var b: int = r.verts[k]
				if dm.has("%d_%d" % [mini(a, b), maxi(a, b)]):
					if cur.size() > 1:
						rivers.append({"verts": cur, "lake": null})
					cur = [b]
				else:
					cur.append(b)
			if cur.size() > 1:
				rivers.append({"verts": cur, "lake": r.lake})
		w.rivers = rivers
		var gl: Array = order.call(ps[i].nbr.duplicate())
		gl = JS.stable_sort(gl, func(x, y): return int(inland.call(y)) - int(inland.call(x)))
		var g: int = gl[0]
		U.deathGuard = g
		banned[i] = true
		for j in ps[i].nbr:
			banned[j] = true
		for j in ps[g].nbr:
			banned[j] = true
		break
	# 2 and 3: a ring of one terrain with a single way in
	var ringed := func(terrain: String, style: String, key: String) -> void:
		var cands := []
		for i in n:
			if ps[i].terrain == terrain and inland.call(i) and ps[i].nbr.size() >= 4 and not banned.has(i) and not ps[i].nbr.any(func(j): return banned.has(j)):
				cands.append(i)
		cands = order.call(cands)
		var same := func(i: int) -> float:
			return ps[i].nbr.filter(func(j): return ps[j].terrain == terrain).size() / float(ps[i].nbr.size())
		cands = JS.stable_sort(cands, func(x, y): return signf(same.call(y) - same.call(x)))
		for i in cands:
			var gs: Array = order.call(ps[i].nbr.filter(func(j): return not banned.has(j)))
			gs = JS.stable_sort(gs, func(x, y):
				var d := int(ps[y].terrain == terrain) - int(ps[x].terrain == terrain)
				return d if d != 0 else ps[y].nbr.size() - ps[x].nbr.size())
			for g in gs:
				var ent := -1
				for id in ps[i].edges:
					if other.call(E[id], i) == g:
						ent = id
						break
				if ent < 0:
					continue
				var closed := {}
				for id in ps[i].edges:
					if id != ent:
						closed[id] = true
				var was: bool = E[ent].open
				E[ent].open = true
				if not connected.call(closed, U.death):
					E[ent].open = was
					continue
				for id in ps[i].edges:
					if id != ent:
						E[id].open = false
						E[id].style = style
				E[ent].style = null
				for j in ps[i].nbr:
					if ps[j].terrain != terrain:
						ps[j].terrain = terrain
						if terrain == "desert":
							for id in ps[j].edges:
								var o: int = other.call(E[id], j)
								if o == i or o == U.death:
									continue
								E[id].open = true
								E[id].style = null
				U[key] = i
				U[key + "Guard"] = g
				banned[i] = true
				for j in ps[i].nbr:
					banned[j] = true
				for j in ps[g].nbr:
					banned[j] = true
				return
	ringed.call("desert", "palms", "oasis")
	ringed.call("forest", "trees", "heart")
	# junction fillers around the unique provinces follow their new borders
	var v_kind := {}
	if U.death >= 0:
		for v in ps[U.death].verts:
			v_kind[v] = "mountains"
	if U.oasis >= 0:
		for v in ps[U.oasis].verts:
			v_kind[v] = "palms"
	if U.heart >= 0:
		for v in ps[U.heart].verts:
			v_kind[v] = "trees"
	for j in w.junctions:
		if v_kind.has(j.v) and j.kind != "river":
			j.kind = v_kind[j.v]
	w.unique = U


## web: generatePractice(seed) — a small 10-province island cut from a normal world.
static func generate_practice(seed: String) -> Dictionary:
	var big := generate_world("practice:" + seed)
	var P: Array = big.provinces
	var rng := Mulberry32.from_string("practice-pick:" + seed)
	var want := {"grassland": 5, "forest": 3, "desert": 1, "swamp": 1}
	var N := 10
	var cx: float = big.center[0]
	var cy: float = big.center[1]
	var start := -1
	var bs := -INF
	for i in P.size():
		var p: Dictionary = P[i]
		if p.terrain != "grassland":
			continue
		var sc: float = p.nbr.size() * 600 - JS.hypot(p.site[0] - cx, p.site[1] - cy) + rng.next() * 50
		if sc > bs:
			bs = sc
			start = i
	var keep := [start]
	var in_k := {start: true}
	var dist_start := func(j: int) -> float: return JS.hypot(P[j].site[0] - P[start].site[0], P[j].site[1] - P[start].site[1])
	while keep.size() < N:
		var best := -1
		var bd := INF
		for i in keep:
			for j in P[i].nbr:
				if not in_k.has(j):
					var d: float = dist_start.call(j)
					if d < bd:
						bd = d
						best = j
		if best < 0:
			break
		keep.append(best)
		in_k[best] = true
	var terr := {start: "grassland"}
	var left := want.duplicate()
	left.grassland -= 1
	var rest: Array = keep.slice(1)
	var rkeys := {}
	for i in rest:
		rkeys[i] = -dist_start.call(i)   # farthest first
	JS.stable_sort(rest, func(a, b): return rkeys[a] - rkeys[b])
	for t in ["desert", "swamp"]:
		var pick = null
		for i in rest:
			if not terr.has(i) and P[i].terrain == t:
				pick = i
				break
		if pick == null:
			for i in rest:
				if not terr.has(i):
					pick = i
					break
		terr[pick] = t
		left[t] -= 1
	for i in rest:
		if not terr.has(i) and P[i].terrain == "forest" and left.forest > 0:
			terr[i] = "forest"
			left.forest -= 1
	var rev := rest.duplicate()
	rev.reverse()
	for i in rev:
		if not terr.has(i) and left.forest > 0:
			terr[i] = "forest"
			left.forest -= 1
	for i in rest:
		if not terr.has(i):
			terr[i] = "grassland"
	# re-index
	var idx := {}
	for k in keep.size():
		idx[keep[k]] = k
	var edges := []
	var e_map := {}
	for ei in big.edges.size():
		var e: Dictionary = big.edges[ei]
		if idx.has(e.a) and idx.has(e.b):
			e_map[ei] = edges.size()
			edges.append({"id": edges.size(), "a": idx[e.a], "b": idx[e.b], "v": e.v.duplicate(), "open": e.open, "style": e.style})
	var provinces := []
	for k in keep.size():
		var o: int = keep[k]
		var p: Dictionary = P[o]
		var vs: Array = p.verts
		var coast := []
		var inner := {}
		for ei in p.edges:
			if e_map.has(ei):
				var v: Array = big.edges[ei].v
				inner["%d_%d" % [mini(v[0], v[1]), maxi(v[0], v[1])]] = true
		for j in vs.size():
			var a: int = vs[j]
			var b: int = vs[(j + 1) % vs.size()]
			if not inner.has("%d_%d" % [mini(a, b), maxi(a, b)]):
				coast.append([a, b, 0])
		var nb := []
		for q in p.nbr:
			if idx.has(q):
				nb.append(idx[q])
		var pe := []
		for ei in p.edges:
			if e_map.has(ei):
				pe.append(e_map[ei])
		provinces.append({"id": k, "site": p.site.duplicate(), "verts": vs.duplicate(), "terrain": terr[o], "adj": nb.duplicate(), "nbr": nb, "edges": pe, "coast": coast})
	# borders: no barriers on the desert, no rivers, forests keep a tree border where they can
	for e in edges:
		var ta: String = provinces[e.a].terrain
		var tb: String = provinces[e.b].terrain
		if ta == "desert" or tb == "desert":
			e.open = true
			e.style = null
			continue
		if not e.open and e.style == "river":
			e.style = "trees" if (ta == "forest" or tb == "forest") else "mountains"
		if not e.open and (ta == "forest" or tb == "forest") and e.style == "mountains":
			e.style = "trees"
	var has_tree_border := func(i: int) -> bool:
		for ei in provinces[i].edges:
			if not edges[ei].open and edges[ei].style == "trees":
				return true
		return false
	for i in provinces.size():
		var p: Dictionary = provinces[i]
		if p.terrain != "forest" or has_tree_border.call(i):
			continue
		for ei in p.edges:
			var e: Dictionary = edges[ei]
			if provinces[e.b if e.a == i else e.a].terrain != "desert":
				e.open = false
				e.style = "trees"
				break
	var reach := func() -> Dictionary:
		var seen := {0: true}
		var q := [0]
		while q.size():
			var u: int = q.pop_back()
			for ei in provinces[u].edges:
				var e: Dictionary = edges[ei]
				if not e.open:
					continue
				var v: int = e.b if e.a == u else e.a
				if not seen.has(v):
					seen[v] = true
					q.append(v)
		return seen
	for guard in 40:
		var seen: Dictionary = reach.call()
		if seen.size() == N:
			break
		var cand := []
		for e in edges:
			if not e.open and seen.has(e.a) != seen.has(e.b):
				cand.append(e)
		JS.stable_sort(cand, func(x, y): return int(x.style == "trees") - int(y.style == "trees"))
		if cand.is_empty():
			break
		cand[0].open = true
		cand[0].style = null
	for i in provinces.size():
		var p: Dictionary = provinces[i]
		if p.terrain != "forest" or has_tree_border.call(i):
			continue
		for ei in p.edges:
			var e: Dictionary = edges[ei]
			if not e.open or provinces[e.b if e.a == i else e.a].terrain == "desert":
				continue
			e.open = false
			e.style = "trees"
			if reach.call().size() == N:
				break
			e.open = true
			e.style = null
	var used := {}
	for p in provinces:
		for v in p.verts:
			used[v] = true
	var sx := 0.0
	var sy := 0.0
	for p in provinces:
		sx += p.site[0]
	for p in provinces:
		sy += p.site[1]
	sx /= N
	sy /= N
	var junctions := []
	for j in big.junctions:
		if used.has(j.v):
			junctions.append(j)
	return {"W": big.W, "H": big.H, "center": [sx, sy], "provinces": provinces, "vertices": big.vertices, "edges": edges, "rivers": [], "junctions": junctions,
		"features": {"peninsulas": [], "coves": []}, "lakes": [], "lakesInland": true, "touchesEdgeOfWorld": false, "seed": "practice:" + seed, "practice": true, "attempts": big.attempts, "report": []}


# ---------------------------------------------------------------------------------------------------------------
# One generation attempt. web: tryGenerate(rng, o)
class _Attempt:
	extends RefCounted
	var rng: Mulberry32
	var o: Dictionary
	var px := PackedFloat64Array()
	var py := PackedFloat64Array()
	var frame := PackedByteArray()
	var N := 0
	var tris: Dictionary
	var edge_tris: Dictionary
	var pt_tris: Array
	var uf := PackedInt32Array()
	var rep_pos := {}
	var cell_v := []
	var sides := PackedInt32Array()
	var near_frame := PackedByteArray()
	var touch := []    # Array of Dictionary (sets)
	var border := []   # Array of Dictionary nb -> [ra, rb]
	var F := PackedFloat64Array()
	var land := PackedByteArray()
	var n_land := 0
	var is_lake := PackedByteArray()
	var lakes := []
	# shape
	var A := 0.0
	var B := 0.0
	var C := [0.0, 0.0]
	var harm := []
	var ph1 := 0.0
	var ph2 := 0.0
	var k_scale := 1.0
	var wob := 0.13
	var bite = null
	var hole = null
	var lobes := []
	var mean_r := 0.0
	var bite_c = null
	var pen_lines := []
	var cove_lines := []
	var strict := false

	func _init(r: Mulberry32, opts: Dictionary) -> void:
		rng = r
		o = opts

	func find(x: int) -> int:
		while uf[x] != x:
			uf[x] = uf[uf[x]]
			x = uf[x]
		return x

	func valid(i: int) -> bool:
		return frame[i] == 0 and near_frame[i] == 0 and sides[i] >= 5 and sides[i] <= 8

	func n_ang(th: float) -> float:
		var s := 0.0
		for h in harm:
			s += h[1] * DMath.sin(h[0] * th + h[2])
		return s

	func coast_r(th: float) -> float:
		var c := DMath.cos(th)
		var s := DMath.sin(th)
		return k_scale * (1.0 / sqrt((c / A) * (c / A) + (s / B) * (s / B))) * (1.0 + wob * n_ang(th))

	func in_hole(x: float, y: float) -> bool:
		if hole == null:
			return false
		var dx: float = x - C[0]
		var dy: float = y - C[1]
		var th := DMath.atan2(dy, dx)
		return JS.hypot(dx, dy) < coast_r(th) * hole.q * (1.0 + 0.08 * DMath.sin(3.0 * th + hole.ph))

	func shape_ok(th: float) -> bool:
		if bite != null and not (RealmGen.ang_diff(th, bite.th) > 1.35):
			return false
		for l in lobes:
			if not (RealmGen.ang_diff(th, l.th) > 0.6):
				return false
		return true

	func at(th: float, f: float) -> Array:
		return [C[0] + DMath.cos(th) * coast_r(th) * f, C[1] + DMath.sin(th) * coast_r(th) * f]

	func field(x: float, y: float) -> float:
		var dx: float = x - C[0]
		var dy: float = y - C[1]
		var th := DMath.atan2(dy, dx)
		var f := 1.0 - JS.hypot(dx, dy) / coast_r(th) + 0.04 * (DMath.sin(x / 273.0 + ph1) + DMath.sin(y / 238.0 + ph2))
		for l in lobes:
			var lx: float = C[0] + DMath.cos(l.th) * mean_r * l.d
			var ly: float = C[1] + DMath.sin(l.th) * mean_r * l.d
			f = maxf(f, 1.0 - JS.hypot(x - lx, y - ly) / (mean_r * l.r))
		if bite != null:
			f = minf(f, 1.4 * (JS.hypot(x - bite_c[0], y - bite_c[1]) / (mean_r * bite.r) - 1.0))
		if in_hole(x, y):
			return -5.0
		for p in pen_lines:
			var d := RealmGen.dist_polyline(x, y, p.line)
			if d < p.hw:
				f = maxf(f, 0.32 + 0.3 * (1.0 - d / p.hw))
		for c in cove_lines:
			if RealmGen.dist_polyline(x, y, c.line) < c.hw:
				f = -5.0
		return f

	func ocean_reach() -> PackedByteArray:
		var seen := PackedByteArray()
		seen.resize(N)
		var q := PackedInt32Array()
		for i in N:
			if frame[i]:
				seen[i] = 1
				q.append(i)
		while q.size():
			var u := q[q.size() - 1]
			q.resize(q.size() - 1)
			for w in border[u].keys():
				if not seen[w] and not land[w]:
					seen[w] = 1
					q.append(w)
		return seen

	func land_connected() -> bool:
		var s := -1
		for i in N:
			if land[i]:
				s = i
				break
		var seen := PackedByteArray()
		seen.resize(N)
		seen[s] = 1
		var q := PackedInt32Array([s])
		var c := 1
		while q.size():
			var u := q[q.size() - 1]
			q.resize(q.size() - 1)
			for w in border[u].keys():
				if land[w] and not seen[w]:
					seen[w] = 1
					c += 1
					q.append(w)
		return c == n_land

	func protected_cell(i: int) -> bool:
		for p in pen_lines:
			if RealmGen.dist_polyline(px[i], py[i], p.line) < p.hw:
				return true
		return false

	func no_corridors() -> bool:
		for i in N:
			if not land[i]:
				continue
			var nb := []
			for w in border[i].keys():
				if land[w]:
					nb.append(w)
			if nb.size() == 2 and not border[nb[0]].has(nb[1]):
				return false
		return true

	func near_lake(i: int) -> bool:
		for w in touch[i].keys():
			if is_lake[w]:
				return true
		return false

	func deep_cell(i: int) -> bool:
		if not land[i]:
			return false
		for w in touch[i].keys():
			if not land[w] and not is_lake[w]:
				return false
			for x in touch[w].keys():
				if not land[x] and not is_lake[x]:
					return false
		return true

	func axis_coords(i: int, th: float) -> Array:
		var dx: float = px[i] - C[0]
		var dy: float = py[i] - C[1]
		return [dx * DMath.cos(th) + dy * DMath.sin(th), -dx * DMath.sin(th) + dy * DMath.cos(th)]

	func fail(reason: String) -> Dictionary:
		return {"ok": false, "reason": reason}

	func run() -> Dictionary:
		# 1. points: hex-ish jittered grid + outer frame
		var row_h := S * 0.866
		var r := 0
		var y := row_h / 2.0
		while y < H - row_h / 3.0:
			var x := S if r % 2 else S / 2.0
			while x < W - S / 3.0:
				var jx := (rng.next() - 0.5) * S * 0.7
				var jy := (rng.next() - 0.5) * row_h * 0.7
				px.append(x + jx)
				py.append(y + jy)
				frame.append(0)
				x += S
			r += 1
			y += row_h
		for off in [S * 0.6, S * 1.8]:
			var x: float = -off
			while x <= W + off:
				px.append(x); py.append(-off)
				px.append(x); py.append(H + off)
				frame.append(1); frame.append(1)
				x += S
			var yy: float = -off + S
			while yy < H + off:
				px.append(-off); py.append(yy)
				px.append(W + off); py.append(yy)
				frame.append(1); frame.append(1)
				yy += S
		# 2. Lloyd relaxation
		for it in 2:
			var m := RealmGen.build_mesh(px, py)
			var mt: Dictionary = m.tris
			for i in px.size():
				if frame[i]:
					continue
				var pts := []
				for t in m.pt_tris[i]:
					pts.append([mt.x[t], mt.y[t]])
				var cc := RealmGen.poly_centroid(pts)
				if is_finite(cc[0]):
					px[i] = maxf(S * 0.3, minf(W - S * 0.3, cc[0]))
					py[i] = maxf(S * 0.3, minf(H - S * 0.3, cc[1]))
		var mesh := RealmGen.build_mesh(px, py)
		tris = mesh.tris
		edge_tris = mesh.edge_tris
		pt_tris = mesh.pt_tris
		N = px.size()
		var nt: int = tris.a.size()
		# 3. merge vertices joined by very short Voronoi edges
		uf.resize(nt)
		for i in nt:
			uf[i] = i
		for k in edge_tris:
			var l: Array = edge_tris[k]
			if l.size() != 2:
				continue
			if JS.hypot(tris.x[l[0]] - tris.x[l[1]], tris.y[l[0]] - tris.y[l[1]]) < MIN_EDGE:
				uf[find(l[0])] = find(l[1])
		var rep_sum := {}
		for i in nt:
			var rr := find(i)
			var s: Array = rep_sum.get(rr, [0.0, 0.0, 0])
			s[0] += tris.x[i]
			s[1] += tris.y[i]
			s[2] += 1
			rep_sum[rr] = s
		for rr in rep_sum:
			var s: Array = rep_sum[rr]
			rep_pos[rr] = [s[0] / s[2], s[1] / s[2]]
		# cells
		cell_v.resize(N)
		sides.resize(N)
		near_frame.resize(N)
		touch.resize(N)
		border.resize(N)
		for i in N:
			touch[i] = {}
			border[i] = {}
		for k in edge_tris:
			var l: Array = edge_tris[k]
			var u := int(floor(k / 100000.0))
			var v: int = k % 100000
			touch[u][v] = true
			touch[v][u] = true
			if frame[u] and not frame[v]:
				near_frame[v] = 1
			if frame[v] and not frame[u]:
				near_frame[u] = 1
			if l.size() == 2:
				var ra := find(l[0])
				var rb := find(l[1])
				if ra != rb:
					border[u][v] = [ra, rb]
					border[v][u] = [ra, rb]
		for i in N:
			if frame[i]:
				continue
			var vs := []
			for t in pt_tris[i]:
				var rr := find(t)
				if vs.is_empty() or vs[vs.size() - 1] != rr:
					vs.append(rr)
			while vs.size() > 1 and vs[0] == vs[vs.size() - 1]:
				vs.pop_back()
			cell_v[i] = vs
			sides[i] = vs.size()
		# 4. island field with deliberate peninsulas and coves
		var cell_area := 0.0
		var cnt := 0
		for i in N:
			if not frame[i] and not near_frame[i]:
				var pts := []
				for rr in cell_v[i]:
					pts.append(rep_pos[rr])
				cell_area += RealmGen.poly_centroid(pts)[2]
				cnt += 1
		cell_area /= cnt
		var ratio := 1.32 + rng.next() * 0.12
		var n_lakes := 1 + int(floor(rng.next() * 3))
		var lake_sizes := []
		for _i in n_lakes:
			lake_sizes.append(2 + int(floor(rng.next() * 2)))
		if o.shape == "ring":
			lake_sizes.clear()
		var lake_cells := 0
		for s in lake_sizes:
			lake_cells += s
		var target := NPROV + lake_cells
		A = sqrt(target * cell_area * ratio / PI)
		B = A / ratio
		var c0 := W / 2.0 + (rng.next() - 0.5) * 50.0
		var c1 := H / 2.0 + (rng.next() - 0.5) * 40.0
		C = [c0, c1]
		for k in range(2, 7):
			var amp := (0.55 / k) * (0.5 + rng.next())
			harm.append([k, amp, rng.next() * 7.0])
		ph1 = rng.next() * 7.0
		ph2 = rng.next() * 7.0
		if o.shape == "ring":
			k_scale = 1.0 / sqrt(1.0 - 0.42 * 0.42) * 1.06
			hole = {"q": 0.42, "ph": rng.next() * 7.0}
		if o.shape == "crescent":
			var b := rng.next() * PI * 2.0
			k_scale = 1.38
			bite = {"th": b, "off": 0.6, "r": 0.7}
		if o.shape == "random":
			wob = 0.18 + rng.next() * 0.1
			for k in range(7, 10):
				var amp := (0.55 / k) * (0.5 + rng.next())
				harm.append([k, amp, rng.next() * 7.0])
			var nl := 1 + int(floor(rng.next() * 3))
			for _i in nl:
				var lth := rng.next() * PI * 2.0
				var ld := 0.7 + rng.next() * 0.35
				var lr := 0.32 + rng.next() * 0.22
				lobes.append({"th": lth, "d": ld, "r": lr})
			k_scale = 0.86
		mean_r = sqrt(A * B) * k_scale
		if bite != null:
			bite_c = [C[0] + DMath.cos(bite.th) * mean_r * bite.off, C[1] + DMath.sin(bite.th) * mean_r * bite.off]
		# pick angles
		var pens := []
		var coves := []
		var arc := (PI * 2.0 - 2.0 * 1.35 if bite != null else PI * 2.0) - lobes.size() * 1.2
		var n_f: int = o.pens + o.coves
		var p_sep := 1.9 if o.pens <= 2 and bite == null else minf(1.9, arc / maxf(1, o.pens) * 0.66)
		var pc_sep := 0.85 if n_f <= 4 and bite == null else minf(0.85, arc / maxf(1, n_f) * 0.6)
		var c_sep := 1.2 if o.coves <= 2 and bite == null else minf(1.2, arc / maxf(1, o.coves) * 0.66)
		var t := 0
		while t < 200 and pens.size() < o.pens:
			var a := rng.next() * PI * 2.0
			if shape_ok(a) and pens.all(func(p): return RealmGen.ang_diff(p, a) > p_sep):
				pens.append(a)
			t += 1
		t = 0
		while t < 400 and coves.size() < o.coves:
			var a := rng.next() * PI * 2.0
			if shape_ok(a) and pens.all(func(p): return RealmGen.ang_diff(p, a) > pc_sep) and coves.all(func(c): return RealmGen.ang_diff(c, a) > c_sep):
				coves.append(a)
			t += 1
		if pens.size() < o.pens or coves.size() < o.coves:
			return fail("feature angles")
		for th in pens:
			var bend := (rng.next() - 0.5) * 2.0 * 246.0
			var pp := [-DMath.sin(th), DMath.cos(th)]
			var tip := at(th, 1.42)
			pen_lines.append({"th": th, "line": [at(th, 0.55), at(th, 1.02), [tip[0] + pp[0] * bend, tip[1] + pp[1] * bend]], "hw": S * 0.95})
		for th in coves:
			cove_lines.append({"th": th, "line": [at(th, 1.7), at(th, 0.74 if hole != null else 0.6)], "hw": S * 0.78})
		F.resize(N)
		for i in N:
			F[i] = field(px[i], py[i])
		# 5. grow island over shared edges, highest field first
		var start := -1
		for i in N:
			if valid(i) and (start < 0 or F[i] > F[start]):
				start = i
		land.resize(N)
		land[start] = 1
		n_land = 1
		var front := {}
		for w in border[start].keys():
			if valid(w):
				front[w] = true
		while n_land < target:
			var best := -1
			for v in front:
				if not land[v] and (best < 0 or F[v] > F[best]):
					best = v
			if best < 0 or F[best] < -2.0:
				return fail("growth stalled")
			land[best] = 1
			n_land += 1
			front.erase(best)
			for w in border[best].keys():
				if not land[w] and valid(w):
					front[w] = true
		# 6. fill lakes, then trim lowest coast cells
		var reach := ocean_reach()
		is_lake.resize(N)
		if hole != null:
			var bigl := []
			for i in N:
				if not land[i] and not reach[i] and in_hole(px[i], py[i]):
					is_lake[i] = 1
					bigl.append(i)
			if bigl.size() < 6:
				return fail("ring lake too small")
			lakes.append(bigl)
		for i in N:
			if not land[i] and not reach[i] and not is_lake[i]:
				if not valid(i):
					return fail("lake on invalid cell")
				land[i] = 1
				n_land += 1
		while n_land > target:
			reach = ocean_reach()
			var cand := []
			for i in N:
				if land[i] and not protected_cell(i):
					for w in border[i].keys():
						if not land[w] and reach[w]:
							cand.append(i)
							break
			JS.stable_sort(cand, func(a, b): return F[a] - F[b])
			var done := false
			for c in cand:
				land[c] = 0
				n_land -= 1
				if land_connected():
					done = true
					break
				land[c] = 1
				n_land += 1
			if not done:
				return fail("trim failed")
		reach = ocean_reach()
		for i in N:
			if not land[i] and not reach[i] and not is_lake[i]:
				return fail("lake remains")
		if hole != null:
			for c in lakes[0]:
				if reach[c]:
					return fail("ring opened to the sea")
		if not land_connected():
			return fail("not one landmass")
		strict = o.shape == "classic" and o.pens == 2 and o.coves == 2
		if strict and not no_corridors():
			return fail("corridor")
		# 6b. carve 1–3 inland lakes, each 2–3 cells
		for size in lake_sizes:
			var placed := false
			var seed_list := []
			for i in N:
				if deep_cell(i) and not near_lake(i):
					seed_list.append(i)
			rng.shuffle(seed_list)
			for sd in seed_list.slice(0, 40):
				var lc := [sd]
				while lc.size() < size:
					var optset := {}
					for c in lc:
						for w in border[c].keys():
							optset[w] = true
					var opts := []
					for w in optset.keys():
						if not lc.has(w) and deep_cell(w) and not near_lake(w):
							opts.append(w)
					if opts.is_empty():
						break
					lc.append(opts[int(floor(rng.next() * opts.size()))])
				if lc.size() < size:
					continue
				for c in lc:
					land[c] = 0
				n_land -= size
				if land_connected() and (not strict or no_corridors()):
					for c in lc:
						is_lake[c] = 1
					lakes.append(lc)
					placed = true
					break
				for c in lc:
					land[c] = 1
				n_land += size
			if not placed:
				return fail("lake placement")
		var reach2 := ocean_reach()
		var lakes_inland := true
		for lc in lakes:
			for c in lc:
				if reach2[c]:
					lakes_inland = false
		# 7. verify peninsulas and coves geometrically
		var pens_ok := 0
		var pen_report := []
		for p in pen_lines:
			var outer := []
			for i in N:
				if not land[i]:
					continue
				var tt: float = axis_coords(i, p.th)[0]
				if tt > coast_r(p.th) * 1.0 and RealmGen.dist_polyline(px[i], py[i], p.line) < p.hw * 1.3:
					outer.append(i)
			var coastal := 0
			var L := false
			var R := false
			for i in outer:
				var touches := false
				for w in border[i].keys():
					if land[w]:
						continue
					touches = true
					var s := (px[w] - px[i]) * -DMath.sin(p.th) + (py[w] - py[i]) * DMath.cos(p.th)
					if s > 21.0:
						L = true
					if s < -21.0:
						R = true
				if touches:
					coastal += 1
			var ok := outer.size() >= 3 and coastal == outer.size() and L and R
			if ok:
				pens_ok += 1
			pen_report.append({"ok": ok, "cells": outer.size(), "line": p.line})
		var coves_ok := 0
		var cove_report := []
		for c in cove_lines:
			var inner := []
			for i in N:
				if land[i] or not reach[i] or frame[i]:
					continue
				var tt: float = axis_coords(i, c.th)[0]
				if tt < coast_r(c.th) * 0.93 and RealmGen.dist_polyline(px[i], py[i], c.line) < c.hw * 1.3:
					inner.append(i)
			var l := false
			var rr := false
			for i in inner:
				for w in border[i].keys():
					if not land[w]:
						continue
					var s := (px[w] - px[i]) * -DMath.sin(c.th) + (py[w] - py[i]) * DMath.cos(c.th)
					if s > 21.0:
						l = true
					if s < -21.0:
						rr = true
			var ok := inner.size() >= 2 and l and rr
			if ok:
				coves_ok += 1
			cove_report.append({"ok": ok, "cells": inner.size(), "line": c.line})
		if pens_ok < o.pens:
			return fail("peninsula check")
		if coves_ok < o.coves:
			return fail("cove check")
		# index land cells as provinces, ordered top-to-bottom, left-to-right
		var cells := []
		for i in N:
			if land[i]:
				cells.append(i)
		JS.stable_sort(cells, func(a, b):
			var d := JS.round_js(py[a] / 403.0) - JS.round_js(py[b] / 403.0)
			return d if d != 0.0 else px[a] - px[b])
		var pid := {}
		for i in cells.size():
			pid[cells[i]] = i
		var n := cells.size()
		var adj := []
		for c in cells:
			var l := []
			for w in touch[c].keys():
				if pid.has(w):
					l.append(pid[w])
			adj.append(l)
		var edges := []
		var p_edges := []
		for _i in n:
			p_edges.append([])
		for i in n:
			var c: int = cells[i]
			for w in border[c]:
				if not pid.has(w):
					continue
				var j: int = pid[w]
				if j < i:
					continue
				var rab: Array = border[c][w]
				var e := {"id": edges.size(), "a": i, "b": j, "ra": rab[0], "rb": rab[1]}
				edges.append(e)
				p_edges[i].append(e.id)
				p_edges[j].append(e.id)
		# 8. colour + 9. barrier assignment
		var nbr := []
		for i in n:
			var l := []
			for id in p_edges[i]:
				l.append(edges[id].b if edges[id].a == i else edges[id].a)
			nbr.append(l)
		var ocean_verts := {}
		var lake_of := {}
		var lake_verts := []
		for k in lakes.size():
			lake_verts.append({})
			for c in lakes[k]:
				lake_of[c] = k
		for c in cells:
			for w in border[c]:
				if land[w]:
					continue
				var rab: Array = border[c][w]
				if is_lake[w]:
					lake_verts[lake_of[w]][rab[0]] = true
					lake_verts[lake_of[w]][rab[1]] = true
				else:
					ocean_verts[rab[0]] = true
					ocean_verts[rab[1]] = true
		var terr = null
		var barrier = null
		var lake_plan = null
		var tryc := 0
		while tryc < 10 and barrier == null:
			terr = RealmGen.assign_terrain(n, nbr, adj, rng, o)
			tryc += 1
			if terr == null:
				continue
			lake_plan = _plan_lake_rivers(terr, edges, lake_verts, ocean_verts)
			if lake_plan == null:
				continue
			barrier = RealmGen.solve_barriers(n, edges, p_edges, terr, rng, lake_plan.fixed, not strict)
		if barrier == null:
			return fail("barrier solve")
		# 10. barrier styles: rivers first, then trees / mountains / ruins
		var coast_verts := {}
		for c in cells:
			for w in border[c]:
				if not land[w]:
					var rab: Array = border[c][w]
					coast_verts[rab[0]] = true
					coast_verts[rab[1]] = true
		var v_bar := {}
		for e in edges:
			if not barrier[e.id]:
				continue
			for rv in [e.ra, e.rb]:
				if not v_bar.has(rv):
					v_bar[rv] = []
				v_bar[rv].append(e.id)
		var style := []
		style.resize(edges.size())
		var rivers := []
		var river_verts := {}
		for rv in lake_plan.rivers:
			for id in rv.ids:
				style[id] = "river"
			for p in rv.path:
				river_verts[p] = true
			rivers.append({"path": rv.path, "lake": rv.lake})
		var starts := []
		for v in ocean_verts.keys():
			if v_bar.has(v):
				starts.append(v)
		rng.shuffle(starts)
		var extra := 0
		for s in starts:
			if extra >= 4:
				break
			if river_verts.has(s):
				continue
			var len := 4 + int(floor(rng.next() * 6))
			var path := [s]
			var used := []
			var v: int = s
			while used.size() < len:
				var opts := []
				for id in v_bar.get(v, []):
					if style[id] != null or used.has(id):
						continue
					var e: Dictionary = edges[id]
					var ov: int = e.rb if e.ra == v else e.ra
					if river_verts.has(ov) or path.has(ov) or coast_verts.has(ov):
						continue
					var p0: Array = rep_pos[v]
					var p1: Array = rep_pos[ov]
					var inward := JS.hypot(p0[0] - C[0], p0[1] - C[1]) - JS.hypot(p1[0] - C[0], p1[1] - C[1])
					opts.append({"id": id, "o": ov, "score": inward + rng.next() * 134.0})
				JS.stable_sort(opts, func(a, b): return b.score - a.score)
				if opts.is_empty():
					break
				used.append(opts[0].id)
				v = opts[0].o
				path.append(v)
			if used.size() >= 3:
				for id in used:
					style[id] = "river"
				for p in path:
					river_verts[p] = true
				rivers.append({"path": path, "lake": null})
				extra += 1
		var weights := {"grassland": {"mountains": 5.0, "trees": 3.0, "ruins": 2.0}, "forest": {"trees": 6.0, "mountains": 2.5, "ruins": 1.5}, "swamp": {"trees": 3.0, "ruins": 3.5, "mountains": 2.0}, "desert": {"mountains": 1.0}}
		var trees_opt: float = o.trees if o.trees else 0
		for e in edges:
			if not barrier[e.id] or style[e.id] != null:
				continue
			var w := {}
			for tn in [RealmGen.TERRAINS[terr[e.a]], RealmGen.TERRAINS[terr[e.b]]]:
				for k in weights[tn]:
					w[k] = w.get(k, 0.0) + weights[tn][k] * (1.0 + 0.75 * trees_opt if k == "trees" else 1.0)
			var tot := 0.0
			for k in w:
				tot += w[k]
			var rr := rng.next() * tot
			for k in w:
				rr -= w[k]
				if rr <= 0.0:
					style[e.id] = k
					break
			if style[e.id] == null:
				style[e.id] = "trees"
		for _pass in 2:
			for e in edges:
				if not barrier[e.id] or style[e.id] == "river":
					continue
				var cnt2 := {}
				for rv in [e.ra, e.rb]:
					for id in v_bar.get(rv, []):
						if id != e.id and style[id] != "river":
							cnt2[style[id]] = cnt2.get(style[id], 0) + 1
				var ent := []
				for k in cnt2:
					ent.append([k, cnt2[k]])
				JS.stable_sort(ent, func(a, b): return b[1] - a[1])
				if ent.size() and ent[0][1] >= 2 and rng.next() < 0.7:
					style[e.id] = ent[0][0]
		# junction fillers where 3+ provinces meet
		var v_cells := {}
		for i in n:
			for rv in cell_v[cells[i]]:
				if not v_cells.has(rv):
					v_cells[rv] = []
				v_cells[rv].append(i)
		var junctions := []
		for rv in v_cells:
			if v_cells[rv].size() < 3 or coast_verts.has(rv):
				continue
			var types := []
			for id in v_bar.get(rv, []):
				types.append(style[id])
			var kind: String
			if types.has("river"):
				kind = "river"
			elif types.size():
				var cnt3 := {}
				for tp in types:
					cnt3[tp] = cnt3.get(tp, 0) + 1
				var ent := []
				for k in cnt3:
					ent.append([k, cnt3[k]])
				JS.stable_sort(ent, func(a, b): return b[1] - a[1])
				kind = ent[0][0]
			else:
				kind = "rocks"
			junctions.append({"v": rv, "kind": kind})
		# ---------- assemble ----------
		var v_index := {}
		var vertices := []
		var vid := func(rv: int) -> int:
			if not v_index.has(rv):
				v_index[rv] = vertices.size()
				var p: Array = rep_pos[rv]
				vertices.append([JS.to_fixed(p[0], 2), JS.to_fixed(p[1], 2)])
			return v_index[rv]
		var provinces := []
		for i in n:
			var c: int = cells[i]
			var vs := []
			for rv in cell_v[c]:
				vs.append(vid.call(rv))
			var coast := []
			for w in border[c]:
				if not land[w]:
					var rab: Array = border[c][w]
					coast.append([vid.call(rab[0]), vid.call(rab[1]), 1 if is_lake[w] else 0])
			provinces.append({"id": i + 1, "site": [JS.to_fixed(px[c], 1), JS.to_fixed(py[c], 1)], "verts": vs, "terrain": RealmGen.TERRAINS[terr[i]], "adj": adj[i], "nbr": nbr[i], "edges": p_edges[i], "coast": coast})
		var out_edges := []
		for e in edges:
			out_edges.append({"id": e.id, "a": e.a, "b": e.b, "v": [vid.call(e.ra), vid.call(e.rb)], "open": not barrier[e.id], "style": style[e.id] if barrier[e.id] else null})
		var out_rivers := []
		for rv in rivers:
			var vv := []
			for p in rv.path:
				vv.append(vid.call(p))
			out_rivers.append({"verts": vv, "lake": rv.lake})
		var out_j := []
		for j in junctions:
			out_j.append({"v": vid.call(j.v), "kind": j.kind})
		var out_lakes := []
		for lc in lakes:
			var polys := []
			for c in lc:
				var poly := []
				for rv in cell_v[c]:
					poly.append(vid.call(rv))
				polys.append(poly)
			out_lakes.append({"cells": lc.size(), "polys": polys})
		var feats := {"peninsulas": [], "coves": []}
		for p in pen_report:
			if p.ok:
				feats.peninsulas.append({"cells": p.cells, "line": p.line})
		for c in cove_report:
			if c.ok:
				feats.coves.append({"cells": c.cells, "line": c.line})
		var touches_edge := false
		for c in cells:
			if near_frame[c]:
				touches_edge = true
		var world := {"W": W, "H": H, "center": C, "provinces": provinces, "vertices": vertices, "edges": out_edges, "rivers": out_rivers, "junctions": out_j,
			"features": feats, "lakes": out_lakes, "lakesInland": lakes_inland, "touchesEdgeOfWorld": touches_edge}
		return {"ok": true, "world": world}

	# web: planLakeRivers(terr) — one river per lake, along province borders down to the sea
	func _plan_lake_rivers(terr: Array, edges: Array, lake_verts: Array, ocean_verts: Dictionary):
		var v_adj := {}
		for e in edges:
			if terr[e.a] == 2 or terr[e.b] == 2:
				continue
			for uv in [[e.ra, e.rb], [e.rb, e.ra]]:
				if not v_adj.has(uv[0]):
					v_adj[uv[0]] = []
				v_adj[uv[0]].append([uv[1], e.id])
		var any_lake_vert := func(v: int) -> bool:
			for s in lake_verts:
				if s.has(v):
					return true
			return false
		var fixed := PackedByteArray()
		fixed.resize(edges.size())
		var out := []
		var used := {}
		for k in lakes.size():
			var dist := {}
			var prev := {}
			var done := {}
			for v in lake_verts[k]:
				if v_adj.has(v) and not used.has(v):
					dist[v] = 0.0
			var goal := -1
			while true:
				var u := -1
				var du := INF
				for v in dist:
					if not done.has(v) and dist[v] < du:
						du = dist[v]
						u = v
				if u < 0:
					break
				done[u] = true
				if ocean_verts.has(u):
					goal = u
					break
				if du > 0.0 and any_lake_vert.call(u):
					continue
				for vi in v_adj.get(u, []):
					var v: int = vi[0]
					var id: int = vi[1]
					if used.has(v) or done.has(v):
						continue
					if any_lake_vert.call(v) and not ocean_verts.has(v):
						continue
					var p0: Array = rep_pos[u]
					var p1: Array = rep_pos[v]
					var nd := du + JS.hypot(p1[0] - p0[0], p1[1] - p0[1]) * (0.6 + rng.next() * 0.8)
					if nd < dist.get(v, INF):
						dist[v] = nd
						prev[v] = [u, id]
			if goal < 0:
				return null
			var path := [goal]
			var ids := []
			var v := goal
			while prev.has(v):
				var ui: Array = prev[v]
				ids.append(ui[1])
				path.append(ui[0])
				v = ui[0]
			for id in ids:
				fixed[id] = 1
			for x in path:
				used[x] = true
			out.append({"path": path, "ids": ids, "lake": k})
		return {"fixed": fixed, "rivers": out}


# ---------- biomes: forest/desert/swamp in separate clumps of 5–15, the rest grassland ----------
# web: assignTerrain(n, nbr, tch, rng, o)
static func assign_terrain(n: int, nbr: Array, tch: Array, rng: Mulberry32, o: Dictionary):
	var scatter: bool = o.shape == "random"
	var min_c := 1 if scatter else 5
	var trees_opt: float = o.trees if o.trees else 0
	var f_bias := 1.0 / (1.0 + 0.6 * trees_opt)
	var lo := int(ceil(0.15 * n))
	var hi := int(floor(0.35 * n))
	for _tries in 40:
		var counts := []
		for k in 3:
			var rv := rng.next()
			counts.append(lo + int(floor((DMath.pow(rv, f_bias) if k == 0 else rv) * (hi - lo + 1))))
		var grass: int = n - counts[0] - counts[1] - counts[2]
		if grass < lo or grass > hi:
			continue
		var clumps := []
		for k in 3:
			var c: int = counts[k]
			var kmin := int(ceil(c / 15.0))
			var kmax := int(floor(c / float(min_c)))
			var r1 := rng.next()
			var kk := kmin + int(floor(r1 * rng.next() * (kmax - kmin + 1)))
			var sizes := []
			for _i in kk:
				sizes.append(min_c)
			var rest := c - min_c * kk
			while rest > 0:
				var i := int(floor(rng.next() * kk))
				if sizes[i] < 15:
					sizes[i] += 1
					rest -= 1
			for size in sizes:
				clumps.append({"type": k + 1, "size": size})
		rng.shuffle(clumps)
		JS.stable_sort(clumps, func(a, b): return b.size - a.size)
		var terr := PackedInt32Array()
		terr.resize(n)
		terr.fill(-1)
		var clump_of := PackedInt32Array()
		clump_of.resize(n)
		clump_of.fill(-1)
		var failed := false
		var ci := 0
		while ci < clumps.size() and not failed:
			var cl: Dictionary = clumps[ci]
			var blocked := func(v: int) -> bool:
				if terr[v] != -1:
					return true
				if scatter:
					return false
				for w in tch[v]:
					if terr[w] == cl.type and clump_of[w] != ci:
						return true
				return false
			var seeds := []
			for v in n:
				if not blocked.call(v):
					seeds.append(v)
			rng.shuffle(seeds)
			var done := false
			for sd in seeds.slice(0, 25):
				var members := [sd]
				terr[sd] = cl.type
				clump_of[sd] = ci
				while members.size() < cl.size:
					var best := -1
					var bs := -1.0
					for m in members:
						for w in nbr[m]:
							if blocked.call(w):
								continue
							var c2 := 0
							for x in nbr[w]:
								if clump_of[x] == ci:
									c2 += 1
							var sc := c2 + rng.next() * 1.5
							if sc > bs:
								bs = sc
								best = w
					if best < 0:
						break
					members.append(best)
					terr[best] = cl.type
					clump_of[best] = ci
				if members.size() == cl.size:
					done = true
					break
				for m in members:
					terr[m] = -1
					clump_of[m] = -1
			if not done:
				failed = true
			ci += 1
		if failed:
			continue
		for v in n:
			if terr[v] < 0:
				terr[v] = 0
		var ok := true
		var v := 0
		while v < n and ok:
			if terr[v] != 2:
				var dn := 0
				for w in nbr[v]:
					if terr[w] == 2:
						dn += 1
				if dn > int(ceil(nbr[v].size() / 2.0)):
					ok = false
			v += 1
		if ok:
			return Array(terr)
	return null


# ---------- barrier solver: half the borders blocked, deserts open, all reachable ----------
# web: solveBarriers(n, edges, pEdges, terr, rng, fixed, loose). Same draws as the web; components are only
# tracked incrementally instead of recounted after every flip.
static func solve_barriers(n: int, edges: Array, p_edges: Array, terr: Array, rng: Mulberry32, fixed: PackedByteArray, loose: bool):
	return _Solver.new().solve(n, edges, p_edges, terr, rng, fixed, loose)


class _Solver:
	extends RefCounted
	const DESERT := 2
	var n: int
	var ea := PackedInt32Array()
	var eb := PackedInt32Array()
	var lo := PackedInt32Array()
	var hi := PackedInt32Array()
	var cnt := PackedInt32Array()
	var bar := PackedByteArray()
	var label := PackedInt32Array()
	var desert := PackedByteArray()
	var pe_start := PackedInt32Array()
	var pe_ids := PackedInt32Array()
	var q := PackedInt32Array()
	var next_label := 0
	var mark := PackedInt32Array()
	var stamp := 0
	var seen_list := PackedInt32Array()

	## Is b reachable from a through open borders? Leaves the cells reached from a in seen_list.
	func reaches(a: int, b: int) -> bool:
		stamp += 1
		mark[a] = stamp
		seen_list.resize(0)
		seen_list.append(a)
		var h := 0
		while h < seen_list.size():
			var u := seen_list[h]
			h += 1
			for k in range(pe_start[u], pe_start[u + 1]):
				var id := pe_ids[k]
				if bar[id]:
					continue
				var w := eb[id] if ea[id] == u else ea[id]
				if w == b:
					return true
				if mark[w] != stamp:
					mark[w] = stamp
					seen_list.append(w)
		return false

	var bad := PackedInt32Array()

	func update_bad(p: int) -> void:
		var i := bad.bsearch(p)
		var has := i < bad.size() and bad[i] == p
		var v := viol(p) > 0
		if v and not has:
			bad.insert(i, p)
		elif has and not v:
			bad.remove_at(i)

	func viol(p: int) -> int:
		if desert[p]:
			return 0
		return maxi(0, lo[p] - cnt[p]) + maxi(0, cnt[p] - hi[p])

	func components() -> int:
		label.fill(-1)
		var c := 0
		for s in n:
			if label[s] >= 0:
				continue
			label[s] = c
			q.resize(0)
			q.append(s)
			while q.size():
				var u := q[q.size() - 1]
				q.resize(q.size() - 1)
				for k in range(pe_start[u], pe_start[u + 1]):
					var id := pe_ids[k]
					if bar[id]:
						continue
					var w := eb[id] if ea[id] == u else ea[id]
					if label[w] < 0:
						label[w] = c
						q.append(w)
			c += 1
		return c

	func solve(n_: int, edges: Array, p_edges: Array, terr: Array, rng: Mulberry32, fixed: PackedByteArray, loose: bool):
		n = n_
		var free := PackedInt32Array()
		for e in edges:
			if terr[e.a] != DESERT and terr[e.b] != DESERT and not fixed[e.id]:
				free.append(e.id)
		var ne := edges.size()
		var is_free := PackedByteArray()
		is_free.resize(ne)
		for id in free:
			is_free[id] = 1
		for e in edges:
			ea.append(e.a)
			eb.append(e.b)
		desert.resize(n)
		for p in n:
			desert[p] = 1 if terr[p] == DESERT else 0
		for l in p_edges:
			lo.append(0 if loose and l.size() <= 2 else int(floor(l.size() / 2.0)))
			hi.append(int(ceil(l.size() / 2.0)))
		bar.resize(ne)
		cnt.resize(n)
		for e in edges:
			if fixed[e.id]:
				bar[e.id] = 1
				cnt[e.a] += 1
				cnt[e.b] += 1
		for p in n:
			if desert[p]:
				continue
			var nfree := 0
			for id in p_edges[p]:
				if is_free[id]:
					nfree += 1
			if cnt[p] > hi[p] or cnt[p] + nfree < lo[p]:
				return null
		label.resize(n)
		mark.resize(n)
		for p in n:
			pe_start.append(pe_ids.size())
			for id in p_edges[p]:
				pe_ids.append(id)
		pe_start.append(pe_ids.size())
		# greedy start
		var order := Array(free)
		rng.shuffle(order)
		for id in order:
			var a := ea[id]
			var b := eb[id]
			if (cnt[a] < lo[a] and cnt[b] < hi[b]) or (cnt[b] < lo[b] and cnt[a] < hi[a]):
				bar[id] = 1
				cnt[a] += 1
				cnt[b] += 1
		var local := 0
		for p in n:
			local += viol(p)
		var comp := components()
		var T := 1.2
		var nfree_all := free.size()
		var fa := PackedInt32Array()
		var fb := PackedInt32Array()
		for x in free:
			fa.append(ea[x])
			fb.append(eb[x])
		for p in n:   # provinces breaking their limits, kept in index order like the web's filter
			if viol(p):
				bad.append(p)
		var opts := PackedInt32Array()
		var changed := PackedInt32Array()
		next_label = n + 1
		for it in 8000:
			if local == 0 and comp == 1:
				return bar
			T = maxf(0.03, T * 0.9995)
			var id := -1
			var r := rng.next()
			if r < 0.6 and local > 0:
				var p: int = bad[int(floor(rng.next() * bad.size()))]
				var want := 0 if cnt[p] < lo[p] else 1
				opts.resize(0)
				for k in range(pe_start[p], pe_start[p + 1]):
					var x := pe_ids[k]
					if is_free[x] and bar[x] == want:
						opts.append(x)
				if opts.size():
					id = opts[int(floor(rng.next() * opts.size()))]
			elif r < 0.85 and comp > 1:
				opts.resize(0)
				for k in nfree_all:
					var x := free[k]
					if bar[x] and label[fa[k]] != label[fb[k]]:
						opts.append(x)
				if opts.size():
					id = opts[int(floor(rng.next() * opts.size()))]
			if id < 0:
				id = free[int(floor(rng.next() * free.size()))]
			var a := ea[id]
			var b := eb[id]
			var before := local + 4 * (comp - 1)
			var old_local := local
			var old_comp := comp
			local -= viol(a) + viol(b)
			var d := -1 if bar[id] else 1
			bar[id] ^= 1
			cnt[a] += d
			cnt[b] += d
			local += viol(a) + viol(b)
			update_bad(a)
			update_bad(b)
			# keep the component labels up to date incrementally (labels are only compared, never counted)
			changed.resize(0)
			var old_lab := -1
			if d == -1:
				if label[a] != label[b]:   # opening a border between two components merges them
					old_lab = label[b]
					var la := label[a]
					for x in n:
						if label[x] == old_lab:
							label[x] = la
							changed.append(x)
					comp -= 1
			elif not reaches(a, b):   # closing a border split a component: give a's side a new label
				old_lab = label[a]
				for x in seen_list:
					label[x] = next_label
					changed.append(x)
				next_label += 1
				comp += 1
			var delta := (local + 4 * (comp - 1)) - before
			if delta > 0 and rng.next() >= DMath.exp(-delta / T):
				bar[id] ^= 1
				cnt[a] -= d
				cnt[b] -= d
				local = old_local
				comp = old_comp
				for x in changed:
					label[x] = old_lab
				update_bad(a)
				update_bad(b)
		return null


## web: game.js scaleWorld(w) — the game plays on the generated map scaled by WORLD_K (2).
const WORLD_K := 2.0
static func scale_world(w: Dictionary) -> Dictionary:
	if w.get("scaledK"):
		return w
	var vs := []
	for v in w.vertices:
		vs.append([v[0] * WORLD_K, v[1] * WORLD_K])
	w.vertices = vs
	for p in w.provinces:
		p.site = [p.site[0] * WORLD_K, p.site[1] * WORLD_K]
	w.center = [w.center[0] * WORLD_K, w.center[1] * WORLD_K]
	w.W *= WORLD_K
	w.H *= WORLD_K
	w.scaledK = WORLD_K
	return w
