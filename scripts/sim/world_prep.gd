class_name WorldPrep
extends RefCounted
## The rules half of page.html prep(w): each province's polygon, inner polygon and drawing centre (ic), coast flags and
## the island's bounds. The decorations prep() also places (tufts, trees, rocks) belong to the view and come later.
## Port the ASSEMBLED page: assemble_game.py rewrites parts of page.html before the game runs them.

const BAND_IN := 50.0   # web: game.js — how far a province's open ground stays clear of a barrier band


# web: page.html centroid(pts)
static func centroid(pts: Array) -> Array:
	var a := 0.0
	var x := 0.0
	var y := 0.0
	var n := pts.size()
	for i in n:
		var p0: Array = pts[i]
		var p1: Array = pts[(i + 1) % n]
		var f: float = p0[0] * p1[1] - p1[0] * p0[1]
		a += f
		x += (p0[0] + p1[0]) * f
		y += (p0[1] + p1[1]) * f
	return [x / (3.0 * a), y / (3.0 * a)]


# web: page.html insetPoly(pts, d, c)
static func inset_poly(pts: Array, d: Array, c: Array) -> Array:
	var n := pts.size()
	var L := []
	for k in n:
		var a: Array = pts[k]
		var b: Array = pts[(k + 1) % n]
		var dx: float = b[0] - a[0]
		var dy: float = b[1] - a[1]
		var l := JS.hypot(dx, dy)
		dx /= l
		dy /= l
		var nx := -dy
		var ny := dx
		var mx: float = (a[0] + b[0]) / 2.0
		var my: float = (a[1] + b[1]) / 2.0
		if (c[0] - mx) * nx + (c[1] - my) * ny < 0:
			nx = -nx
			ny = -ny
		L.append([a[0] + nx * d[k], a[1] + ny * d[k], dx, dy])
	var out := []
	for k in n:
		var o: Array = pts[k]
		var A: Array = L[(k - 1 + n) % n]
		var B: Array = L[k]
		var den: float = A[2] * B[3] - A[3] * B[2]
		var x: float
		var y: float
		if absf(den) < 1e-6:
			x = B[0]
			y = B[1]
		else:
			var t: float = ((B[0] - A[0]) * B[3] - (B[1] - A[1]) * B[2]) / den
			x = A[0] + A[2] * t
			y = A[1] + A[3] * t
		if JS.hypot(x - o[0], y - o[1]) > maxf(d[k], d[(k - 1 + n) % n]) * 3:
			x = o[0] + (c[0] - o[0]) * 0.25
			y = o[1] + (c[1] - o[1]) * 0.25
		out.append([x, y])
	return out


# web: page.html prep(w), without the decorations
static func prep(w: Dictionary) -> Dictionary:
	var V: Array = w.vertices
	var edge_by := {}
	for e in w.edges:
		edge_by[_ek(e.v[0], e.v[1])] = e
	var provs := []
	for p in w.provinces:
		var pts := []
		for v in p.verts:
			pts.append(V[v])
		var c := centroid(pts)
		var kinds := []
		var d := []
		for k in pts.size():
			var e = edge_by.get(_ek(p.verts[k], p.verts[(k + 1) % pts.size()]))
			var kind := "coast" if e == null else ("open" if e.open else "bar")
			kinds.append(kind)
			d.append(6.0 if kind == "open" else BAND_IN if kind == "bar" else 18.0)   # assemble_game.py patches page.html's 4 / 16 / 10
		var inner := inset_poly(pts, d, c)
		var ic := centroid(inner)
		var bars := 0
		for id in p.edges:
			if not w.edges[id].open:
				bars += 1
		var coastal := false
		var lakeside := false
		for q in p.coast:
			if q[2]:
				lakeside = true
			else:
				coastal = true
		provs.append({"id": p.id, "terrain": p.terrain, "pts": pts, "c": c, "inner": inner, "ic": ic, "sides": pts.size(), "borders": p.edges.size(), "bars": bars, "coastal": coastal, "lakeside": lakeside, "kinds": kinds})
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
	return {"provs": provs, "bounds": [x0, y0, x1, y1]}


static func _ek(a: int, b: int) -> String:
	return "%d_%d" % [a, b] if a < b else "%d_%d" % [b, a]
