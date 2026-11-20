class_name MapView
extends Node2D
## Placeholder map: flat province polygons in the web palette (page.html TER / SEA / OL), barriers as coloured
## lines, the capital marked. Only draws; never changes the world. The real terrain art comes in Phase 4.

const TER_BASE := {"grassland": Color("#9bd95f"), "forest": Color("#4ba557"), "desert": Color("#f4cd72"), "swamp": Color("#7b9c86")}
const SEA := Color("#2b7fc4")
const SAND := Color("#f2dfa2")
const OL := Color("#1d1a22")
const STYLE_COL := {"mountains": Color("#7d7a86"), "trees": Color("#2b6b35"), "ruins": Color("#9a7b5a"), "river": Color("#55a6dc")}

var world: Dictionary
var polys := []        # PackedVector2Array per province
var font: Font


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


func bounds() -> Rect2:
	var r := Rect2(polys[0][0], Vector2.ZERO)
	for pts in polys:
		for v in pts:
			r = r.expand(v)
	return r


func _draw() -> void:
	if world.is_empty():
		return
	var V: Array = world.vertices
	var b := bounds().grow(4000)
	draw_rect(b, SEA)
	# beach: thick sand stroke along the coast, under the land
	for p in world.provinces:
		for c in p.coast:
			draw_line(_v(V, c[0]), _v(V, c[1]), SAND, 90.0, true)
			draw_circle(_v(V, c[0]), 45.0, SAND)
			draw_circle(_v(V, c[1]), 45.0, SAND)
	for i in polys.size():
		var col: Color = TER_BASE.get(world.provinces[i].terrain, Color.MAGENTA)
		draw_colored_polygon(polys[i], col)
		var outline: PackedVector2Array = polys[i].duplicate()
		outline.append(outline[0])
		draw_polyline(outline, Color(OL, 0.45), 6.0, true)
	for e in world.edges:
		if e.open:
			continue
		draw_line(_v(V, e.v[0]), _v(V, e.v[1]), STYLE_COL.get(e.style, OL), 34.0, true)
	for i in world.provinces.size():
		var s: Array = world.provinces[i].site
		var at := Vector2(s[0], s[1])
		if i == 0:
			draw_circle(at, 70.0, OL)
			draw_circle(at, 55.0, Color("#e8c547"))
		draw_string(font, at + Vector2(-300, 150), "%d %s" % [i, world.provinces[i].terrain], HORIZONTAL_ALIGNMENT_CENTER, 600, 64, OL)


static func _v(V: Array, i: int) -> Vector2:
	return Vector2(V[i][0], V[i][1])
