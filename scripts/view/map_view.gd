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
	else:
		for i in world.provinces.size():
			var s: Array = world.provinces[i].site
			draw_string(font, Vector2(s[0], s[1]) + Vector2(-300, 20), "%d %s" % [i, world.provinces[i].terrain], HORIZONTAL_ALIGNMENT_CENTER, 600, 64, OL)


func _draw_game() -> void:
	for p in game.buildings:
		var b: Dictionary = game.buildings[p]
		var P: Dictionary = game.G.provs[p]
		var sp = Art.get_sprite("settlements", "realm", "%s_%s_v%d.png" % [STAGE_ART[b.stage], P.terrain, p % 10])
		if sp:
			Art.draw(self, sp, Vector2(P.ic[0], P.ic[1]))
		else:
			draw_circle(Vector2(P.ic[0], P.ic[1]), 60.0, OL)
	# units, back to front
	var us: Array = game.units.duplicate()
	us.sort_custom(func(a, b): return a.y < b.y)
	for u in us:
		var kind: String = u.kind
		var n := 0
		if kind == "army":
			for k in u.troops:
				if u.troops[k] > 0:
					if n == 0:
						kind = k
					n += u.troops[k]
		var at := Vector2(u.x, u.y)
		var sp = Art.get_sprite("units", "realm", Art.unit_file(kind))
		if sp == null and kind.begins_with("d"):
			sp = Art.get_sprite("units", "realm", Art.unit_file("d-sword"))   # Armory designs without art yet
		if sp:
			Art.draw(self, sp, at)
		else:
			draw_circle(at, 18.0, OL)
		if n > 0:
			_badge(at + Vector2(26, -70), str(n))


func _badge(at: Vector2, txt: String) -> void:
	draw_circle(at, 22.0, OL)
	draw_circle(at, 18.0, Color("#faf1dc"))
	draw_string(font, at + Vector2(-20, 9), txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 26, OL)


static func _v(V: Array, i: int) -> Vector2:
	return Vector2(V[i][0], V[i][1])
