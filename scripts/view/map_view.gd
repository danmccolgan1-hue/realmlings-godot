class_name MapView
extends Node2D
## The map: MapLayers draws the land, sea, nation borders and fog below; this node draws the game on top
## (roads, walls, the selection, settlements, buildings and units with the exported art). Only draws; never changes
## the game.

const TER_BASE := {"grassland": Color("#9bd95f"), "forest": Color("#4ba557"), "desert": Color("#f4cd72"), "swamp": Color("#7b9c86")}
const SEA := Color("#2b7fc4")
const SAND := Color("#f2dfa2")
const OL := Color("#1d1a22")
const STYLE_COL := {"mountains": Color("#7d7a86"), "trees": Color("#2b6b35"), "ruins": Color("#9a7b5a"), "river": Color("#55a6dc"), "wall": Color("#8a5a34")}
const ROAD_COL := Color("#c9a46a")
const STAGE_ART := ["outpost", "fort", "capital"]

var world: Dictionary
var game: Game
var polys := []        # PackedVector2Array per province
var font: Font
var selected_part := ""   # "settlement" or "<type>@<slot>" when a building is selected
var selected_prov := -1
var selected_unit = null    # the command card's unit (a unit Dictionary of the game)
var selection := []         # every selected unit (box select, Shift-click)
var box := Rect2()          # the selection box being dragged (world)
var marks := []             # where you just sent units: [{x, y, t0}]
var orders: MapOrders
var effects: MapEffects
var layers: MapLayers
var _edge_mid := {}       # "a_b" (both ways) -> the middle of that border, where a road crosses it
const FOG_UNEXPLORED := Color("#10182e", 0.86)
const FOG_DIM := Color("#10182e", 0.28)


func set_world(w: Dictionary) -> void:
	_edge_mid.clear()
	for e in w.edges:
		var m := (_v(w.vertices, e.v[0]) + _v(w.vertices, e.v[1])) / 2
		_edge_mid["%d_%d" % [e.a, e.b]] = m
		_edge_mid["%d_%d" % [e.b, e.a]] = m
	world = w
	polys.clear()
	var V: Array = w.vertices
	for p in w.provinces:
		var pts := PackedVector2Array()
		for vi in p.verts:
			pts.append(Vector2(V[vi][0], V[vi][1]))
		polys.append(pts)
	font = ThemeDB.fallback_font
	if layers == null:
		layers = MapLayers.new()
		layers.z_as_relative = true
		add_child(layers)
	layers.setup(self, w, game.G if game else WorldPrep.prep(w))
	queue_redraw()


## The zoom that fits the whole island on screen.
func fit_zoom() -> float:
	var b := bounds()
	var vs := get_viewport_rect().size
	return minf(vs.x / b.size.x, vs.y / b.size.y) * 0.9


func set_game(g: Game) -> void:
	game = g
	set_world(g.world)


func bounds() -> Rect2:
	var r := Rect2(polys[0][0], Vector2.ZERO)
	for pts in polys:
		for v in pts:
			r = r.expand(v)
	return r


## The province under a world position, or -1.
func province_at(at: Vector2) -> int:
	for i in polys.size():
		if Geometry2D.is_point_in_polygon(at, polys[i]):
			return i
	return -1


func _process(_delta: float) -> void:
	if game:
		queue_redraw()
		layers.refresh()


func _draw() -> void:
	if world.is_empty():
		return
	var V: Array = world.vertices
	if game:
		for k in game.roads:
			var ab: PackedStringArray = k.split("_")
			var a: Array = game.G.provs[int(ab[0])].ic
			var b: Array = game.G.provs[int(ab[1])].ic
			var m: Vector2 = _edge_mid.get(k, Vector2.ZERO)
			_stroke_road(PackedVector2Array([Vector2(a[0], a[1]), m, Vector2(b[0], b[1])]), 1.0)
		# roads and walls being built grow from the Mason's side (web: govtech.js drawLinks)
		for u in game.units:
			var bu = u.get("build")
			if bu == null or not (bu.type in ["road", "wall", "rewall"]) or not (game.explored.has(bu.prov) or game.explored.has(bu.to)):
				continue
			var f := clampf((game.t - bu.t0) / bu.dur, 0.0, 1.0)
			if bu.type == "road":
				var a2: Array = game.G.provs[bu.prov].ic
				var b2: Array = game.G.provs[bu.to].ic
				var m2: Vector2 = _edge_mid.get("%d_%d" % [bu.prov, bu.to], (Vector2(a2[0], a2[1]) + Vector2(b2[0], b2[1])) / 2)
				_stroke_road(PackedVector2Array([Vector2(a2[0], a2[1]), m2, Vector2(b2[0], b2[1])]), f)
			else:
				for e in world.edges:
					if (e.a == bu.prov and e.b == bu.to) or (e.b == bu.prov and e.a == bu.to):
						_wall_edge(_v(V, e.v[0]), _v(V, e.v[1]), f, game.wall_kind() == "stone")
						break
		for i in game.walls:
			var e: Dictionary = world.edges[i]
			if game and not game.explored.has(e.a) and not game.explored.has(e.b):
				continue
			var a := _v(V, e.v[0])
			var b := _v(V, e.v[1])
			var stone: bool = game != null and game.wall_type(i) == "stone"
			_wall_edge(a, b, 1.0, stone)
			if game and game.wall_crack.get(i, false):   # cracked below half health
				var n := maxi(3, int(a.distance_to(b) / 45))
				for k in n:
					var c := a.lerp(b, (k + 0.5) / n)
					draw_polyline(PackedVector2Array([c + Vector2(-4, -24), c + Vector2(5, -12), c + Vector2(-5, -2), c + Vector2(7, 10)]), Color("#2b2620"), 4.0)
			# the gate, in the color of the nation that holds it
			var ctl: int = game.gate_ctl(game.link_key(e.a, e.b)) if game else 0
			var gate := Color(game.player_info(ctl).color) if game and ctl else Color("#3f72d9")
			_gate(a, b, gate)
			if game and game.wall_hp.has(i) and (game.visible.has(e.a) or game.visible.has(e.b)):
				var w := game.wall_life(i)
				if w.hp < w.max - 0.01:   # web: drawWallLife, a health bar over every damaged wall you can see
					var m := (a + b) / 2 + Vector2(0, -120)
					draw_rect(Rect2(m - Vector2(32, 2), Vector2(64, 13)), Color("#1d1a22"))
					draw_rect(Rect2(m - Vector2(30, 0), Vector2(60, 9)), Color("#5a3d2a"))
					draw_rect(Rect2(m - Vector2(30, 0), Vector2(60 * maxf(0, w.hp / w.max), 9)), Color("#e8c33a") if w.hp / w.max > 0.5 else Color("#e0503a"))
	if selected_prov >= 0 and selected_part == "":
		# the selected province: a marching dashed outline (web: game.js drawGame, S.selProv without a part)
		var P: Dictionary = game.G.provs[selected_prov] if game else {}
		var outline := PackedVector2Array()
		for q in (P.inner if game and not P.inner.is_empty() else polys[selected_prov]):
			outline.append(Vector2(q[0], q[1]))
		outline.append(outline[0])
		var z := get_viewport().get_camera_2d().zoom.x if get_viewport().get_camera_2d() else 1.0
		Pen.stroke_line(self, outline, OL, maxf(7, 4 / z))
		_dashes(outline, maxf(4, 2.4 / z), Color("#ffc93c"), 16.0, 10.0, (game.t if game else 0.0) * 20.0)
	if game:
		if orders == null:
			orders = MapOrders.new(self)
		orders.draw_sel_provs(game, game.t)
		_draw_game()


const HOSTILE := Color("#d8473a")


## A dashed line along a polyline; the dashes march by `offset`. (web: setLineDash, lineDashOffset)
func _dashes(pts: PackedVector2Array, w: float, col: Color, on: float, off: float, offset: float) -> void:
	var period := on + off
	var pos := fposmod(-offset, period)   # distance along the line where the pattern starts
	var acc := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var L := a.distance_to(b)
		var s := 0.0
		while s < L:
			var ph := fposmod(acc + s + pos, period)
			var step := minf(L - s, (on - ph) if ph < on else (period - ph))
			if ph < on:
				draw_line(a.lerp(b, s / L), a.lerp(b, (s + step) / L), col, w, true)
			s += maxf(step, 0.01)
		acc += L


## The selected building: a pulsing ring round it. web: game.js drawGame (S.selPart)
func _part_ring() -> void:
	var P: Dictionary = game.G.provs[selected_prov]
	var pulse := 1 + sin(game.t * 4) * 0.03
	var x: float = P.ic[0]
	var y: float = P.ic[1]
	var rx := 42.0
	var ry := 22.0
	if selected_part == "settlement":
		var st: int = game.buildings[selected_prov].stage if game.buildings.has(selected_prov) else 0
		rx = 108.0 if st == 2 else 52.0
		ry = 56.0 if st == 2 else 28.0
	else:
		var slot := int(selected_part.split("@")[1])
		for e in game.extras_in(selected_prov):
			if e.slot == slot:
				var o: Array = game.bslot_of(selected_prov, slot)
				x += o[0]
				y += o[1]
	var ring := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48
		ring.append(Vector2(x + cos(a) * rx * pulse, y + 2 + sin(a) * ry * pulse))
	draw_polyline(ring, OL, 7.0, true)
	draw_polyline(ring, Color("#ffc93c"), 4.0, true)


## The building under a map point: {prov, part} ("settlement" or "<type>@<slot>"), or null.
## web: game.js partAt, buildingAt
func part_at(at: Vector2):
	if game == null:
		return null
	for p in game.extras:
		if not game.visible.has(p):
			continue
		for e in game.extras[p]:
			var c: Array = game.G.provs[p].ic
			var o: Array = game.bslot_of(p, e.slot)
			var x: float = c[0] + o[0]
			var y: float = c[1] + o[1]
			if absf(at.x - x) < 36 and at.y > y - 44 and at.y < y + 20:
				return {"prov": p, "part": "%s@%d" % [e.type, e.slot]}
	for p in game.buildings:
		var b: Dictionary = game.buildings[p]
		if b.owner != Game.ME:
			continue
		var c: Array = game.G.provs[p].ic
		var r := 70.0 if b.stage == 2 else 40.0
		if absf(at.x - c[0]) < r * 1.4 and at.y > c[1] - r * 1.5 and at.y < c[1] + r * 0.75:
			return {"prov": p, "part": "settlement"}
	return null


# --- roads, walls and gates (web: govtech.js strokeRoad, strokePalisade, strokeWall, drawGate) ---

## A road from one province's center over the border's middle to the other's; `f` < 1 while it is being built.
func _stroke_road(pts: PackedVector2Array, f: float) -> void:
	var line := PackedVector2Array([pts[0]])
	if f >= 1.0:
		line = pts
	else:
		var L0 := pts[0].distance_to(pts[1])
		var L1 := pts[1].distance_to(pts[2])
		var left := (L0 + L1) * f
		line.append(pts[0].lerp(pts[1], minf(1.0, left / maxf(L0, 0.01))))
		if left > L0:
			line.append(pts[1].lerp(pts[2], minf(1.0, (left - L0) / maxf(L1, 0.01))))
	if line.size() < 2:
		return
	draw_polyline(line, OL, 26.0, true)
	draw_polyline(line, ROAD_COL, 20.0, true)


func _wall_edge(a: Vector2, b: Vector2, f: float, stone: bool) -> void:
	if stone:
		_stroke_wall(a, b, f)
	else:
		_stroke_palisade(a, b, f)


## Sharpened stakes standing along the border (web: strokePalisade)
func _stroke_palisade(a: Vector2, b: Vector2, f: float) -> void:
	var ex := a.lerp(b, f)
	var u := (b - a).normalized()
	var len := a.distance_to(ex)
	draw_line(a + Vector2(0, -6), ex + Vector2(0, -6), OL, 6.0, true)
	draw_line(a + Vector2(0, -6), ex + Vector2(0, -6), Color("#8a5f3a"), 3.0, true)
	var d := 4.0
	while d < len:
		var x := a + u * d
		var h := 20.0 + (int(d / 9) % 3) * 2
		var stake := PackedVector2Array([x + Vector2(-4, 3), x + Vector2(-4, -h), x + Vector2(0, -h - 6), x + Vector2(4, -h), x + Vector2(4, 3)])
		draw_colored_polygon(stake, Color("#b07a45"))
		var ol := stake.duplicate()
		ol.append(stake[0])
		draw_polyline(ol, OL, 2.0, true)
		draw_rect(Rect2(x + Vector2(-3, -h + 1), Vector2(1.6, h)), Color(1, 1, 1, 0.25))
		d += 9.0


## A stone wall with merlons and round towers at its ends (web: strokeWall)
func _stroke_wall(a: Vector2, b: Vector2, f: float) -> void:
	var ex := a.lerp(b, f)
	var u := (b - a).normalized()
	var len := a.distance_to(ex)
	draw_line(a + Vector2(0, 8), ex + Vector2(0, 8), OL, 22.0, true)
	draw_line(a + Vector2(0, 8), ex + Vector2(0, 8), Color("#8f877a"), 16.0, true)
	draw_line(a, ex, OL, 22.0, true)
	draw_line(a, ex, Color("#cfc8ba"), 16.0, true)
	var d := 10.0
	while d < len - 6:
		var x := a + u * d
		draw_rect(Rect2(x + Vector2(-5, -13), Vector2(10, 9)), Color("#e2dccf"))
		draw_rect(Rect2(x + Vector2(-5, -13), Vector2(10, 9)), OL, false, 2.4)
		d += 20.0
	for x in ([a, b] if f >= 1.0 else [a]):
		_filled_ellipse(x + Vector2(0, -4), 13, 11, Color("#d8d2c4"))
		_ellipse(x + Vector2(0, -4), 13, 11, OL, 3.0)
		_filled_ellipse(x + Vector2(0, -9), 9, 5, Color("#ece6da"))
		_ellipse(x + Vector2(0, -9), 9, 5, OL, 2.0)


func _filled_ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 24:
		var t := TAU * k / 24.0
		pts.append(c + Vector2(cos(t) * rx, sin(t) * ry))
	draw_colored_polygon(pts, col)


## The gatehouse in the middle of a wall: two towers with pennants in the gate holder's color, an arched door
## (web: drawGate)
func _gate(a: Vector2, b: Vector2, col: Color) -> void:
	var m := (a + b) / 2
	var u := (b - a).normalized()
	for sg in [-1.0, 1.0]:
		var x: Vector2 = m + u * 16.0 * sg
		draw_rect(Rect2(x + Vector2(-7, -30), Vector2(14, 32)), Color("#d8d2c4"))
		draw_rect(Rect2(x + Vector2(-7, -30), Vector2(14, 32)), OL, false, 2.6)
		var roof := PackedVector2Array([x + Vector2(-9, -30), x + Vector2(0, -40), x + Vector2(9, -30)])
		draw_colored_polygon(roof, col)
		roof.append(roof[0])
		draw_polyline(roof, OL, 2.6, true)
	var door := PackedVector2Array([m + Vector2(-9, 2), m + Vector2(-9, -14)])
	for k in 9:   # the arch
		var t := k / 8.0
		var p0 := m + Vector2(-9, -14)
		var p1 := m + Vector2(0, -24)
		var p2 := m + Vector2(9, -14)
		door.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	door.append(m + Vector2(9, 2))
	draw_colored_polygon(door, Color("#7b5029"))
	var ol := door.duplicate()
	ol.append(door[0])
	draw_polyline(ol, OL, 2.4, true)
	draw_line(m + Vector2(0, 2), m + Vector2(0, -18), Color(0, 0, 0, 0.3), 1.4)


var landmarks: MapLandmarks
var labels: MapLabels


## A spring that pops a new unit into place: 0 → overshoot → 1 in about a second. web: drawUnitBody / drawArmy
static func _pop(age: float) -> float:
	return maxf(0.01, 1 - exp(-age * 7) * cos(age * 15))


func _is_sel(u) -> bool:
	return is_same(u, selected_unit) or selection.any(func(x): return is_same(x, u))


func _draw_game() -> void:
	if landmarks == null:
		landmarks = MapLandmarks.new(self)
	landmarks.draw_under(game, game.t)
	if effects == null:
		effects = MapEffects.new(self)
	effects.draw_under(game, game.t)
	for p in game.buildings:
		if not game.explored.has(p):
			continue   # other nations' settlements stay hidden under the fog
		var b: Dictionary = game.buildings[p]
		var P: Dictionary = game.G.provs[p]
		var at := Vector2(P.ic[0], P.ic[1])
		var sp = Art.race_sprite("settlements", str(b.get("ccRace")) if b.get("cc", false) and b.get("ccRace") != null else game.race(b.owner), "%s_%s_v%d.png" % [STAGE_ART[b.stage], P.terrain, p % 10])
		if sp:
			Art.draw(self, sp, at)
		else:
			draw_circle(at, 60.0, OL)
		if game.upgrades.has(p):
			var f: float = (game.t - game.upgrades[p].t0) / GameData.c("FORT_UPGRADE").time
			_bar(at + Vector2(0, -150), f, Color("#e8c547"))
	for p in game.extras:
		if not game.explored.has(p):
			continue
		var ic: Array = game.G.provs[p].ic
		for e in game.extras[p]:
			_building(e.type, e.slot, p, ic, 1.0, e.get("level", 1))
	# battles: the melee in the middle of the province (web: game.js drawBattle)
	for b in game.battles:
		if game.visible.has(b.prov):
			effects.draw_battle(game, b, game.t)
	# surveys trace their loop under the units (web: game.js drawSurvey)
	for u in game.units:
		if u.survey != null and (u.owner == Game.ME or game.visible.has(u.prov)):
			orders.draw_survey(game, u.survey, game.t)
	# units, back to front
	var us: Array = game.units.duplicate()
	us.sort_custom(func(a, b): return a.y < b.y)
	for u in us:
		if u.owner != Game.ME and not game.visible.has(u.prov):
			continue   # raiders under the fog stay hidden
		if u.build != null and game.BUILD_DEFS.has(u.build.type) and u.build.get("slot") != null:   # (roads and walls have no plot)
			var ic: Array = game.G.provs[u.build.prov].ic
			_building(u.build.type, u.build.slot, u.build.prov, ic, (game.t - u.build.t0) / u.build.dur, 1)
		if u.kind == "army" and not u.get("monster"):
			_army(u)
			continue
		var kind: String = u.kind
		var n := 0
		if kind == "army":
			for k in u.troops:
				if u.troops[k] > 0:
					if n == 0:
						kind = k
					n += u.troops[k]
		var at := Vector2(u.x, u.y - u.get("flyH", 0.0))   # Winged Slippers lift a flying army
		if u.get("flyH", 0.0) > 0:
			draw_circle(Vector2(u.x, u.y + 4), 30.0, Color(0, 0, 0, 0.22))
		# rings at the feet: yours a thin pulsing one in your color, others' in theirs (bandits and monsters red),
		# the selected one glowing (web: game.js drawUnitBody, ownRing; v78.js selRing)
		var t2: float = game.t
		var big := u.get("monster") != null
		var rrx := (30.0 if big else 16.0) * UK_K
		var rry := (12.0 if big else 6.5) * UK_K
		if u.owner == Game.ME and not _is_sel(u) and not u.get("exiting", false):
			var pulse := 1.0 + sin(t2 * 4 + float(u.id)) * 0.07
			_ellipse(Vector2(u.x, u.y + 1), rrx * pulse, rry * pulse, OL, 3.0)
			_ellipse(Vector2(u.x, u.y + 1), rrx * pulse, rry * pulse, Color(game.player_info(Game.ME).color), 1.6)
		if u.owner != Game.ME:
			var hostile: bool = game.hostile(Game.ME, u.owner)
			var ring: Color = HOSTILE if hostile else Color(game.player_info(u.owner).color)
			_ellipse(Vector2(u.x, u.y + 1), rrx, rry, OL, 4.0)
			_ellipse(Vector2(u.x, u.y + 1), rrx, rry, ring, 2.2)
		if _is_sel(u):
			_sel_ring(Vector2(u.x, u.y + 1), rrx + 1 * UK_K, rry + 0.5 * UK_K, t2)
		# workers hop as they walk, and bob as they build or survey
		var working: bool = u.build != null or u.survey != null
		var walking2: bool = u.moving or u.survey != null
		var ttu: float = t2 * 2.4 if walking2 else t2 * 3.0 if working else t2
		if u.get("monster") == null:
			at.y += -absf(sin(t2 * 9)) * 3.0 if walking2 else -absf(sin(t2 * 8)) * 2.0 if working else 0.0
			at.y -= sin((ttu + u.id) * 3.2) * 1.3 * 0.75   # breathing; faster on the move (web: iso.js humanoid bob)
		# a new unit pops up (web: drawUnitBody born); a sneaking Wayfinder is faint; one marching home is faded
		var usc := _pop(game.t - u.born) if u.get("born") != null and game.t - u.born < 1.2 else 1.0
		var ua := 0.55 if u.get("exiting", false) else (0.45 + sin(t2 * 3) * 0.08) if u.get("stealth", false) else 1.0
		var urc: String = game.race(u.owner)
		var sp = Art.race_sprite("units", urc, Art.unit_file(kind, _dir(u.th)))
		if sp == null and u.get("monster") != null:
			# monsters are drawn facing left or right only (web: art.js monster sprites)
			var side := "d2" if cos(u.th) >= 0 else "d6"
			sp = Art.get_sprite("units", "common", Art.unit_file("monster-" + kind, side))
		if sp == null and kind.begins_with("d"):
			sp = Art.race_sprite("units", urc, Art.unit_file(Art.design_art(game, kind), _dir(u.th)))   # Armory designs without art yet
		if sp:
			Art.draw(self, sp, at, usc, ua)
			if u.kind == game.MAGE:   # v99: the Mage's mana, just over his hat
				var top: float = sp.ay / sp.scale
				_mana_bar(u, u.x, u.y - top - 3.2 * sqrt(UK_K) - 7, 18 * UK_K, UK_K)
		else:
			draw_circle(at, 18.0, OL)
		if n > 0:
			_badge(at + Vector2(26, -70), str(n))
		if u.survey != null:
			_bar(at + Vector2(0, -60), minf(1.0, (game.t - u.survey.t0) / u.survey.dur), Color("#7fc8f0"))
		elif u.build != null:
			_bar(at + Vector2(0, -60), minf(1.0, (game.t - u.build.t0) / u.build.dur), Color("#e8c547"))
		if u.get("fleeing", false) or u.get("doomAt", 0.0):   # running for it (web: content.js drawFleeMark)
			var fp := Vector2(u.x + 12, u.y - 36 + sin(t2 * 10) * 1.5)
			draw_circle(fp, 8, Color("#ff6b5a"))
			draw_arc(fp, 8, 0, TAU, 20, OL, 2.2, true)
			draw_string(font if font else ThemeDB.fallback_font, fp + Vector2(-2, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		elif u.scouting != null:   # exploring: a "?" bubble (web: drawUnitBody)
			var bp := Vector2(u.x + 13 * UK_K, u.y - 34 * UK_K + sin(t2 * 4) * 1.5)
			var tail := PackedVector2Array([bp + Vector2(-4, 6), bp + Vector2(-8, 12), bp + Vector2(0, 7.5)])
			draw_colored_polygon(tail, Color.WHITE)
			draw_circle(bp, 8, Color.WHITE)
			draw_arc(bp, 8, 0, TAU, 20, OL, 2.2, true)
			draw_polyline(tail, OL, 2.2, true)
			draw_string(font if font else ThemeDB.fallback_font, bp + Vector2(-3.5, 4.5), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, OL)
		if working and sin(t2 * 8) > 0.6:   # sparks from the work (web: drawUnitBody)
			for k in 3:
				draw_circle(Vector2(u.x + (12 + k * 3) * UK_K, u.y - (18 + k * 4) * UK_K), 1.8 * UK_K, Color("#fff3a6"))
		if u.get("sieging") != null:   # battering a wall
			_badge(at + Vector2(-30, -70), "⚒")
	if selected_prov >= 0 and selected_part != "":
		_part_ring()
		if selection.is_empty() and game.owned(selected_prov):   # the selected training building's rally point
			var src := "capital" if selected_part == "settlement" and game.buildings[selected_prov].stage == 2 else selected_part.split("@")[0]
			if src in ["capital", "barracks", "magetower"]:
				orders.draw_rally(game, "%s:%d" % [src, selected_prov], game.t)
	effects.draw_over(game, game.t)
	orders.draw_survey_queue(game, game.t)
	orders.draw_scout_marks(game, game.t)
	orders.draw_move_marks()
	if labels == null:
		labels = MapLabels.new(self)
	labels.draw(game, game.t)
	landmarks.draw_over(game)
	orders.draw_box()


# --- armies (web: game.js drawArmy, v78.js armyFigures / drawArmyFlag / drawArmyHealth / drawArmyPower) ---

const UK_K := 1.5   # the web game's unit scale on the map (UKK)


## Up to 10 figures standing for the army's soldiers, shared out between its kinds: infantry in front, then Mages,
## then cavalry. web: v78.js armyFigures
func army_figures(u: Dictionary) -> Array:
	var ks: Array = u.troops.keys().filter(func(k): return u.troops[k] > 0)
	if ks.is_empty():
		return []
	var total := 0
	for k in ks:
		total += u.troops[k]
	var shown := mini(10, total)
	var want := []
	for k in ks:
		var x: float = float(shown) * u.troops[k] / total
		want.append({"k": k, "n": maxi(1, int(floor(x))), "r": fmod(x, 1.0)})
	var sum := 0
	for w in want:
		sum += w.n
	want = JS.stable_sort(want, func(a, b): return b.r - a.r)
	var i := 0
	var guard := 0
	while sum < shown and guard < 100:
		guard += 1
		if want[i].n < u.troops[want[i].k]:
			want[i].n += 1
			sum += 1
		elif want.all(func(w): return w.n >= u.troops[w.k]):
			break
		i = (i + 1) % want.size()
	while sum > shown:
		var big = JS.stable_sort(want.duplicate(), func(a, b): return b.n - a.n)[0]
		if big.n <= 1:
			break
		big.n -= 1
		sum -= 1
	var rank := func(k): return 2 if _is_cav(k) else 1 if k == Game.MAGE else 0
	want = JS.stable_sort(want, func(a, b): return (rank.call(a.k) - rank.call(b.k)) if rank.call(a.k) != rank.call(b.k) else b.n - a.n)
	var out := []
	for w in want:
		for j in w.n:
			out.append(w.k)
	return out


func _is_cav(k: String) -> bool:
	return game.DSTATS.has(k) and game.DSTATS[k].get("cav", false)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for k in 41:
		var a := TAU * k / 40.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, w, true)


func _army(u: Dictionary) -> void:
	var K := UK_K
	var t: float = Time.get_ticks_msec() / 1000.0
	if u.get("battle") != null and not u.get("retreating", false):   # in battle: drawn in the melee (web: drawArmy)
		if _is_sel(u):
			_sel_ring(Vector2(u.x, u.y + 2), 44 * K, 18 * K, t)
		return
	var figs := army_figures(u)
	var n := figs.size()
	if n == 0:
		return
	var per := n if n <= 3 else 4 if n <= 8 else 5
	var rows := ceili(float(n) / per)
	var gx := 15.0 * K
	var gy := 10.0 * K
	var half_w := maxf(18.0 * K, (per - 1) * gx / 2 + 14.0 * K)
	var rx := half_w + 8.0 * K
	var ry := maxf(11.0 * K, rx * 0.4)
	var lift: float = u.get("flyH", 0.0)
	var base := Vector2(u.x, u.y - lift)
	if lift > 0:
		draw_circle(Vector2(u.x, u.y + 4), 30.0, Color(0, 0, 0, 0.22))
	var ring_y := base.y + 2
	if u.owner != Game.ME:   # other nations, bandits and monsters: a ring in their color
		_ellipse(Vector2(base.x, ring_y), rx, ry, OL, 5.0)
		_ellipse(Vector2(base.x, ring_y), rx, ry, Color(game.player_info(u.owner).color), 3.0)
	elif not _is_sel(u):   # yours: a thin pulsing ring in your color (web: ownRing)
		var pulse := 1.0 + sin(t * 4 + float(u.id)) * 0.07
		_ellipse(Vector2(base.x, base.y + 1), rx * pulse, ry * pulse, OL, 3.0)
		_ellipse(Vector2(base.x, base.y + 1), rx * pulse, ry * pulse, Color(game.player_info(Game.ME).color), 1.6)
	if _is_sel(u):
		_sel_ring(Vector2(base.x, base.y + 2), rx + 2 * K, ry + K, t)
	var walking: bool = u.moving or u.get("patrolling", false)
	var hop := -absf(sin(t * 9)) * 3.0 if walking else 0.0
	var tt := t * 2.4 if walking else t
	# a new army pops up; one that just grew swells a little (web: drawArmy born / grew)
	var sc := 1.0
	var born: float = game.t - u.born if u.get("born") != null else 9.0
	var grow: float = game.t - u.grew if u.get("grew") != null else 9.0
	if born < 1.2:
		sc = _pop(born)
	elif grow < 0.6:
		sc = 1 + sin(grow / 0.6 * PI) * 0.15
	var spots := []
	for i in n:
		var r := i / per
		var c := i % per
		var in_row := mini(per, n - r * per)
		spots.append({"k": figs[i], "i": i, "x": base.x + (c - (in_row - 1) / 2.0) * gx + (gx * 0.35 if r % 2 else 0.0), "y": base.y + (rows - 1 - r) * gy - (rows - 1) * gy / 2 + 4 * K})
	spots.sort_custom(func(a, b): return a.y < b.y)
	for sp_ in spots:
		var sp = Art.race_sprite("units", game.race(u.owner), Art.unit_file(sp_.k, _dir(u.th)))
		if sp == null and str(sp_.k).begins_with("d"):
			sp = Art.race_sprite("units", game.race(u.owner), Art.unit_file(Art.design_art(game, sp_.k), _dir(u.th)))
		if sp:
			var bob := -sin((tt + u.id + sp_.i * 0.7) * 3.2) * 1.3 * K * 0.5   # each soldier breathes (web: iso.js humanoid bob)
			Art.draw(self, sp, Vector2(sp_.x, sp_.y + hop + bob), (0.85 if _is_cav(sp_.k) else 1.0) * sc, 0.55 if u.get("exiting", false) else 1.0)
		else:
			draw_circle(Vector2(sp_.x, sp_.y), 8.0, OL)
	var top := base.y - (rows - 1) * gy / 2 + 4 * K - (38.0 if figs.any(func(k): return _is_cav(k)) else 33.0) * K
	_army_flag(u, base.x + half_w + 4 * K, base.y + (rows - 1) * gy / 2 + 2, top - 2 * K, t, K)
	_army_health(u, base.x, top - 5 * K, minf(56 * K, half_w * 1.6), K)
	if game.mages_in(u) > 0:   # v99: an army with Mages shows their mana over its health
		_mana_bar(u, base.x, top - 5 * K - 3.2 * sqrt(K) - 4.5, minf(56 * K, half_w * 1.6), K)
	_army_power(u, Vector2(base.x, base.y + ry + 6 * K))
	if u.survey != null:
		_bar(base + Vector2(0, -60), minf(1.0, (game.t - u.survey.t0) / u.survey.dur), Color("#7fc8f0"))
	if u.get("sieging") != null:
		_badge(Vector2(base.x - half_w - 14, top), "⚒")


## The selection ring: a glowing gold oval with a ripple going out. web: v78.js selRing
func _sel_ring(c: Vector2, rx: float, ry: float, t: float) -> void:
	var pulse := 1 + sin(t * 6) * 0.14
	var ripple := fposmod(t * 0.9, 1.0)
	_ellipse(c, rx * (1 + ripple * 0.6), ry * (1 + ripple * 0.6), Color("#ffe27a", 0.55 * (1 - ripple)), 2.5)
	_ellipse(c, rx * pulse, ry * pulse, Color(1.0, 0.84, 0.35, 0.35), 12.0 + sin(t * 6) * 4)   # (the glow)
	_ellipse(c, rx * pulse, ry * pulse, OL, 6.0)
	_ellipse(c, rx * pulse, ry * pulse, Color("#ffd34d"), 3.6)
	_ellipse(c, rx * pulse, ry * pulse, Color("#fff8d6"), 1.4)


## A caster's mana as a thin blue bar. web: v98.js manaBar
func _mana_bar(c: Dictionary, x: float, y: float, w: float, K: float) -> void:
	var h := 3.2 * sqrt(K)
	var f := clampf(Game.mana_of(c) / maxf(1.0, game.mana_cap(c.owner)), 0, 1)
	var outer := StyleBoxFlat.new()
	outer.bg_color = OL
	outer.set_corner_radius_all(int((h + 3) / 2))
	draw_style_box(outer, Rect2(x - w / 2 - 1.5, y - 1.5, w + 3, h + 3))
	var inner := StyleBoxFlat.new()
	inner.bg_color = Color("#26324a")
	inner.set_corner_radius_all(int(h / 2))
	draw_style_box(inner, Rect2(x - w / 2, y, w, h))
	if f > 0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("#3f7fe8")
		fill.set_corner_radius_all(int(h / 2))
		draw_style_box(fill, Rect2(x - w / 2, y, maxf(h, w * f), h))
		draw_rect(Rect2(x - w / 2 + h / 2, y + 0.5, maxf(0, w * f - h), h * 0.3), Color(1, 1, 1, 0.35))


## The nation's flag on the army's banner pole, waving (web: v78.js drawArmyFlag)
func _army_flag(u: Dictionary, px: float, y_foot: float, y_top: float, t: float, K: float) -> void:
	var fw := 19.0 * K
	var fh := 13.5 * K
	var top := y_top - fh
	draw_line(Vector2(px, y_foot), Vector2(px, top - 3 * K), OL, 4.5)
	draw_line(Vector2(px, y_foot), Vector2(px, top - 3 * K), Color("#c99a2c"), 2.2)
	draw_circle(Vector2(px, top - 4 * K), 2.6 * K + 1.5, OL)
	draw_circle(Vector2(px, top - 4 * K), 2.6 * K, Color("#f4c44f"))
	var tex = nation_flag(u.owner)
	if tex == null:
		draw_rect(Rect2(px + 1, top, fw, fh), Color(game.player_info(u.owner).color))
		return
	var N := 8
	var tw: float = tex.get_width()
	var th: float = tex.get_height()
	for i in N:
		var f := float(i) / N
		var dy := sin(t * 5 - i * 0.7) * 1.8 * K * f
		draw_texture_rect_region(tex, Rect2(px + 1 + f * fw, top + dy, fw / N + 0.6, fh), Rect2(i * tw / N, 0, tw / N + 1, th))


func nation_flag(o: int):
	return Art.nation_flag(game, o)


## A thin health bar over the army (web: v78.js drawArmyHealth)
func _army_health(u: Dictionary, x: float, y: float, w: float, K: float) -> void:
	var full := 0.0
	for k in u.troops:
		if u.troops[k] > 0:
			full += u.troops[k] * game.hp_of(u, k)
	var cur := maxf(0.0, full - u.get("wounds", 0.0))
	var f := clampf(cur / maxf(full, 1.0), 0.0, 1.0)
	var h := 4.2 * sqrt(K)
	draw_rect(Rect2(x - w / 2 - 1.5, y - 1.5, w + 3, h + 3), OL)
	draw_rect(Rect2(x - w / 2, y, w, h), Color("#5a2a26"))
	draw_rect(Rect2(x - w / 2, y, w * f, h), Color("#5cc95c") if f > 0.5 else Color("#e8c547") if f > 0.25 else Color("#e0533f"))


## The army's power under it, in a pill (web: v78.js drawArmyPower, gpc.js powerOf, v96.js fmtPow)
func _army_power(u: Dictionary, at: Vector2) -> void:
	var p := int(round(game.raw_strength([u]) * 10))
	var txt := "⚔ " + (str(p) if p < 2000 else (str(snappedf(p / 1000.0, 0.1)) if p < 10000 else str(int(round(p / 1000.0)))) + "k")
	var k := maxf(1.0, 0.62 / maxf(0.05, get_viewport_transform().get_scale().x))
	var fs := int(9.5 * k * 1.6)
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10 * k
	var h := 13.0 * k * 1.6
	var r := Rect2(at.x - w / 2, at.y - h / 2, w, h)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#f3e4c4", 0.92) if u.owner == Game.ME else Color("#fae0dc", 0.92)
	bg.border_color = OL
	bg.set_border_width_all(maxi(1, int(2 * k)))
	bg.set_corner_radius_all(int(h / 2))
	draw_style_box(bg, r)
	draw_string(font, Vector2(r.position.x, at.y + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs, OL)


## A building on its plot; `f` < 1 while it is being built (the art rises in quarters).
func _building(type: String, slot: int, p: int, ic: Array, f: float, level: int) -> void:
	var o: Array = game.bslot_of(p, slot)
	var at := Vector2(ic[0] + o[0], ic[1] + o[1])
	var brc: String = game.race(game.nation_of(p)) if game.nation_of(p) >= 0 else "realm"
	if type == "pyre":
		brc = "swamp"
	var base := _building_art(type, level, brc)
	var file := base + ".png"
	if f < 1.0:
		file = base + "_rise%d.png" % (25 if f < 0.375 else 50 if f < 0.625 else 75)
	var sp = null
	if f >= 1.0 and not Settings.calm_map:   # finished: its animation (smoke, flags, wheels, crystals), when it has one
		var fr := int(fposmod(Time.get_ticks_msec() / 1000.0 + p * 0.37, BLD_LOOP) / BLD_LOOP * BLD_FRAMES)
		sp = Art.get_sprite("buildings", brc, "%s_a%02d.png" % [base, fr])
	if sp == null:
		sp = Art.get_sprite("buildings", brc, file)
	if sp == null:
		sp = Art.get_sprite("buildings", "realm", file)
	if sp:
		Art.draw(self, sp, at)
	else:
		draw_rect(Rect2(at - Vector2(30, 30), Vector2(60, 40)), OL)
	if f < 1.0:
		_bar(at + Vector2(0, -70), f, Color("#e8c547"))


# the building animations exported from the web art (tools/export_art.js bldanim): 32 frames over two puffs of smoke
const BLD_FRAMES := 32
const BLD_LOOP := 2.0 / 0.35
static var _art_names := {}
func _building_art(type: String, level: int, rc := "realm") -> String:
	if game.BUILD_DEFS.has(type) and game.BUILD_DEFS[type].get("levels") is Array:
		return "%s_lv%d" % [type, level]
	var key := rc + type
	if not _art_names.has(key):
		_art_names[key] = type + "_v0"
		for v in ["_v0", "_v1", "_v2", "_v3"]:
			if Art.get_sprite("buildings", rc, type + v + ".png") != null or Art.get_sprite("buildings", rc, type + v + "_a00.png") != null:
				_art_names[key] = type + v
				break
	return _art_names[key]


## Art direction from a facing angle (web th: 0 = toward the camera, then clockwise in eighths).
static func _dir(th: float) -> String:
	var k := int(round(th / (PI / 4)))
	return "d%d" % (((-k) % 8 + 8) % 8)


func _bar(at: Vector2, f: float, col: Color) -> void:
	var w := 90.0
	draw_rect(Rect2(at - Vector2(w / 2 + 3, 3), Vector2(w + 6, 16)), OL)
	draw_rect(Rect2(at - Vector2(w / 2, 0), Vector2(w * clampf(f, 0, 1), 10)), col)


## The unit drawn nearest a world position (within reach), or null.
func unit_at(at: Vector2):
	var best = null
	var bd := 60.0
	for u in game.units:
		var d := at.distance_to(Vector2(u.x, u.y - 20))
		if d < bd:
			bd = d
			best = u
	return best


func _badge(at: Vector2, txt: String) -> void:
	draw_circle(at, 22.0, OL)
	draw_circle(at, 18.0, Color("#faf1dc"))
	draw_string(font, at + Vector2(-20, 9), txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 26, OL)


static func _v(V: Array, i: int) -> Vector2:
	return Vector2(V[i][0], V[i][1])
