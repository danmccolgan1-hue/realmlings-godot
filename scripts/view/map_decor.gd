class_name MapDecor
extends RefCounted
## The map's decoration, placed exactly as the web game places it (one seeded random stream, `seed + ':decor'`, used
## in the same order): province details, the border bands of trees / palms / mountains / ruins, junction fillers,
## lake ripples, waves, clouds and the darker terrain patches. Pure look: nothing here changes the game.
## web: page.html prep() as rewritten by assemble_game.py (DECOR_N, the thick border bands, the blended terrain)

const WORLD_K := 2.0
const DECOR_N := 3
const BLEND := 70.0
const PADT := 260.0

const RECIPE := {
	"grassland": [["tuft", 9], ["flower0", 2], ["flower1", 2], ["flower2", 2], ["rock0", 1]],
	"forest": [["grove", 3], ["shroom", 2], ["tuft", 3]],
	"desert": [["dune", 5], ["cactus", 2], ["rock0", 1], ["rock1", 1]],
	"swamp": [["puddle", 4], ["reeds", 6], ["lily", 4], ["swampgrove", 2]],
}


## {items: [[{x, y, s}]] per province, sway: [{x, y, s, ph}], still: [{x, y, s}], crossings: [{x, y, ang, len}],
##  lake_marks: [{x, y}], waves: [{x, y, ph, s}], clouds: [{x, y, v, s}], shade: [[{x, y, rx, ry, a}]] per province,
##  bounds: [x0, y0, x1, y1]}
static func build(w: Dictionary, G: Dictionary) -> Dictionary:
	var V: Array = w.vertices
	var r := Mulberry32.from_string(str(w.seed) + ":decor")
	var provs: Array = G.provs
	# province details: they hug the edges and leave the middle open for units and buildings
	var all_items := []
	for p in provs:
		var items := []
		var inner: Array = p.inner
		var ic: Array = p.ic
		var bx0 := INF
		var by0 := INF
		var bx1 := -INF
		var by1 := -INF
		var rs := 0.0
		for q in inner:
			bx0 = minf(bx0, q[0])
			bx1 = maxf(bx1, q[0])
			by0 = minf(by0, q[1])
			by1 = maxf(by1, q[1])
			rs += JS.hypot(q[0] - ic[0], q[1] - ic[1])
		var clear_r := rs / inner.size() * 0.5
		var spot := func(min_gap: float, edge_gap: float):
			for t in 40:
				var x: float = bx0 + r.next() * (bx1 - bx0)
				var y: float = by0 + r.next() * (by1 - by0)
				if not Geo.in_poly(x, y, inner) or Geo.dist_to_edges(x, y, inner) < edge_gap:
					continue
				if JS.hypot(x - ic[0], y - ic[1]) < clear_r:
					continue
				if items.any(func(it): return JS.hypot(it.x - x, it.y - y) < min_gap):
					continue
				return [x, y]
			return null
		for rc in RECIPE[p.terrain]:
			var name: String = rc[0]
			for k in rc[1] * DECOR_N:
				if name == "grove" or name == "swampgrove":
					var at = spot.call(34.0, 30.0)
					if at == null:
						continue
					var m := 3 + int(floor(r.next() * 2)) if name == "grove" else 2
					for j in m:
						var a: float = j * 2.1 + r.next()
						var rad: float = 11 + r.next() * 4 if j else 0.0
						var s: String
						if name == "grove":
							s = ["tree0", "tree1", "pine0", "pine1"][int(floor(r.next() * 4))]
						else:
							s = "cypress%d" % (j % 2)
						items.append({"x": at[0] + cos(a) * rad, "y": at[1] + sin(a) * rad * 0.7, "s": s})
				else:
					var at = spot.call(16.0, 16.0)
					if at != null:
						items.append({"x": at[0], "y": at[1], "s": name})
		items = JS.stable_sort(items, func(a, b): return signf(a.y - b.y))
		all_items.append(items)
	# border bands: two staggered rows of large sprites
	var sway := []
	var still := []
	var tree_for := func(swampy: bool) -> String:
		if swampy:
			return "cypress%d" % (0 if r.next() < 0.5 else 1)
		if r.next() < 0.45:
			return "pine%d" % (0 if r.next() < 0.5 else 1)
		return "tree%d" % int(floor(r.next() * 3))
	for e in w.edges:
		if e.open or e.style == "river":
			continue
		var a: Array = V[e.v[0]]
		var b: Array = V[e.v[1]]
		var dx: float = b[0] - a[0]
		var dy: float = b[1] - a[1]
		var ln := JS.hypot(dx, dy)
		var nx := -dy / ln
		var ny := dx / ln
		var swampy: bool = w.provinces[e.a].terrain == "swamp" or w.provinces[e.b].terrain == "swamp"
		var gap := 30.0 if e.style == "mountains" else 38.0 if e.style == "ruins" else 20.0
		var n := maxi(1, int(JS.round_js(ln / gap)))
		for row in [-1, 1]:
			for j in n:
				var t: float = (j + 0.5 + (0.5 if row > 0 else 0.0)) / n
				if t > 1:
					continue
				var off: float = row * (15.0 if e.style == "trees" else 13.0) + (r.next() - 0.5) * 8
				var x: float = a[0] + dx * t + nx * off
				var y: float = a[1] + dy * t + ny * off + 8
				if e.style == "trees":
					var s: String = tree_for.call(swampy) + "_L"
					sway.append({"x": x, "y": y, "s": s, "ph": r.next() * 6.28})
				elif e.style == "palms":
					var s := "palm%d_L" % (0 if r.next() < 0.5 else 1)
					sway.append({"x": x, "y": y, "s": s, "ph": r.next() * 6.28})
				elif e.style == "mountains":
					still.append({"x": x, "y": y + 4, "s": "mtn%d_L" % int(floor(r.next() * 3))})
					if r.next() < 0.3:
						still.append({"x": x + nx * row * 14, "y": y + ny * row * 14 + 10, "s": "mtn1_L"})
				else:
					still.append({"x": x, "y": y, "s": "pillar_L" if r.next() < 0.4 else "arch_L"})
					if r.next() < 0.7:
						var rx: float = x + (r.next() - 0.5) * 24
						still.append({"x": rx, "y": y + 8, "s": "rock%d_L" % (0 if r.next() < 0.5 else 1)})
	var v_swamp := {}
	for p in w.provinces:
		if p.terrain == "swamp":
			for v in p.verts:
				v_swamp[v] = true
	for jn in w.junctions:
		var x: float = V[jn.v][0]
		var y: float = V[jn.v][1]
		if jn.kind == "river":
			continue
		var swampy := v_swamp.has(jn.v)
		if jn.kind == "palms":
			for o in [[-12, 0], [12, 6], [0, 16]]:
				var s := "palm%d_L" % (0 if r.next() < 0.5 else 1)
				sway.append({"x": x + o[0], "y": y + o[1], "s": s, "ph": r.next() * 6.28})
		elif jn.kind == "trees":
			for o in [[-14, 0], [14, 4], [0, 18], [0, -12]]:
				var s: String = tree_for.call(swampy) + "_L"
				sway.append({"x": x + o[0], "y": y + o[1], "s": s, "ph": r.next() * 6.28})
		elif jn.kind == "mountains":
			still.append({"x": x - 10, "y": y + 6, "s": "mtn2_L"})
			still.append({"x": x + 14, "y": y + 16, "s": "mtn1_L"})
			still.append({"x": x + 2, "y": y - 8, "s": "mtn0_L"})
		elif jn.kind == "ruins":
			still.append({"x": x - 8, "y": y + 4, "s": "pillar_L"})
			still.append({"x": x + 12, "y": y + 12, "s": "rock0_L"})
		else:
			still.append({"x": x, "y": y + 6, "s": "rock%d_L" % (0 if r.next() < 0.5 else 1)})
	sway = JS.stable_sort(sway, func(a, b): return signf(a.y - b.y))
	still = JS.stable_sort(still, func(a, b): return signf(a.y - b.y))
	# stepping stones on open borders
	var crossings := []
	for e in w.edges:
		if e.open:
			var a: Array = V[e.v[0]]
			var b: Array = V[e.v[1]]
			crossings.append({"x": (a[0] + b[0]) / 2.0, "y": (a[1] + b[1]) / 2.0, "ang": atan2(b[1] - a[1], b[0] - a[0]), "len": JS.hypot(b[0] - a[0], b[1] - a[1])})
	# lake ripples
	var lake_marks := []
	for l in w.get("lakes", []):
		for poly in l.polys:
			var pts := []
			for v in poly:
				pts.append(V[v])
			var c := WorldPrep.centroid(pts)
			for k in 3:
				var mx: float = c[0] + (r.next() - 0.5) * 130 * WORLD_K
				lake_marks.append({"x": mx, "y": c[1] + (r.next() - 0.5) * 100 * WORLD_K})
	# bounds
	var x0 := INF
	var y0 := INF
	var x1 := -INF
	var y1 := -INF
	for p in provs:
		for q in p.pts:
			x0 = minf(x0, q[0])
			y0 = minf(y0, q[1])
			x1 = maxf(x1, q[0])
			y1 = maxf(y1, q[1])
	# waves and clouds
	var waves := []
	var k := 0
	while waves.size() < 560 * WORLD_K and k < 8000 * WORLD_K:
		k += 1
		var x: float = x0 - 1100 * WORLD_K + r.next() * (x1 - x0 + 2200 * WORLD_K)
		var y: float = y0 - 900 * WORLD_K + r.next() * (y1 - y0 + 1800 * WORLD_K)
		if provs.any(func(p): return JS.hypot(p.c[0] - x, p.c[1] - y) < 340 * WORLD_K):
			continue
		var ph := r.next() * 6.28
		waves.append({"x": x, "y": y, "ph": ph, "s": 2 + r.next() * 1.4})
	var clouds := []
	for i in 5:
		var cx: float = x0 + r.next() * (x1 - x0)
		var cy: float = y0 + r.next() * (y1 - y0)
		var cv := 6 + r.next() * 8
		clouds.append({"x": cx, "y": cy, "v": cv, "s": 0.8 + r.next() * 0.7})
	# gentle darker patches in each province's terrain
	var shade := []
	for p in provs:
		var list := []
		for i in 7:
			var a := r.next() * 6.28
			var r0 := r.next() * 0.6
			var q: Array = p.inner[int(floor(r.next() * p.inner.size()))]
			var rx := 60 + r.next() * 90
			var ry := 40 + r.next() * 60
			list.append({"x": p.ic[0] + (q[0] - p.ic[0]) * r0, "y": p.ic[1] + (q[1] - p.ic[1]) * r0, "rx": rx, "ry": ry, "a": a})
		shade.append(list)
	return {"items": all_items, "sway": sway, "still": still, "crossings": crossings, "lake_marks": lake_marks, "waves": waves,
		"clouds": clouds, "shade": shade, "bounds": [x0, y0, x1, y1]}


## A river as a smooth line: the web's quadratic curves through the midpoints, sampled. web: page.html prep rivers
## The 0.18 terrain variants' extra look, from their own random numbers (the web game's decoration stays as it is):
## golden grass swaying in Drylands, more flowers in a Meadow, more and darker trees in a Fae Forest, big pools in a
## Bog, and mangroves instead of cypresses in the tree bands round a Bog.
static func add_variants(D: Dictionary, w: Dictionary, G: Dictionary, variant: Array) -> void:
	var r := Mulberry32.from_string(str(w.seed) + ":variant-decor")
	var V: Array = w.vertices
	var FAE := Color(0.62, 0.74, 0.7)
	for i in mini(variant.size(), G.provs.size()):
		var v: String = variant[i]
		if v == "":
			continue
		var p: Dictionary = G.provs[i]
		var items: Array = D.items[i]
		if v == "fae":   # the trees already there grow darker too
			for it in items:
				if str(it.s).begins_with("tree") or str(it.s).begins_with("pine"):
					it.m = FAE
		var inner: Array = p.inner
		var ic: Array = p.ic
		var bx0 := INF
		var by0 := INF
		var bx1 := -INF
		var by1 := -INF
		var rs := 0.0
		for q in inner:
			bx0 = minf(bx0, q[0])
			bx1 = maxf(bx1, q[0])
			by0 = minf(by0, q[1])
			by1 = maxf(by1, q[1])
			rs += JS.hypot(q[0] - ic[0], q[1] - ic[1])
		var clear_r := rs / inner.size() * 0.45
		var spot := func(min_gap: float, edge_gap: float):
			for t in 40:
				var x: float = bx0 + r.next() * (bx1 - bx0)
				var y: float = by0 + r.next() * (by1 - by0)
				if not Geo.in_poly(x, y, inner) or Geo.dist_to_edges(x, y, inner) < edge_gap:
					continue
				if JS.hypot(x - ic[0], y - ic[1]) < clear_r:
					continue
				if items.any(func(it): return JS.hypot(it.x - x, it.y - y) < min_gap):
					continue
				return [x, y]
			return null
		match v:
			"meadow":
				for k in 30:
					var at = spot.call(11.0, 10.0)
					if at != null:
						items.append({"x": at[0], "y": at[1], "s": "flower%d" % int(floor(r.next() * 3))})
			"fae":
				for k in 6:
					var at = spot.call(30.0, 26.0)
					if at == null:
						continue
					for j in 3 + int(floor(r.next() * 2)):
						var a: float = j * 2.1 + r.next()
						var rad: float = 11 + r.next() * 4 if j else 0.0
						items.append({"x": at[0] + cos(a) * rad, "y": at[1] + sin(a) * rad * 0.7, "s": ["tree0", "tree1", "pine0", "pine1"][int(floor(r.next() * 4))], "m": FAE})
			"drylands":
				for k in 22:
					var at = spot.call(24.0, 16.0)
					if at != null:
						D.sway.append({"x": at[0], "y": at[1], "s": "goldgrass", "ph": r.next() * 6.28})
			"bog":
				# half its puddles spread into wide pools, swallowing the reeds and lilies beside them
				var pools := []
				for it in items:
					if it.s == "puddle" and r.next() < 0.5 and Geo.dist_to_edges(it.x, it.y, inner) > 40:
						it.s = "bigpuddle"
						pools.append(it)
				items = items.filter(func(it): return it.s == "bigpuddle" or not pools.any(func(q): return absf(q.x - it.x) < 52 and absf(q.y - it.y) < 30))
				# the cypresses on this Bog's tree borders become mangroves
				for e in w.edges:
					if (e.a != i and e.b != i) or e.open or e.style != "trees":
						continue
					var a2 := Vector2(V[e.v[0]][0], V[e.v[0]][1])
					var b2 := Vector2(V[e.v[1]][0], V[e.v[1]][1])
					for it in D.sway:
						if str(it.s).begins_with("cypress") and Geometry2D.get_closest_point_to_segment(Vector2(it.x, it.y - 8), a2, b2).distance_to(Vector2(it.x, it.y - 8)) < 26:
							it.s = "mangrove_L"
		D.items[i] = JS.stable_sort(items, func(a, b): return signf(a.y - b.y))
	D.sway = JS.stable_sort(D.sway, func(a, b): return signf(a.y - b.y))


static func river_points(w: Dictionary, rv: Dictionary) -> PackedVector2Array:
	var V: Array = w.vertices
	var pts := []
	for v in rv.verts:
		pts.append(Vector2(V[v][0], V[v][1]))
	var ext := func(a: Vector2, b: Vector2, d: float) -> Vector2:
		return a + (a - b).normalized() * d
	pts.push_front(ext.call(pts[0], pts[1], 70 * WORLD_K))
	if rv.get("lake") != null:
		pts.append(ext.call(pts[pts.size() - 1], pts[pts.size() - 2], 40 * WORLD_K))
	var out := PackedVector2Array([pts[0]])
	var cur: Vector2 = pts[0]
	for i in range(1, pts.size() - 1):
		var m: Vector2 = (pts[i] + pts[i + 1]) / 2
		for s in range(1, 9):
			var t := s / 8.0
			out.append(cur.lerp(pts[i], t).lerp(pts[i].lerp(m, t), t))
		cur = m
	out.append(pts[pts.size() - 1])
	return out
