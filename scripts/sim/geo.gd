class_name Geo
extends RefCounted
## Geometry on a province's open ground (its `inner` polygon from WorldPrep): where units may stand and how they
## walk around bends. Points are [x, y] Arrays, like the web game.


# web: page.html inPoly(x, y, pts)
static func in_poly(x: float, y: float, pts: Array) -> bool:
	var inside := false
	var j := pts.size() - 1
	for i in pts.size():
		var xi: float = pts[i][0]
		var yi: float = pts[i][1]
		var xj: float = pts[j][0]
		var yj: float = pts[j][1]
		if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
			inside = not inside
		j = i
	return inside


# web: page.html distToEdges(x, y, pts)
static func dist_to_edges(x: float, y: float, pts: Array) -> float:
	var d := INF
	var n := pts.size()
	for i in n:
		var a: Array = pts[i]
		var b: Array = pts[(i + 1) % n]
		var dx: float = b[0] - a[0]
		var dy: float = b[1] - a[1]
		var l2 := dx * dx + dy * dy
		var t := maxf(0.0, minf(1.0, ((x - a[0]) * dx + (y - a[1]) * dy) / l2))
		d = minf(d, JS.hypot(x - a[0] - t * dx, y - a[1] - t * dy))
	return d


const STAND_GAP := 14.0


# web: game.js clampInto(prov, x, y): keep a spot on the open ground, away from its edge
static func clamp_into(P: Dictionary, x: float, y: float) -> Array:
	var ok := func(a: float, b: float) -> bool: return in_poly(a, b, P.inner) and dist_to_edges(a, b, P.inner) >= STAND_GAP
	if ok.call(x, y):
		return [x, y]
	var f := 0.08
	while f <= 1:
		var qx: float = x + (P.ic[0] - x) * f
		var qy: float = y + (P.ic[1] - y) * f
		if ok.call(qx, qy):
			return [qx, qy]
		f += 0.08
	return [P.ic[0], P.ic[1]]


# web: game.js segClear(prov, a, b)
static func seg_clear(P: Dictionary, a: Array, b: Array) -> bool:
	var t := 0.12
	while t < 0.9:
		if not in_poly(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, P.inner):
			return false
		t += 0.08
	return true


# web: gpc.js segIn(P, a, b, slackA, slackB)
static func seg_in(P: Dictionary, a: Array, b: Array, slack_a: float, slack_b: float) -> bool:
	var L := JS.hypot(b[0] - a[0], b[1] - a[1])
	var n := maxi(2, ceili(L / 14.0))
	for k in range(1, n):
		var d := L * k / n
		if d < slack_a or L - d < slack_b:
			continue
		if not in_poly(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n, P.inner):
			return false
	return true


# web: gpc.js navNodes(prov): stepping stones on the open ground and which can see which. Cached on P.
static func nav_nodes(P: Dictionary) -> Dictionary:
	if P.has("_nav"):
		return P._nav
	var c: Array = P.ic
	var pts := [[c[0], c[1]]]
	for v in P.inner:
		for f in [0.85, 0.62, 0.38]:
			var q := [c[0] + (v[0] - c[0]) * f, c[1] + (v[1] - c[1]) * f]
			if in_poly(q[0], q[1], P.inner) and dist_to_edges(q[0], q[1], P.inner) >= 12:
				var near := false
				for o in pts:
					if JS.hypot(o[0] - q[0], o[1] - q[1]) < 36:
						near = true
						break
				if not near:
					pts.append(q)
	var vis := []
	for i in pts.size():
		var row := []
		row.resize(pts.size())
		row.fill(false)
		vis.append(row)
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var s := seg_in(P, pts[i], pts[j], 0, 0)
			vis[i][j] = s
			vis[j][i] = s
	P._nav = {"pts": pts, "vis": vis}
	return P._nav


# web: gpc.js navRoute(prov, a, b): the bends to walk through between a and b inside one province
static func nav_route(P: Dictionary, a: Array, b: Array) -> Array:
	var sa := 0.0 if in_poly(a[0], a[1], P.inner) else 44.0
	var sb := 0.0 if in_poly(b[0], b[1], P.inner) else 44.0
	if seg_in(P, a, b, sa, sb):
		return []
	var N := nav_nodes(P)
	var pts: Array = N.pts
	var vis: Array = N.vis
	var n := pts.size()
	var dist := []
	var prev := []
	var done := []
	var to_b := []
	for i in n:
		dist.append(JS.hypot(pts[i][0] - a[0], pts[i][1] - a[1]) if seg_in(P, a, pts[i], sa, 0) else INF)
		prev.append(-1)
		done.append(false)
		to_b.append(seg_in(P, pts[i], b, 0, sb))
	var best := -1
	var best_d := INF
	while true:
		var k := -1
		for i in n:
			if not done[i] and dist[i] < INF and (k < 0 or dist[i] < dist[k]):
				k = i
		if k < 0:
			break
		done[k] = true
		if to_b[k]:
			var d: float = dist[k] + JS.hypot(b[0] - pts[k][0], b[1] - pts[k][1])
			if d < best_d:
				best_d = d
				best = k
		if dist[k] >= best_d:
			break
		for j in n:
			if not done[j] and vis[k][j]:
				var d: float = dist[k] + JS.hypot(pts[j][0] - pts[k][0], pts[j][1] - pts[k][1])
				if d < dist[j]:
					dist[j] = d
					prev[j] = k
	if best < 0:
		return [[P.ic[0], P.ic[1]]]
	var out := []
	var k := best
	while k >= 0:
		out.push_front(pts[k])
		k = prev[k]
	return out
