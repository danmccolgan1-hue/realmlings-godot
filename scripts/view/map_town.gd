class_name MapTown
extends RefCounted
## The houses that grow around a province's buildings and developed settlements, and the townsfolk who walk between
## them (web: content.js syncTowns / housePlace / stepTowns / drawHouse / drawCiv, v106.js devHousePlace). Only
## looks; the rules never read it. Seeded from the map, so the same island has the same village.

const OL := Color("#1d1a22")
const HOUSE_LOOKS := 6
const CIV_SPEED := 24.0
const CK := 1.0   # townsfolk are drawn at their own size in world units (web: drawCiv), smaller than soldiers
const CIV_TUNIC := ["#c8473d", "#3f72d9", "#4b9b4f", "#d9b45a", "#8a5aa8", "#e08a3c", "#6d8fa8", "#b3646f"]
const CIV_SKIN := ["#f2c9a0", "#e0ad82", "#c68a5e", "#9c6a45", "#f5d6b8"]
const SW_CIV := ["#3f6b35", "#5f9a3e", "#93c463", "#3f8a80", "#8a6a44"]
const WD_CIV_TUNIC := ["#c8c6c0", "#6f7f4a", "#3f8f86", "#8a63b8", "#d9cfa8", "#4f6f3c", "#a07ab8"]
const WD_CIV_HAIR := ["#e6e2ef", "#2d2838", "#8a4a3a", "#cfd8e8", "#4a3560", "#d9b85a"]
const WD_SKIN := ["#b9c98a", "#9fb07a", "#a08ab8", "#8a76a8", "#c4b89a"]

var v: Node2D
var houses := {}     # "<prov>@<slot>" or "<prov>@d<level>" -> [{x, y, v, born, prov, n}]
var civs := []
var sig := ""
var dsig := ""
var last_t := -1.0
var civ_z := 0.0
var seed := ""


func _init(view: Node2D) -> void:
	v = view


func reset() -> void:
	houses.clear()
	civs.clear()
	sig = ""
	dsig = ""
	last_t = -1.0
	civ_z = 0.0


# --- geometry (web: inPoly / distToEdges on the province's inner polygon) ---
static func _pts(P: Dictionary) -> Array:
	var poly = P.get("inner", [])
	return poly if poly is Array and not poly.is_empty() else P.get("pts", [])


static func in_poly(x: float, y: float, poly: Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var a = poly[i]
		var b = poly[j]
		if ((a[1] > y) != (b[1] > y)) and x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]:
			inside = not inside
		j = i
	return inside


static func dist_to_edges(x: float, y: float, poly: Array) -> float:
	var best := INF
	for i in poly.size():
		var a := Vector2(poly[i][0], poly[i][1])
		var b := Vector2(poly[(i + 1) % poly.size()][0], poly[(i + 1) % poly.size()][1])
		best = minf(best, Geometry2D.get_closest_point_to_segment(Vector2(x, y), a, b).distance_to(Vector2(x, y)))
	return best


func _ok_spot(g: Game, p: int, x: float, y: float, taken: Array, out: Array, edge: float, plot_gap: float, gap: float) -> bool:
	var P: Dictionary = g.G.provs[p]
	var c: Array = P.ic
	var poly := _pts(P)
	if not in_poly(c[0] + x, c[1] + y, poly) or dist_to_edges(c[0] + x, c[1] + y, poly) < edge:
		return false
	if pow(x / 150.0, 2) + pow(y / 92.0, 2) < 1:   # the settlement
		return false
	for k in GameData.c("BSLOTS").size():
		var q: Array = g.bslot_of(p, k)
		if Vector2(q[0] - x, (q[1] - y) * 1.25).length() < plot_gap:
			return false
	for s in GameData.c("SLOTS"):
		if Vector2(s[0] - x, s[1] - y).length() < 34:
			return false
	if absf(x) < 120 and y > 80 and y < 185:   # the resource and set piece badges
		return false
	for h in taken + out:
		if Vector2(h.x - x, (h.y - y) * 1.3).length() < gap:
			return false
	return true


func _place(g: Game, p: int, slot: int, n: int, taken: Array) -> Array:
	var b: Array = g.bslot_of(p, slot)
	var r := Mulberry32.from_string(seed + ":houses:%d:%d" % [p, slot])
	var out := []
	for i in n:
		for tries in 60:
			var a := r.next() * TAU
			var rad := 52 + r.next() * 38
			var x: float = b[0] + cos(a) * rad
			var y: float = b[1] + sin(a) * rad * 0.75
			if _ok_spot(g, p, x, y, taken, out, 30, 60, 32):
				out.append({"x": roundf(x), "y": roundf(y), "v": int(floor(r.next() * HOUSE_LOOKS))})
				break
	return out


func _place_dev(g: Game, p: int, L: int, n: int, taken: Array) -> Array:
	var r := Mulberry32.from_string(seed + ":devhouses:%d:%d" % [p, L])
	var out := []
	for i in n:
		for tries in 120:
			var a := r.next() * TAU
			var rad := 150 + r.next() * 120 + tries
			var x := cos(a) * rad
			var y := sin(a) * rad * 0.75
			if _ok_spot(g, p, x, y, taken, out, 26, 58, 30):
				out.append({"x": roundf(x), "y": roundf(y), "v": int(floor(r.next() * HOUSE_LOOKS))})
				break
	return out


func _add_civs(g: Game, key: String, p: int, hs: Array, r: Mulberry32, per: int) -> void:
	var c: Array = g.G.provs[p].ic
	for h in hs:
		for j in per:
			civs.append({"key": key, "prov": p, "home": h, "x": c[0] + h.x, "y": c[1] + h.y + 6, "tx": null, "ty": null, "wait": 1 + r.next() * 4,
				"ph": r.next() * 6, "col": Color(CIV_TUNIC[int(r.next() * CIV_TUNIC.size())]), "skin": Color(CIV_SKIN[int(r.next() * CIV_SKIN.size())]),
				"hat": ("straw" if r.next() < 0.5 else "hood") if r.next() < 0.45 else "", "sack": r.next() < 0.3, "born": h.born, "dir": 1})


func _taken(p: int, key: String) -> Array:
	var out := []
	for k in houses:
		if int(k.split("@")[0]) == p and k != key:
			out += houses[k]
	return out


## web: content.js syncTowns + v106.js (three houses for every development level)
func sync(g: Game) -> void:
	seed = str(g.world.seed)
	var parts := []
	for p in g.extras:
		parts.append(str(p) + ":" + ",".join(g.extras[p].map(func(e): return e.type + str(e.slot))))
	var s := "|".join(parts)
	if s != sig:
		sig = s
		var live := {}
		for p in g.extras:
			for e in g.extras[p]:
				var key := "%d@%d" % [p, e.slot]
				live[key] = true
				if houses.has(key) and houses[key].get(0, {}).get("type", "") == e.type:
					continue
				var r := Mulberry32.from_string(seed + ":housecount:" + key)
				var hs := _place(g, p, e.slot, 2 + (1 if r.next() < 0.5 else 0), _taken(p, key))
				var ord := _taken(p, key).size()
				for h in hs:
					h.born = e.get("born", g.t)
					h.prov = p
					h.n = ord
					h.type = e.type
					ord += 1
				houses[key] = hs
				civs = civs.filter(func(cv): return cv.key != key)
				_add_civs(g, key, p, hs, r, 2)
		for k in houses.keys():
			if not k.contains("@d") and not live.has(k):
				houses.erase(k)
				civs = civs.filter(func(cv): return cv.key != k)
	var dparts := []
	for p in g.devel:
		dparts.append("%s:%d" % [p, int(g.devel[p].get("lv", 0))])
	var ds := ",".join(dparts) + "|" + str(houses.size())
	if ds != dsig:
		dsig = ds
		for k in houses.keys():
			if k.contains("@d"):
				var p := int(k.split("@")[0])
				var lv := int(k.split("@d")[1])
				if int(g.devel.get(p, {}).get("lv", 0)) < lv:
					houses.erase(k)
					civs = civs.filter(func(cv): return cv.key != k)
		for p in g.devel:
			for L in range(1, int(g.devel[p].get("lv", 0)) + 1):
				var key := "%d@d%d" % [p, L]
				if houses.has(key):
					continue
				var tk := _taken(int(p), key)
				var hs := _place_dev(g, int(p), L, int(GameData.c("DEV").houses), tk)
				var ord := tk.size()
				for h in hs:
					h.born = g.t
					h.prov = int(p)
					h.n = ord
					h.type = "dev"
					ord += 1
				houses[key] = hs
				_add_civs(g, key, int(p), hs, Mulberry32.from_string(seed + ":devciv:" + key), 1)
		dsig = ",".join(dparts) + "|" + str(houses.size())


func _danger(g: Game, p: int) -> bool:
	if g.occ.has(p) or g.battles.any(func(b): return b.prov == p):
		return true
	var o := g.nation_of(p)
	return o > 0 and g.units.any(func(u): return u.kind == "army" and u.prov == p and g.troop_count(u) > 0 and g.hostile(u.owner, o))


func _target(g: Game, cv: Dictionary) -> void:
	var p: int = cv.prov
	var c: Array = g.G.provs[p].ic
	var r := randf()
	var x: float
	var y: float
	var ex := g.extras_in(p)
	if r < 0.35:
		var hs := _taken(p, "")
		var h: Dictionary = hs[randi() % hs.size()] if not hs.is_empty() else cv.home
		x = c[0] + h.x
		y = c[1] + h.y + 8
	elif r < 0.7 and not ex.is_empty():
		var e: Dictionary = ex[randi() % ex.size()]
		var o: Array = g.bslot_of(p, e.slot)
		x = c[0] + o[0] + (randf() - 0.5) * 30
		y = c[1] + o[1] + 14
	else:
		var st: int = g.buildings[p].stage if g.buildings.has(p) else 0
		var rx := 80.0 if st == 2 else 40.0
		x = c[0] + (randf() - 0.5) * rx * 2
		y = c[1] + (64 if st == 2 else 36) + randf() * 14
	var poly := _pts(g.G.provs[p])
	var k := 0
	while not in_poly(x, y, poly) and k < 10:   # web: clampInto
		x = lerpf(x, c[0], 0.3)
		y = lerpf(y, c[1], 0.3)
		k += 1
	cv.tx = x
	cv.ty = y


## Townsfolk go about their errands; when danger comes they run indoors (web: content.js stepTowns)
func step(g: Game, shown: bool) -> void:
	var dt := 0.0 if last_t < 0 else clampf(g.t - last_t, 0.0, 0.5)
	last_t = g.t
	if dt <= 0:
		return
	for cv in civs:
		if g.t < cv.born:
			continue
		var c: Array = g.G.provs[cv.prov].ic
		if _danger(g, cv.prov):
			if cv.get("inside", false):
				continue
			var hx: float = c[0] + cv.home.x
			var hy: float = c[1] + cv.home.y + 6
			if not shown or not g.visible.has(cv.prov):
				cv.inside = true
				cv.x = hx
				cv.y = hy
				continue
			var d := Vector2(hx - cv.x, hy - cv.y)
			var stp := CIV_SPEED * 3 * dt
			if d.length() <= stp:
				cv.x = hx
				cv.y = hy
				cv.inside = true
				cv.moving = false
				cv.tx = null
			else:
				cv.x += d.x / d.length() * stp
				cv.y += d.y / d.length() * stp
				cv.moving = true
				cv.running = true
				cv.dir = -1 if d.x < 0 else 1
			continue
		if cv.get("inside", false):
			cv.inside = false
			cv.running = false
			cv.tx = null
			cv.wait = 0.4 + randf() * 3
		cv.running = false
		if not shown or not g.visible.has(cv.prov):
			continue
		if cv.wait > 0:
			cv.wait -= dt
			cv.moving = false
			if cv.wait <= 0:
				_target(g, cv)
			continue
		if cv.tx == null:
			_target(g, cv)
		var d := Vector2(cv.tx - cv.x, cv.ty - cv.y)
		var stp := CIV_SPEED * dt
		if d.length() <= stp:
			cv.x = cv.tx
			cv.y = cv.ty
			cv.tx = null
			cv.wait = 1.5 + randf() * 4.5
			cv.moving = false
		else:
			cv.x += d.x / d.length() * stp
			cv.y += d.y / d.length() * stp
			cv.moving = true
			cv.dir = -1 if d.x < 0 else 1


static func _pop(a: float) -> float:
	return maxf(0.01, 1 - exp(-a * 7) * cos(a * 15)) if a < 1.2 else 1.0


func draw_houses(g: Game) -> void:
	for key in houses:
		for h in houses[key]:
			var p: int = h.prov
			if not g.visible.has(p):
				continue
			var c: Array = g.G.provs[p].ic
			var b = g.buildings.get(p)
			var rc: String = g.race(b.owner) if b != null else "realm"
			var own := b != null and int(h.n) % 3 != 2 and str(g.player_info(b.owner).color).to_lower() == "#3f72d9"   # (the roofed art is exported in blue)
			var sp = Art.race_sprite("houses", rc, "house_v%d%s.png" % [h.v, "_owned" if own else ""])
			if sp != null:
				Art.draw(v, sp, Vector2(c[0] + h.x, c[1] + h.y), _pop(g.t - h.born))


func draw_civs(g: Game, t: float) -> void:
	for cv in civs:
		if cv.get("inside", false) or not g.visible.has(cv.prov) or g.t < cv.born:
			continue
		_civ(g, cv, t)


func _civ(g: Game, cv: Dictionary, t: float) -> void:
	var age: float = g.t - cv.born
	var s := maxf(0.01, 1 - exp(-age * 8) * cos(age * 14)) if age < 0.8 else 1.0
	var ph: float = t * (18 if cv.get("running", false) else 9) + cv.ph
	var mv: bool = cv.get("moving", false)
	var sw := sin(ph) * 2.2 if mv else 0.0
	var bob := -absf(sin(ph)) * 1.1 if mv else 0.0
	var rc: String = g.race(g.nation_of(cv.prov)) if g.nation_of(cv.prov) >= 0 else "realm"
	var sx: float = s * cv.get("dir", 1) * (0.88 if rc == "wood" else 1.0)
	var sy: float = s * (1.22 if rc == "wood" else 1.0)
	var at := Vector2(cv.x, cv.y)
	var P := func(x: float, y: float) -> Vector2: return at + Vector2(x * sx, y * sy) * CK
	v.draw_set_transform(Vector2.ZERO)
	_ell(at + Vector2(0, 0.6), 4.6 * s, 1.8 * s, Color(0.11, 0.1, 0.13, 0.22))
	for lx in [[-1.4, sw], [1.4, -sw]]:   # legs
		v.draw_line(P.call(lx[0], -4.6 + bob), P.call(lx[0] + lx[1], 0), OL, 2.8 * s)
		v.draw_line(P.call(lx[0], -4.6 + bob), P.call(lx[0] + lx[1], 0), Color("#5b4a3a"), 1.4 * s)
	var k := int(floor(cv.ph * 7))
	if rc == "wood":   # tall and slender, long hair, long pointed ears, purple eyes
		var skin := Color(WD_SKIN[k % WD_SKIN.size()])
		var tunic := Color(WD_CIV_TUNIC[int(floor(cv.ph * 11)) % WD_CIV_TUNIC.size()])
		var hair := Color(WD_CIV_HAIR[int(floor(cv.ph * 13)) % WD_CIV_HAIR.size()])
		_ellp(P.call(0, -11 + bob), 3.8 * CK * absf(sx), 3.6 * CK * sy, hair)
		_ellp(P.call(0, -7.4 + bob), 3 * CK * absf(sx), 4.2 * CK * sy, tunic)
		for e in [-1, 1]:
			v.draw_colored_polygon(PackedVector2Array([P.call(e * 1.8, -12.6 + bob), P.call(e * 4.4, -17.4 + bob), P.call(e * 2.2, -14.6 + bob)]), skin)
		_ellp(P.call(0, -13.6 + bob), 2.4 * CK * absf(sx), 3 * CK * sy, skin)
		v.draw_rect(Rect2(P.call(0.5, -13.8 + bob), Vector2(CK, 0.9 * CK)), Color("#b26cff"))
		return
	var swf := rc == "swamp"
	var swc := Color(SW_CIV[k % SW_CIV.size()])
	var tunic: Color = swc.darkened(0.28) if swf else cv.col
	var skin: Color = swc if swf else cv.skin
	var off := Vector2(0.8, 1.2) if swf else Vector2.ZERO   # a little hunched
	_ellp(P.call(off.x, -7.6 + bob + off.y), 3.5 * CK * absf(sx), 4.2 * CK * sy, tunic)
	if cv.get("sack", false):
		_ellp(P.call(3.6 + off.x, -6.4 + bob + off.y), 2.2 * CK, 2.2 * CK, Color("#c99560"))
	if swf:
		for e in [-1, 1]:
			v.draw_colored_polygon(PackedVector2Array([P.call(e * 1.6 + off.x, -14 + bob + off.y), P.call(e * 5 + off.x, -15.6 + bob + off.y), P.call(e * 1.8 + off.x, -12.4 + bob + off.y)]), skin)
	_ellp(P.call(off.x, -13.4 + bob + off.y), 2.6 * CK, 2.6 * CK, skin)
	if swf:
		v.draw_rect(Rect2(P.call(0.6 + off.x, -14.2 + bob + off.y), Vector2(CK, CK)), Color("#ff3b2f"))
		return
	if cv.hat == "straw":
		_ellp(P.call(0, -15 + bob), 4.2 * CK, 1.3 * CK, Color("#e8cf7a"))
	elif cv.hat == "hood":
		_ellp(P.call(0, -14.4 + bob), 3 * CK, 1.6 * CK, cv.col)


func _ell(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	v.draw_colored_polygon(pts, col)


# a filled oval with the ink outline
func _ellp(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 18:
		var a := TAU * i / 18
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	v.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	v.draw_polyline(pts, OL, 1.3)
