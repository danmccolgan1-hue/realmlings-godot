class_name MapView
extends Node2D
## Placeholder map: flat province polygons in the web palette (page.html TER / SEA / OL), barriers as coloured
## lines, then the game on top: settlements and units with the exported art. Only draws; never changes the game.
## The real terrain art comes in Phase 4.

const TER_BASE := {"grassland": Color("#9bd95f"), "forest": Color("#4ba557"), "desert": Color("#f4cd72"), "swamp": Color("#7b9c86")}
const SEA := Color("#2b7fc4")
const SAND := Color("#f2dfa2")
const OL := Color("#1d1a22")
const STYLE_COL := {"mountains": Color("#7d7a86"), "trees": Color("#2b6b35"), "ruins": Color("#9a7b5a"), "river": Color("#55a6dc")}
const STAGE_ART := ["outpost", "fort", "capital"]

var world: Dictionary
var game: Game
var polys := []        # PackedVector2Array per province
var font: Font
var selected_prov := -1
var selected_unit = null    # a unit Dictionary of the game
const FOG_UNEXPLORED := Color("#10182e", 0.86)
const FOG_DIM := Color("#10182e", 0.28)


func set_world(w: Dictionary) -> void:
	world = w
	polys.clear()
	var V: Array = w.vertices
	for p in w.provinces:
		var pts := PackedVector2Array()
		for vi in p.verts:
			pts.append(Vector2(V[vi][0], V[vi][1]))
		polys.append(pts)
	font = ThemeDB.fallback_font
	queue_redraw()


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


func _draw() -> void:
	if world.is_empty():
		return
	var V: Array = world.vertices
	draw_rect(bounds().grow(4000), SEA)
	# beach: thick sand stroke along the coast, under the land
	for p in world.provinces:
		for c in p.coast:
			draw_line(_v(V, c[0]), _v(V, c[1]), SAND, 90.0, true)
			draw_circle(_v(V, c[0]), 45.0, SAND)
			draw_circle(_v(V, c[1]), 45.0, SAND)
	for i in polys.size():
		var terrain: String = game.G.provs[i].terrain if game else world.provinces[i].terrain
		draw_colored_polygon(polys[i], TER_BASE.get(terrain, Color.MAGENTA))
		var outline: PackedVector2Array = polys[i].duplicate()
		outline.append(outline[0])
		draw_polyline(outline, Color(OL, 0.45), 6.0, true)
	for e in world.edges:
		if not e.open:
			draw_line(_v(V, e.v[0]), _v(V, e.v[1]), STYLE_COL.get(e.style, OL), 34.0, true)
	if selected_prov >= 0:
		var outline: PackedVector2Array = polys[selected_prov].duplicate()
		outline.append(outline[0])
		draw_polyline(outline, Color("#fff6c8"), 14.0, true)
	if game:
		_draw_game()
		_draw_fog()
	else:
		for i in world.provinces.size():
			var s: Array = world.provinces[i].site
			draw_string(font, Vector2(s[0], s[1]) + Vector2(-300, 20), "%d %s" % [i, world.provinces[i].terrain], HORIZONTAL_ALIGNMENT_CENTER, 600, 64, OL)


func _draw_game() -> void:
	for p in game.buildings:
		var b: Dictionary = game.buildings[p]
		var P: Dictionary = game.G.provs[p]
		var at := Vector2(P.ic[0], P.ic[1])
		var sp = Art.get_sprite("settlements", "realm", "%s_%s_v%d.png" % [STAGE_ART[b.stage], P.terrain, p % 10])
		if sp:
			Art.draw(self, sp, at)
		else:
			draw_circle(at, 60.0, OL)
		if game.upgrades.has(p):
			var f: float = (game.t - game.upgrades[p].t0) / GameData.c("FORT_UPGRADE").time
			_bar(at + Vector2(0, -150), f, Color("#e8c547"))
	for p in game.extras:
		var ic: Array = game.G.provs[p].ic
		for e in game.extras[p]:
			_building(e.type, e.slot, p, ic, 1.0, e.get("level", 1))
	# units, back to front
	var us: Array = game.units.duplicate()
	us.sort_custom(func(a, b): return a.y < b.y)
	for u in us:
		if u.build != null and u.build.type != "outpost":
			var ic: Array = game.G.provs[u.build.prov].ic
			_building(u.build.type, u.build.slot, u.build.prov, ic, (game.t - u.build.t0) / u.build.dur, 1)
		var kind: String = u.kind
		var n := 0
		if kind == "army":
			for k in u.troops:
				if u.troops[k] > 0:
					if n == 0:
						kind = k
					n += u.troops[k]
		var at := Vector2(u.x, u.y)
		if is_same(u, selected_unit):
			draw_arc(at, 30.0, 0, TAU, 32, Color("#fff6c8"), 5.0)
		var sp = Art.get_sprite("units", "realm", Art.unit_file(kind, _dir(u.th)))
		if sp == null and kind.begins_with("d"):
			sp = Art.get_sprite("units", "realm", Art.unit_file("d-sword", _dir(u.th)))   # Armory designs without art yet
		if sp:
			Art.draw(self, sp, at)
		else:
			draw_circle(at, 18.0, OL)
		if n > 0:
			_badge(at + Vector2(26, -70), str(n))
		if u.survey != null:
			_bar(at + Vector2(0, -60), minf(1.0, (game.t - u.survey.t0) / u.survey.dur), Color("#7fc8f0"))
		elif u.build != null:
			_bar(at + Vector2(0, -60), minf(1.0, (game.t - u.build.t0) / u.build.dur), Color("#e8c547"))
		elif u.scouting != null:
			_bar(at + Vector2(0, -60), minf(1.0, (game.t - u.get("exploreT0", game.t)) / Game.EXPLORE_TIME), Color("#b9e07a"))


## A building on its plot; `f` < 1 while it is being built (the art rises in quarters).
func _building(type: String, slot: int, p: int, ic: Array, f: float, level: int) -> void:
	var o: Array = game.bslot_of(p, slot)
	var at := Vector2(ic[0] + o[0], ic[1] + o[1])
	var base := _building_art(type, level)
	var file := base + ".png"
	if f < 1.0:
		file = base + "_rise%d.png" % (25 if f < 0.375 else 50 if f < 0.625 else 75)
	var sp = Art.get_sprite("buildings", "realm", file)
	if sp:
		Art.draw(self, sp, at)
	else:
		draw_rect(Rect2(at - Vector2(30, 30), Vector2(60, 40)), OL)
	if f < 1.0:
		_bar(at + Vector2(0, -70), f, Color("#e8c547"))


static var _art_names := {}
func _building_art(type: String, level: int) -> String:
	if type in ["forge", "magetower"]:
		return "%s_lv%d" % [type, level]
	if not _art_names.has(type):
		_art_names[type] = type + "_v0"
		for v in ["_v0", "_v1", "_v2"]:
			if Art.get_sprite("buildings", "realm", type + v + ".png") != null:
				_art_names[type] = type + v
				break
	return _art_names[type]


## Art direction from a facing angle (web th: 0 = toward the camera, then clockwise in eighths).
static func _dir(th: float) -> String:
	var k := int(round(th / (PI / 4)))
	return "d%d" % (((-k) % 8 + 8) % 8)


func _draw_fog() -> void:
	for i in polys.size():
		var st := game.fog_state(i)
		if st == "unexplored":
			draw_colored_polygon(polys[i], FOG_UNEXPLORED)
		elif st == "explored":
			draw_colored_polygon(polys[i], FOG_DIM)


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
