class_name MapLayers
extends Node2D
## The map below the game, in the web game's order (page.html frame / renderCache as assembled):
## sea and waves · shallows and surf · the island's ink edge · blended terrain · border lines · beaches · lakes ·
## province details · stepping stones · nation borders · border bands · rivers · swaying trees · fog;
## and above the game, the drifting clouds. Only draws; never changes the game.

const OL := Color("#1d1a22")
const SEA := Color("#2b7fc4")
const SHALLOW := Color("#55a6dc")
const FOAM := Color("#d8f1ff")
const SAND := Color("#f2dfa2")
const TER := {"grassland": ["#9bd95f", "#76b744"], "forest": ["#4ba557", "#378243"], "desert": ["#f4cd72", "#d9a94c"], "swamp": ["#7b9c86", "#5d7d69"]}
const PADT := 260.0
const BLEND := 70.0
const FOG_COL := Color("#2f3b55")
const FOG_MS := 0.08      # fog mask texels per world unit

## One drawing pass: calls `paint(self)` in _draw, every frame when `animated`.
class Layer extends Node2D:
	var paint: Callable
	var animated := false
	func _draw() -> void:
		if paint.is_valid():
			paint.call(self)
	func _process(_dt: float) -> void:
		if animated and is_visible_in_tree():
			queue_redraw()

var view: MapView
var w: Dictionary
var G: Dictionary
var D: Dictionary
var polys := []                 # PackedVector2Array per province
var island := []                # outer outlines of the merged land
var surf := []                  # [radius, [PackedVector2Array]] grown island outlines
var coast_segs := []            # [[a, b]] vertex pairs
var terrain_tex: Texture2D
var terrain_at := Rect2()
var river_lines := []
var layers := {}
var fog_vp: SubViewport
var fog_sprite: Sprite2D
var fog_key := ""
var terr_key := ""
var t0 := 0.0


func setup(v: MapView, world: Dictionary, prep: Dictionary) -> void:
	view = v
	w = world
	G = prep
	for c in get_children():
		c.queue_free()
	layers.clear()
	D = MapDecor.build(w, G)
	var V: Array = w.vertices
	polys.clear()
	coast_segs.clear()
	for p in G.provs:
		var pts := PackedVector2Array()
		for q in p.pts:
			pts.append(Vector2(q[0], q[1]))
		polys.append(pts)
	for p in w.provinces:
		for c in p.coast:
			coast_segs.append(c)
	_build_island()
	river_lines = w.get("rivers", []).map(func(rv): return MapDecor.river_points(w, rv))
	t0 = Time.get_ticks_msec() / 1000.0
	_add("sea", -20, _paint_sea, true)
	_add("shore", -19, _paint_shore, true)
	_add("land", -18, _paint_land)
	_add("territory", -17, _paint_territory)
	_add("still", -16, _paint_still)
	_add("rivers", -15, _paint_rivers, true)
	_add("sway", -14, _paint_sway, true)
	_build_fog()
	_add("dim", -12, _paint_dim)
	_add("clouds", 5, _paint_clouds, true)
	_bake_terrain()


func _add(name: String, z: int, paint: Callable, animated := false) -> Layer:
	var L := Layer.new()
	L.name = name
	L.z_index = z
	L.paint = paint
	L.animated = animated
	add_child(L)
	layers[name] = L
	return L


func now() -> float:
	return Time.get_ticks_msec() / 1000.0 - t0


func cam_zoom() -> float:
	var c := get_viewport().get_camera_2d() if is_inside_tree() else null
	return c.zoom.x if c else 0.1


func view_rect(pad: float) -> Rect2:
	var c := get_viewport().get_camera_2d() if is_inside_tree() else null
	if c == null:
		return Rect2(-1e9, -1e9, 2e9, 2e9)
	var size := get_viewport_rect().size / c.zoom
	return Rect2(c.get_screen_center_position() - size / 2, size).grow(pad)


# --- shapes -----------------------------------------------------------------------------------------------------

func _build_island() -> void:
	# the land's outlines are its coasts joined up (lake shores are separate)
	var V: Array = w.vertices
	var segs := coast_segs.map(func(c): return [_v(V, c[0]), _v(V, c[1])])
	island = chains(segs).map(func(ln: PackedVector2Array):
		var q := ln.slice(0, ln.size() - 1) if ln.size() > 2 and ln[0].distance_to(ln[ln.size() - 1]) < 0.01 else ln
		if Geometry2D.is_polygon_clockwise(q):
			q.reverse()
		return q)
	surf.clear()
	for r in [65.0, 33.0, 15.5, 16.75, 18.0, 19.25, 20.5]:
		var grown := []
		for poly in island:
			for q in Geometry2D.offset_polygon(poly, r, Geometry2D.JOIN_ROUND):
				if not Geometry2D.is_polygon_clockwise(q):
					grown.append(q)
		surf.append([r, grown])


static func ellipse(c: Vector2, rx: float, ry: float, a: float, n := 28) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ca := cos(a)
	var sa := sin(a)
	for i in n:
		var u := TAU * i / n
		var x := cos(u) * rx
		var y := sin(u) * ry
		out.append(c + Vector2(x * ca - y * sa, x * sa + y * ca))
	return out


static func closed(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	q.append(p[0])
	return q


func fill(ci: CanvasItem, poly: PackedVector2Array, col: Color) -> void:
	if poly.size() < 3:
		return
	var tri := Geometry2D.triangulate_polygon(poly)
	if tri.is_empty():
		return
	var cols := PackedColorArray()
	cols.resize(poly.size())
	cols.fill(col)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), tri, poly, cols)


# --- terrain: drawn once into an offscreen image, then blurred (web: assemble_game.py "terrain painted once") ---

func _bake_terrain() -> void:
	var b: Array = D.bounds
	var TS := minf(0.5, 2600.0 / maxf(b[2] - b[0], b[3] - b[1]))
	var tw := int(ceil((b[2] - b[0] + PADT * 2) * TS))
	var th := int(ceil((b[3] - b[1] + PADT * 2) * TS))
	var origin := Vector2(b[0] - PADT, b[1] - PADT)
	terrain_at = Rect2(origin, Vector2(tw / TS, th / TS))
	var vp := SubViewport.new()
	vp.size = Vector2i(tw, th)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.disable_3d = true
	var L := Layer.new()
	L.paint = func(ci: CanvasItem):
		for i in polys.size():
			var col := Color(TER[G.provs[i].terrain][0])
			for q in Geometry2D.offset_polygon(polys[i], PADT, Geometry2D.JOIN_ROUND):
				fill(ci, _scaled(q, origin, TS), col)
		for i in polys.size():
			var T: Array = TER[G.provs[i].terrain]
			fill(ci, _scaled(polys[i], origin, TS), Color(T[0]))
			var sh := Color(T[1], 0.35)
			for e in D.shade[i]:
				for q in Geometry2D.intersect_polygons(ellipse(Vector2(e.x, e.y), e.rx, e.ry, e.a), polys[i]):
					fill(ci, _scaled(q, origin, TS), sh)
	vp.add_child(L)
	add_child(vp)
	await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return
	var img := vp.get_texture().get_image()
	vp.queue_free()
	# blur: shrink so one texel spans about the blend distance, then grow back smoothly
	var sigma := BLEND * TS
	var small := Vector2i(maxi(2, int(tw / maxf(1.0, sigma * 0.75))), maxi(2, int(th / maxf(1.0, sigma * 0.75))))
	img.resize(small.x, small.y, Image.INTERPOLATE_LANCZOS)
	img.resize(small.x * 8, small.y * 8, Image.INTERPOLATE_CUBIC)
	terrain_tex = ImageTexture.create_from_image(img)
	layers.land.queue_redraw()


# the offscreen pass draws in image pixels (no transform on the triangle arrays)
static func _scaled(q: PackedVector2Array, origin: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in q:
		out.append((v - origin) * s)
	return out


# --- layers ---------------------------------------------------------------------------------------------------

func _paint_sea(ci: CanvasItem) -> void:
	var b: Array = D.bounds
	ci.draw_rect(Rect2(b[0] - 6000, b[1] - 6000, b[2] - b[0] + 12000, b[3] - b[1] + 12000), SEA)
	var t := now()
	var vr := view_rect(60)
	var lw := maxf(3.0, 1.4 / cam_zoom())
	for wv in D.waves:
		if not vr.has_point(Vector2(wv.x, wv.y)):
			continue
		var bob := sin(t * 1.4 + wv.ph) * 5
		var col := Color(220 / 255.0, 242 / 255.0, 1.0, 0.35 + 0.25 * sin(t * 0.9 + wv.ph * 2))
		var r: float = 5 * wv.s
		ci.draw_arc(Vector2(wv.x - r, wv.y + bob), r, PI * 1.15, PI * 1.85, 6, col, lw)
		ci.draw_arc(Vector2(wv.x + r, wv.y + bob), r, PI * 1.15, PI * 1.85, 6, col, lw)


func _paint_shore(ci: CanvasItem) -> void:
	for q in surf[0][1]:
		fill(ci, q, Color(85 / 255.0, 166 / 255.0, 220 / 255.0, 0.55))
	for q in surf[1][1]:
		fill(ci, q, SHALLOW)
	# the surf breathes: 36 ± 5 wide
	var k := clampi(int(round((sin(now() * 1.8) + 1) * 2)), 0, 4)
	for q in surf[2 + k][1]:
		fill(ci, q, FOAM)
	for poly in island:
		ci.draw_polyline(closed(poly), OL, 8.0, true)


func _paint_land(ci: CanvasItem) -> void:
	var V: Array = w.vertices
	for i in polys.size():
		var pts: PackedVector2Array = polys[i]
		if terrain_tex:
			var uv := PackedVector2Array()
			for v in pts:
				uv.append((v - terrain_at.position) / terrain_at.size)
			ci.draw_polygon(pts, PackedColorArray([Color.WHITE]), uv, terrain_tex)
		else:
			fill(ci, pts, Color(TER[G.provs[i].terrain][0]))
	for e in w.edges:
		ci.draw_line(_v(V, e.v[0]), _v(V, e.v[1]), Color(OL, 0.5), 1.6, true)
	for c in coast_segs:
		var a := _v(V, c[0])
		var b := _v(V, c[1])
		ci.draw_line(a, b, SAND, 24.0)
		ci.draw_circle(a, 12.0, SAND)
		ci.draw_circle(b, 12.0, SAND)
	_paint_lakes(ci)
	for items in D.items:
		for it in items:
			_sprite(ci, it)
	for c in D.crossings:
		ci.draw_set_transform(Vector2(c.x, c.y), c.ang, Vector2.ONE)
		fill(ci, ellipse(Vector2.ZERO, 10, 15, 0, 16), Color("#d9b77a"))
		ci.draw_polyline(closed(ellipse(Vector2.ZERO, 10, 15, 0, 16)), OL, 1.6, true)
		for dy in [-6.0, 6.0]:
			var e := ellipse(Vector2(dy * 0.3, dy), 3.6, 2.6, 0, 10)
			fill(ci, e, Color("#b08a55"))
			ci.draw_polyline(closed(e), OL, 1.1, true)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_lakes(ci: CanvasItem) -> void:
	var V: Array = w.vertices
	for l in w.get("lakes", []):
		for poly in l.polys:
			var pts := PackedVector2Array()
			for v in poly:
				pts.append(_v(V, v))
			# a pale rim inside, a band of foam at the shore, deep water in the middle, an ink edge
			fill(ci, pts, FOAM)
			for q in Geometry2D.offset_polygon(pts, -7.0, Geometry2D.JOIN_ROUND):
				fill(ci, q, Color("#6cbbe8"))
			for q in Geometry2D.offset_polygon(pts, -20.0, Geometry2D.JOIN_ROUND):
				fill(ci, q, Color("#3d97d4"))
			ci.draw_polyline(closed(pts), OL, 4.0, true)
	for m in D.lake_marks:
		var col := Color(220 / 255.0, 242 / 255.0, 1.0, 0.7)
		ci.draw_arc(Vector2(m.x - 6, m.y), 6, PI * 1.15, PI * 1.85, 6, col, 2.5)
		ci.draw_arc(Vector2(m.x + 6, m.y), 6, PI * 1.15, PI * 1.85, 6, col, 2.5)


func _paint_still(ci: CanvasItem) -> void:
	for it in D.still:
		_sprite(ci, it)


func _sprite(ci: CanvasItem, it: Dictionary, rot := 0.0) -> void:
	var sp = Art.get_sprite("map", "common", it.s + ".png")
	if sp == null:
		return
	var s: float = 1.0 / sp.scale
	var at := Vector2(it.x, it.y)
	if rot == 0.0:
		ci.draw_set_transform(at - Vector2(sp.ax, sp.ay) * s, 0.0, Vector2(s, s))
	else:
		ci.draw_set_transform(at + (-Vector2(sp.ax, sp.ay) * s).rotated(rot), rot, Vector2(s, s))
	ci.draw_texture(sp.tex, Vector2.ZERO)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_rivers(ci: CanvasItem) -> void:
	if river_lines.is_empty():
		return
	var ow := maxf(24.0, 18 + 3 / cam_zoom())
	for pts in river_lines:
		ci.draw_polyline(pts, OL, ow, true)
		ci.draw_circle(pts[0], ow / 2, OL)
		ci.draw_circle(pts[pts.size() - 1], ow / 2, OL)
	for pts in river_lines:
		ci.draw_polyline(pts, Color("#45a8e4"), 17.0, true)
		ci.draw_circle(pts[0], 8.5, Color("#45a8e4"))
		ci.draw_circle(pts[pts.size() - 1], 8.5, Color("#45a8e4"))
	# flowing highlights: dashes 10 on, 26 off, moving downstream
	var off := fposmod(now() * 30, 36.0)
	for pts in river_lines:
		var along := -off
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var ln := a.distance_to(b)
			var s := 0.0
			while s < ln:
				var ph := fposmod(along + s, 36.0)
				if ph < 10:
					var e := minf(ln, s + (10 - ph))
					ci.draw_line(a.lerp(b, s / ln), a.lerp(b, e / ln), Color("#c7ecff"), 3.5, true)
					s = e
				else:
					s += 36 - ph
			along += ln


func _paint_sway(ci: CanvasItem) -> void:
	var t := now()
	var vr := view_rect(120)
	for it in D.sway:
		if vr.has_point(Vector2(it.x, it.y)):
			_sprite(ci, it, sin(t * 1.7 + it.ph) * 0.07)


# --- nation borders (web: game.js buildTerritory / drawTerritory) ---------------------------------------------

func _paint_territory(ci: CanvasItem) -> void:
	for c in ci.get_children():
		c.queue_free()
	if view.game == null:
		return
	var g: Game = view.game
	var V: Array = w.vertices
	var P: Dictionary = GameData.c("PLAYERS")
	var by_owner := {}
	for p in g.buildings:
		var o: int = g.buildings[p].owner
		if not by_owner.has(o):
			by_owner[o] = {"area": [], "segs": []}
		by_owner[o].area.append(polys[p])
	for e in w.edges:
		var oa = g.buildings[e.a].owner if g.buildings.has(e.a) else null
		var ob = g.buildings[e.b].owner if g.buildings.has(e.b) else null
		if oa == ob:
			continue
		for o in [oa, ob]:
			if o != null:
				by_owner[o].segs.append([_v(V, e.v[0]), _v(V, e.v[1])])
	for p in g.buildings:
		for c in w.provinces[p].coast:
			by_owner[g.buildings[p].owner].segs.append([_v(V, c[0]), _v(V, c[1])])
	var px := 1.0 / cam_zoom()
	for o in by_owner:
		var T: Dictionary = by_owner[o]
		var col := Color(P[str(o)].color)
		var light := Color(P[str(o)].light)
		var lines := chains(T.segs)
		# the province shapes clip the bands to the inside of the border
		var mask := Layer.new()
		mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		mask.paint = func(m: CanvasItem):
			for q in T.area:
				fill(m, q, Color.WHITE)
		var S := Layer.new()
		S.paint = func(s: CanvasItem):
			for q in T.area:
				fill(s, q, Color(col, 0.05))
			for wa in [[maxf(182, 48 * px), 0.08], [maxf(117, 25 * px), 0.11], [64.0, 0.28], [maxf(18, 9 * px), 1.0]]:
				for ln in lines:
					s.draw_polyline(ln, Color(col, wa[1]), wa[0], true)
			for ln in lines:
				s.draw_polyline(ln, Color(light, 0.9), maxf(4, 2 * px), true)
		mask.add_child(S)
		ci.add_child(mask)
		var E := Layer.new()
		E.paint = func(s: CanvasItem):
			for ln in lines:
				s.draw_polyline(ln, OL, maxf(3.5, 2 * px), true)
		ci.add_child(E)


## Segments joined into continuous lines (web: game.js coastChains)
static func chains(segs: Array) -> Array:
	var at := {}
	var key := func(v: Vector2) -> Vector2i: return Vector2i(roundi(v.x * 16), roundi(v.y * 16))
	for i in segs.size():
		for v in segs[i]:
			var k: Vector2i = key.call(v)
			if not at.has(k):
				at[k] = []
			at[k].append(i)
	var used := []
	used.resize(segs.size())
	used.fill(false)
	var out := []
	for i0 in segs.size():
		if used[i0]:
			continue
		used[i0] = true
		var a: Vector2 = segs[i0][0]
		var b: Vector2 = segs[i0][1]
		var line := PackedVector2Array([a, b])
		# grow forward, then backward
		for dir in 2:
			var v: Vector2 = line[line.size() - 1] if dir == 0 else line[0]
			while true:
				var nxt := -1
				for j in at[key.call(v)]:
					if not used[j]:
						nxt = j
						break
				if nxt < 0:
					break
				used[nxt] = true
				var s2: Array = segs[nxt]
				var wv: Vector2 = s2[1] if key.call(s2[0]) == key.call(v) else s2[0]
				if dir == 0:
					line.append(wv)
				else:
					line.insert(0, wv)
				v = wv
		out.append(line)
	return out


# --- fog (web: game.js renderFog): dark over the unknown, with clouds; explored land and a band of sea along its
# coasts cut out; explored land nobody can see right now dimmed --------------------------------------------------

func _build_fog() -> void:
	var b: Array = D.bounds
	var origin := Vector2(b[0] - 6000, b[1] - 6000)
	var size := Vector2(b[2] - b[0] + 12000, b[3] - b[1] + 12000)
	fog_vp = SubViewport.new()
	fog_vp.size = Vector2i(ceili(size.x * FOG_MS), ceili(size.y * FOG_MS))
	fog_vp.transparent_bg = false
	fog_vp.disable_3d = true
	fog_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var L := Layer.new()
	L.paint = func(ci: CanvasItem):
		ci.draw_rect(Rect2(Vector2.ZERO, Vector2(fog_vp.size)), Color.BLACK)
		if view.game == null:
			ci.draw_rect(Rect2(Vector2.ZERO, Vector2(fog_vp.size)), Color.WHITE)
			return
		var V: Array = w.vertices
		var segs := []
		for i in view.game.explored:
			for q in Geometry2D.offset_polygon(polys[i], 12.0, Geometry2D.JOIN_ROUND):
				fill(ci, _scaled(q, origin, FOG_MS), Color.WHITE)
			for c in w.provinces[i].coast:
				segs.append([_v(V, c[0]), _v(V, c[1])])
		for ln in chains(segs):
			ci.draw_polyline(_scaled(ln, origin, FOG_MS), Color.WHITE, 280 * FOG_MS)
	fog_vp.add_child(L)
	add_child(fog_vp)
	fog_sprite = Sprite2D.new()
	fog_sprite.centered = false
	fog_sprite.position = origin
	fog_sprite.scale = Vector2.ONE / FOG_MS
	fog_sprite.texture = fog_vp.get_texture()
	fog_sprite.z_index = -13
	fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/view/fog.gdshader")
	mat.set_shader_parameter("origin", origin)
	mat.set_shader_parameter("ms", FOG_MS)
	fog_sprite.material = mat
	add_child(fog_sprite)


func _paint_dim(ci: CanvasItem) -> void:
	if view.game == null:
		return
	for i in view.game.explored:
		if not view.game.visible.has(i):
			fill(ci, polys[i], Color(16 / 255.0, 24 / 255.0, 46 / 255.0, 0.38))
			ci.draw_polyline(closed(polys[i]), Color(16 / 255.0, 24 / 255.0, 46 / 255.0, 0.35), maxf(3, 2 / cam_zoom()), true)


## Called every frame by the map: redraws what depends on the game when it changed.
func refresh() -> void:
	var g: Game = view.game
	if g == null:
		return
	var fk := "%s|%s" % [g.explored.keys(), g.visible.keys()]
	if fk != fog_key:
		fog_key = fk
		fog_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		for c in fog_vp.get_children():
			c.queue_redraw()
		layers.dim.queue_redraw()
	var parts := []
	for p in g.buildings:
		parts.append("%d:%d" % [p, g.buildings[p].owner])
	var tk := "%s|%d" % [",".join(parts), int(log(cam_zoom()) * 4)]
	if tk != terr_key:
		terr_key = tk
		layers.territory.queue_redraw()


# --- clouds (web: page.html frame) ------------------------------------------------------------------------------

func _paint_clouds(ci: CanvasItem) -> void:
	var fit := view.fit_zoom()
	var ca := clampf(0.8 - (cam_zoom() / fit - 1) * 0.45, 0, 0.8)
	if ca <= 0.02:
		return
	var b: Array = D.bounds
	var span: float = b[2] - b[0] + 2400
	var t := now()
	for cl in D.clouds:
		var x: float = b[0] - 1200 + fposmod(cl.x - b[0] + 1200 + t * cl.v * 5, span)
		var y: float = cl.y
		var s: float = cl.s * 5.6
		fill(ci, ellipse(Vector2(x + 14 * s, y + 52 * s), 38 * s, 11 * s, 0), Color(Color("#0d3050"), ca * 0.18))
		var puffs := [[0, 0, 22], [-24, 6, 15], [24, 6, 16], [-10, -10, 15], [12, -12, 17]]
		for pf in puffs:
			ci.draw_circle(Vector2(x + pf[0] * s, y + pf[1] * s), pf[2] * s + 2.5 * s, Color(OL, ca))
		for pf in puffs:
			ci.draw_circle(Vector2(x + pf[0] * s, y + pf[1] * s), pf[2] * s - 2.5 * s, Color(1, 1, 1, ca))


static func _v(V: Array, i: int) -> Vector2:
	return Vector2(V[i][0], V[i][1])
