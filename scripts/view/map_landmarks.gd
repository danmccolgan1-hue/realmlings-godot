class_name MapLandmarks
extends RefCounted
## The hand-drawn landmarks on the map: the three unique provinces (Death Mountain, the Desert Oasis, the Heart of
## the Forest), set pieces, ruins and treasure, lost travelers, and the red glow round provinces where bandits or
## monsters have been seen. Ported from the web game's canvas drawing through Pen. Only draws.

const OL := Color("#1d1a22")
const CIV_TUNIC := ["#c8473d", "#3f72d9", "#4b9b4f", "#d9b45a", "#8a5aa8", "#e08a3c", "#6d8fa8", "#b3646f"]
const CIV_SKIN := ["#f2c9a0", "#e0ad82", "#c68a5e", "#9c6a45", "#f5d6b8"]

var view: Node2D
var game: Game
var pen: Pen
var _uq_box := {}
var _sp_spot := {}
var _folk := {}


func _init(v: Node2D) -> void:
	view = v
	pen = Pen.new(v)


static func rgba(r: float, g: float, b: float, a: float) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a)


func _cam_z() -> float:
	var cam := view.get_viewport().get_camera_2d()
	return cam.zoom.x if cam else 1.0


func _on_screen(p: int, pad := 500.0) -> bool:
	var ic: Array = game.G.provs[p].ic
	var cam := view.get_viewport().get_camera_2d()
	if cam == null:
		return true
	var half := view.get_viewport_rect().size / cam.zoom / 2 + Vector2(pad, pad)
	return absf(ic[0] - cam.get_screen_center_position().x) < half.x and absf(ic[1] - cam.get_screen_center_position().y) < half.y


## Everything under the units, in the web game's order: lair glow first, then the landmarks back to front.
## web: game.js drawGame (drawLairGlow, then the depth-sorted items)
func draw_under(g: Game, t: float) -> void:
	game = g
	pen.xf = Transform2D.IDENTITY
	draw_lair_glow(t)
	var items := []
	var U = game.uq()
	if U != null:
		if U.death >= 0 and game.explored.has(U.death):
			items.append({"y": uq_box(U.death).y1 - 40, "f": draw_death_mountain.bind(U.death, t)})
		if U.oasis >= 0 and game.explored.has(U.oasis):
			items.append({"y": game.G.provs[U.oasis].ic[1] - 60, "f": draw_oasis.bind(U.oasis, t)})
		if U.heart >= 0 and game.explored.has(U.heart):
			items.append({"y": game.G.provs[U.heart].ic[1] - 70, "f": draw_heart.bind(U.heart, t)})
	for p in game.setpieces:
		if game.explored.has(p) and game.sp_known(p) and _on_screen(p):
			var c: Array = game.G.provs[p].ic
			var o: Array = sp_spot(p)
			items.append({"y": c[1] + o[1], "f": draw_setpiece_art.bind(game.setpieces[p], c[0] + o[0], c[1] + o[1], t)})
	for p in game.finds:
		var f: Dictionary = game.finds[p]
		if not (game.explored.has(p) and (f.id == "ruins" or f.get("done", false))) or not _on_screen(p):
			continue   # the ruins can be seen from afar; treasure only once found (web: v78.js findKnown)
		var c: Array = game.G.provs[p].ic
		var o: Array = find_spot(p)
		if f.id == "ruins":
			items.append({"y": c[1] + o[1], "f": draw_ruins_art.bind(c[0] + o[0], c[1] + o[1], t, f.get("done", false))})
		else:
			items.append({"y": c[1] + o[1], "f": draw_treasure_art.bind(c[0] + o[0], c[1] + o[1], t)})
	if game.quests_on:   # relics left on the ground: a chest with a gold lock (Godot only)
		for p in game.chests:
			if Quests.chest_seen(game, p) and _on_screen(p):
				var c: Array = game.G.provs[p].ic
				items.append({"y": c[1] + 44, "f": draw_chest_art.bind(c[0] - 48, c[1] + 44, t)})
	for B in game.travelers:
		if game.visible.has(B.prov) and _on_screen(B.prov):
			items.append({"y": B.y, "f": draw_travelers.bind(B, t, B.tx != null)})
	items.sort_custom(func(a, b): return a.y < b.y)
	for it in items:
		pen.xf = Transform2D.IDENTITY
		it.f.call()
	pen.xf = Transform2D.IDENTITY


## Over the units: the set pieces' little "+N" research tags. web: content.js drawSetpieces
func draw_over(g: Game) -> void:
	game = g
	var k := maxf(1.0, 0.62 / _cam_z())
	var font := ThemeDB.fallback_font
	for p in game.setpieces:
		if not game.explored.has(p) or not game.sp_known(p):
			continue
		var D: Dictionary = game.SETPIECES[game.setpieces[p]]
		var P: Dictionary = game.G.provs[p]
		var live: bool = game.owned(p) and not game.occ.has(p) and game.setpiece_on(game.setpieces[p])
		var w := 52 * k
		var h := 26 * k
		var x: float = P.ic[0] - w / 2
		var y: float = P.ic[1] + (150 if game.surveyed.has(p) else 118)
		var a := 1.0 if live else 0.8
		var box := StyleBoxFlat.new()
		box.bg_color = Color(rgba(243, 228, 196, 0.96) if live else rgba(222, 224, 228, 0.94), (0.96 if live else 0.94) * a)
		box.set_corner_radius_all(int(h / 2))
		box.set_border_width_all(int(round(2.6 * k)))
		box.border_color = Color(OL, a)
		box.anti_aliasing = true
		view.draw_style_box(box, Rect2(x, y, w, h))
		var tc: Color = {"gov": Color("#e8c547"), "mil": Color("#d8473a"), "mag": Color("#8a5aff")}.get(D.tree, Color("#aaa"))
		if not live:
			tc = Color("#9aa0aa")
		view.draw_circle(Vector2(x + 15.5 * k, y + h / 2), 7.5 * k, OL)
		view.draw_circle(Vector2(x + 15.5 * k, y + h / 2), 5.8 * k, tc)
		view.draw_string(font, Vector2(x + 27 * k, y + h / 2 + 5.5 * k), "+" + str(D.pts), HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * k), OL if live else Color("#6d7280"))


# --- lairs (web: v78.js drawLairGlow) ---

func draw_lair_glow(t: float) -> void:
	var done := {}
	var z := _cam_z()
	for v in game.units:
		if not v.get("bandit", false) or not v.get("seen", false) or game.troop_count(v) <= 0 or done.has(v.prov) or not game.explored.has(v.prov):
			continue
		done[v.prov] = true
		var P: Dictionary = game.G.provs[v.prov]
		var a := 0.6 + sin(t * 3 + v.prov) * 0.25
		var pts := PackedVector2Array()
		for q in (P.inner if not P.inner.is_empty() else P.pts):
			pts.append(Vector2(q[0], q[1]))
		pts.append(pts[0])
		view.draw_polyline(pts, Color("#a0103a", 0.18 * a), maxf(70, 30 / z), true)
		view.draw_polyline(pts, Color("#a0103a", 0.35 * a), maxf(30, 14 / z), true)
		Pen.stroke_line(view, pts, OL, maxf(9, 5 / z))
		Pen.stroke_line(view, pts, Color("#8c1c3a"), maxf(5.5, 3 / z))
		view.draw_polyline(pts, Color("#ff9ab8", 0.7 * a), maxf(2, 1.2 / z), true)


# --- the unique provinces (web: v95.js uqBox, drawDeathMountain, drawOasis, drawHeart) ---

func uq_box(p: int) -> Dictionary:
	if _uq_box.has(p) and _uq_box[p].seed == game.world.seed:
		return _uq_box[p]
	var P: Dictionary = game.G.provs[p]
	var src: Array = P.inner if not P.inner.is_empty() else P.pts
	var pts := []
	var x0 := INF
	var y0 := INF
	var x1 := -INF
	var y1 := -INF
	for q in src:
		pts.append(Vector2(q[0], q[1]))
		x0 = minf(x0, q[0]); y0 = minf(y0, q[1]); x1 = maxf(x1, q[0]); y1 = maxf(y1, q[1])
	_uq_box[p] = {"seed": game.world.seed, "x0": x0, "y0": y0, "x1": x1, "y1": y1, "pts": pts}
	return _uq_box[p]


func draw_death_mountain(p: int, t: float) -> void:
	var B := uq_box(p)
	var w: float = B.x1 - B.x0
	var h: float = B.y1 - B.y0
	var cx: float = (B.x0 + B.x1) / 2
	var H := maxf(w, h) * 0.85
	var pts: Array = B.pts
	var n := pts.size()
	# the massif sits on the province's own lower borders; only the ridge rises above the province
	var iL := 0
	var iR := 0
	for i in n:
		if pts[i].x < pts[iL].x: iL = i
		if pts[i].x > pts[iR].x: iR = i
	var chain := func(from: int, to: int, step: int) -> Array:
		var out := []
		var i := from
		while true:
			out.append(pts[i])
			if i == to:
				break
			i = (i + step + n) % n
		return out
	var a1: Array = chain.call(iR, iL, 1)
	var a2: Array = chain.call(iR, iL, -1)
	var avg := func(c: Array) -> float:
		var s := 0.0
		for q in c:
			s += q.y
		return s / c.size()
	var foot: Array = a1 if avg.call(a1) > avg.call(a2) else a2
	var xL: float = pts[iL].x
	var yL: float = pts[iL].y
	var xR: float = pts[iR].x
	var yR: float = pts[iR].y
	var by := -INF
	for q in foot:
		by = maxf(by, q.y)
	var X := func(f: float) -> float: return xL + (xR - xL) * f
	var Y := func(f: float, kk: float) -> float: return yL + (yR - yL) * f - H * kk
	var prof := [[0.06, 0.18], [0.12, 0.26], [0.18, 0.48], [0.24, 0.66], [0.28, 0.62], [0.33, 0.7], [0.38, 0.6], [0.44, 0.82], [0.5, 1], [0.55, 0.9], [0.6, 0.84], [0.66, 0.68], [0.72, 0.76], [0.76, 0.72], [0.82, 0.52], [0.88, 0.36], [0.94, 0.2]]
	var outline := PackedVector2Array()
	for q in foot:
		outline.append(q)
	for fk in prof:
		outline.append(Vector2(X.call(fk[0]), Y.call(fk[0], fk[1])))
	pen.begin().poly(outline).fill(Color("#211d22")).stroke(8, OL)
	# lit faces on the left of each summit, deep shadow on the right
	for s in [[0.24, 0.66], [0.5, 1.0], [0.72, 0.76]]:
		var tx: float = X.call(s[0])
		var ty: float = Y.call(s[0], s[1])
		pen.begin().move(tx, ty).line(X.call(s[0] - 0.24), by + 20).line(X.call(s[0] - 0.03), by + 20).close().fill_in(outline, rgba(150, 140, 165, 0.2))
		pen.begin().move(tx, ty).line(X.call(s[0] + 0.03), by + 20).line(X.call(s[0] + 0.26), by + 20).close().fill_in(outline, Color(0, 0, 0, 0.3))
		pen.begin().move(tx, ty).line(X.call(s[0] + 0.01), by + 20).stroke_in(outline, 2.5, Color(0, 0, 0, 0.5))
	# strata
	for kk in range(1, 7):
		var y := by - H * kk * 0.14
		pen.begin().move(xL - 20, y + sin(kk) * 10).quad(cx, y - 18, xR + 20, y + cos(kk) * 10, 16).stroke_in(outline, 3, rgba(90, 80, 100, 0.35))
	# glowing lava running down from the summit
	var glow := 0.65 + sin(t * 2) * 0.2
	var top := Vector2(X.call(0.5), Y.call(0.5, 1))
	for dk in [[-0.06, 0], [0.04, 1], [0.12, 2], [-0.14, 3], [0.2, 4]]:
		var x: float = top.x + dk[0] * w * 0.1
		var y: float = top.y + H * (0.08 + dk[1] * 0.04)
		pen.begin().move(x, y)
		for s2 in 9:
			x += dk[0] * w * 0.1 + sin(s2 * 2.1 + dk[1]) * 12
			y += H * 0.11
			pen.line(x, y)
		pen.stroke_in(outline, 9, rgba(255, 80 + dk[1] * 18, 30, glow))
		pen.stroke_in(outline, 3, rgba(255, 225, 130, 0.85))
	# the crater glows; ash and smoke rise
	pen.begin().ellipse(top.x, top.y + 8, 22, 8).fill(rgba(255, 120, 40, glow))
	pen.glow(top.x, top.y, 90, 90, rgba(255, 110, 40, 0.45 * glow))
	for i in 7:
		var ph := fposmod(t * 0.12 + i / 7.0, 1.0)
		var x := top.x + sin(i * 1.7 + t * 0.5) * 24 + ph * 90
		var y := top.y - 24 - ph * H * 0.45
		view.draw_circle(Vector2(x, y), 22 + ph * 60, rgba(42, 38, 46, 0.6 * (1 - ph)))


func draw_oasis(p: int, t: float) -> void:
	var c: Array = game.G.provs[p].ic
	var x: float = c[0]
	var y: float = c[1] - 70
	# a ring of green, then the water
	pen.begin().ellipse(x, y, 150, 72).fill(Color("#7cc25a")).stroke(4, OL)
	pen.begin().ellipse(x, y + 2, 112, 50).fill(Color("#3fa8d8")).stroke(4, OL)
	pen.begin().ellipse(x - 20, y - 10, 60, 18).fill(Color(1, 1, 1, 0.18))
	for i in 4:
		var ph := fposmod(t * 0.4 + i / 4.0, 1.0)
		pen.begin().ellipse(x + 20, y + 6, 20 + ph * 60, 8 + ph * 22, 0.3, 2.6).stroke(2.5, rgba(220, 245, 255, 0.8 * (1 - ph)))
	# reeds and palms around the water
	for o in [[-118, 10], [-96, 34], [104, 30], [124, 4], [60, 52], [-40, 52]]:
		for kk in [-1, 0, 1]:
			pen.begin().move(x + o[0] + kk * 4, y + o[1]).quad(x + o[0] + kk * 7, y + o[1] - 14, x + o[0] + kk * 9 + sin(t * 2 + o[0]) * 2, y + o[1] - 22).stroke(2.4, Color("#3f8a3a"))
	for o in [[-140, -40, 1.5], [128, -36, 1.4], [-70, -62, 1.2], [80, -64, 1.3], [0, -72, 1.1]]:
		var sp = Art.get_sprite("map", "common", "palm%d_L.png" % (1 if o[0] > 0 else 0))
		if sp:
			Art.draw(view, sp, Vector2(x + o[0], y + o[1]), o[2] / 2.0)


func draw_heart(p: int, t: float) -> void:
	var c: Array = game.G.provs[p].ic
	var x: float = c[0]
	var y: float = c[1] - 60
	# mossy clearing with a glowing pool of light and a vast ancient tree
	pen.begin().ellipse(x, y + 40, 150, 56).fill(Color("#4f9a3f")).stroke(4, OL)
	var pulse := 0.5 + sin(t * 1.6) * 0.15
	pen.glow(x, y + 40, 150, 56, rgba(220, 255, 170, pulse))
	# roots
	for s in [-1, 1]:
		for kk in [0, 1]:
			pen.begin().move(x + s * 20, y + 30).quad(x + s * (50 + kk * 20), y + 36 + kk * 6, x + s * (80 + kk * 30), y + 52 + kk * 8)
			pen.stroke(14 - kk * 4, OL).stroke(9 - kk * 4, Color("#7b5029"))
	# the trunk
	pen.begin().move(x - 34, y + 36).quad(x - 26, y - 60, x - 18, y - 150).line(x + 18, y - 150).quad(x + 26, y - 60, x + 34, y + 36).close()
	pen.fill(Color("#8a5a34")).stroke(5, OL)
	for dx in [-14, 0, 12]:
		pen.begin().move(x + dx, y + 30).quad(x + dx + 6, y - 50, x + dx - 2, y - 140).stroke(2.5, Color("#5e3b1e"))
	# a glowing heart-shaped knot
	var hx := x
	var hy := y - 40
	pen.begin().move(hx, hy + 12).bez(hx - 18, hy, hx - 12, hy - 16, hx, hy - 8).bez(hx + 12, hy - 16, hx + 18, hy, hx, hy + 12)
	pen.fill(rgba(190, 255, 140, 0.6 + pulse * 0.4)).stroke(2.5, OL)
	# the crown
	for cr in [[-80, -170, 50, "#2f7a35"], [80, -168, 52, "#2f7a35"], [-40, -220, 60, "#3f8a3a"], [40, -222, 58, "#3f8a3a"], [0, -190, 62, "#4f9a3f"], [0, -260, 46, "#5fae4a"]]:
		pen.begin().arc(x + cr[0], y + cr[1] + sin(t + cr[0]) * 2, cr[2]).fill(Color(cr[3])).stroke(4, OL)
	# fireflies
	for i in 10:
		var a := t * 0.6 + i * 0.63
		view.draw_circle(Vector2(x + cos(a) * (60 + i * 8), y - 60 + sin(a * 1.3) * 60), 3, rgba(230, 255, 150, 0.5 + 0.5 * sin(t * 4 + i)))


# --- set pieces (web: gpc.js spSpot, drawSetpieceArt) ---

func sp_spot(p: int) -> Array:
	if _sp_spot.has(p) and _sp_spot[p].seed == game.world.seed:
		return _sp_spot[p].at
	var P: Dictionary = game.G.provs[p]
	var c: Array = P.ic
	var r := Mulberry32.from_string(str(game.world.seed) + ":setpiece-spot:" + str(p))
	var plots := []
	for kk in GameData.c("BSLOTS").size():
		plots.append(game.bslot_of(p, kk))
	var SL: Array = GameData.c("SLOTS")
	var best = null
	var bs := -INF
	for tries in 120:
		var a := r.next() * PI * 2
		var rad := 150 + r.next() * 170
		var x := cos(a) * rad
		var y := sin(a) * rad * 0.8
		if not Geo.in_poly(c[0] + x, c[1] + y, P.inner):
			continue
		var edge := Geo.dist_to_edges(c[0] + x, c[1] + y, P.inner)
		if edge < 36:
			continue
		if pow(x / 165, 2) + pow(y / 105, 2) < 1:
			continue   # the settlement
		if absf(x) < 130 and y > 70 and y < 200:
			continue   # the resource and set piece badges
		var d_plot := INF
		for q in plots:
			d_plot = minf(d_plot, Vector2(q[0] - x, (q[1] - y) * 1.25).length())
		var d_slot := INF
		for q in SL:
			d_slot = minf(d_slot, Vector2(q[0] - x, q[1] - y).length())
		var sc := minf(d_plot, 140) + minf(d_slot, 80) * 0.5 + minf(edge, 80) * 0.3
		if sc > bs:
			bs = sc
			best = [roundf(x), roundf(y)]
		if d_plot > 110 and d_slot > 60 and edge > 60:
			break
	if best == null:
		best = [-130.0, -150.0]
	_sp_spot[p] = {"seed": game.world.seed, "at": best}
	return best


## The landmark's spot: the set piece spot, or its mirror image if a set piece already stands there. web: v78.js findSpot
func find_spot(p: int) -> Array:
	var s := sp_spot(p)
	return [-s[0], s[1]] if game.setpieces.has(p) and game.sp_known(p) else s


func draw_setpiece_art(id: String, x: float, y: float, t: float) -> void:
	pen.push().at(x, y)
	pen.begin().ellipse(0, 4, 46, 13).fill(Color(0, 0, 0, 0.25))
	if id == "battlesite":
		# a sandy barrow with old blades, a broken shield and bones
		pen.begin().ellipse(0, 0, 44, 15, PI, TAU).line(44, 0).ellipse(0, 0, 44, 8, 0, PI).close().fink(Color("#e2c487"))
		for b in [[-18, -0.25, 40], [6, 0.18, 46], [24, 0.4, 34]]:
			var hh: float = b[2]
			pen.push().at(b[0], -6).turn(b[1])
			pen.begin().move(-2.5, 0).line(-2.5, -hh).line(0, -hh - 6).line(2.5, -hh).line(2.5, 0).close().fink(Color("#a9a39a"), 2)
			pen.begin().move(-1, -4).line(-1, -hh + 4).stroke(1, rgba(140, 70, 30, 0.6))
			pen.begin().rect(-8, -hh * 0.2 - 3, 16, 4).fink(Color("#8a5f3a"), 1.8)
			pen.pop()
		pen.push().at(-34, -6).turn(-0.5)
		pen.begin().ellipse(0, 0, 11, 14).fink(Color("#9a4b3a"), 2.2)
		pen.begin().move(-2, -12).line(3, -2).line(-1, 6).stroke(2, Color("#e2c487"))
		pen.pop()
		pen.begin().arc(30, -4, 6.5).fink(Color("#f3ead6"), 2)
		pen.begin().arc(28, -5, 1.4).fill(OL)
		pen.begin().arc(32.5, -5, 1.4).fill(OL)
		pen.begin().move(-6, 2).line(10, 4).stroke(5, OL).stroke(3, Color("#f3ead6"))
	elif id == "library":
		# a crumbling stone library with a broken roof, columns and fallen scrolls
		pen.begin().move(-38, 0).line(-38, -44).line(-20, -44).line(-14, -52).line(-4, -46).line(8, -58).line(20, -48).line(38, -48).line(38, 0).close().fink(Color("#c9c2b4"))
		pen.begin().rect(-38, -12, 76, 12).fill(Color(0, 0, 0, 0.12))
		for cx in [-28, 28]:
			pen.begin().rect(cx - 4, -40, 8, 40).fink(Color("#e4ddcf"), 2)
		pen.begin().move(-11, 0).line(-11, -22).quad(0, -36, 11, -22).line(11, 0).close().fink(Color("#3a3240"), 2.2)
		for bk in [[-18, -30, "#c8473d"], [16, -32, "#3f72d9"]]:
			pen.begin().rect(bk[0] - 3, bk[1], 6, 10).fink(Color(bk[2]), 1.5)
		pen.begin().move(-36, -44).quad(-30, -30, -36, -18).stroke(3, Color("#5fae4a"))
		for sc in [[-22, 4, 0.3], [20, 5, -0.4], [32, 2, 0.9]]:
			pen.push().at(sc[0], sc[1]).turn(sc[2])
			pen.begin().rect(-7, -3, 14, 6).fink(Color("#f3ead6"), 1.6)
			pen.pop()
	else:
		# a closed rift: a dark seam in the air, ringed by floating stones, softly glowing
		var glow := 0.55 + 0.25 * sin(t * 2.2)
		pen.begin().ellipse(0, 0, 36, 11).fink(Color("#6b5b7a"), 2.2)
		pen.begin().move(-26, -1).line(-12, 2).line(0, -2).line(14, 3).line(28, 0).stroke(2, Color("#2a2230"))
		pen.glow(0, -34, 30, 38, rgba(230, 210, 255, glow))
		pen.begin().move(0, -66).quad(9, -48, 3, -34).quad(-6, -20, 0, -4).quad(-11, -20, -5, -34).quad(1, -48, 0, -66).close().fink(Color("#2b1d45"), 2.4)
		pen.begin().move(0, -60).quad(4, -46, 0, -34).stroke(1.6, rgba(200, 170, 255, glow))
		for kk in 4:
			var a := t * 0.8 + kk * PI / 2
			var sx := cos(a) * 26
			var sy := -34 + sin(a) * 9 - 4 * sin(t * 1.5 + kk)
			pen.begin().move(sx - 5, sy).line(sx, sy - 5).line(sx + 5, sy).line(sx, sy + 4).close().fink(Color("#8a8f9b"), 1.6)
	pen.pop()


# --- ruins and treasure (web: v78.js drawRuinsArt, drawTreasureArt) ---

func draw_ruins_art(x: float, y: float, t: float, done: bool) -> void:
	var ST := Color("#cfc8b6")
	var STD := Color("#a9a190")
	var MOSS := Color("#6aa84f")
	pen.push().at(x, y).grow(1.25)
	pen.begin().ellipse(0, 6, 58, 16).fill(Color(0, 0, 0, 0.25))
	# stepped platform
	for st in [[56, 7, 0], [48, 7, -7], [40, 6, -14]]:
		pen.begin().rect(-st[0], st[2] - st[1], st[0] * 2, st[1]).fink(STD if st[2] == 0 else ST, 2.2)
	# back wall with a doorway
	pen.begin().move(-30, -20).line(-30, -58).line(30, -58).line(30, -20).close().fink(STD, 2.2)
	pen.begin().move(-9, -20).line(-9, -40).quad(0, -50, 9, -40).line(9, -20).close().fink(Color("#2d2a26"), 2)
	if not done:
		pen.begin().ellipse(0, -28, 5, 7).fill(rgba(255, 226, 122, 0.4 + 0.25 * sin(t * 2)))
	# pediment, broken on the right
	pen.begin().move(-38, -58).line(-38, -64).line(0, -82).line(14, -75).line(18, -70).line(24, -66).line(38, -64).line(38, -58).close().fink(ST, 2.4)
	pen.begin().arc(-4, -67, 4).fink(STD, 1.6)
	# columns: two whole, one broken, one fallen
	for cl in [[-38, 34], [-22, 34], [22, 34]]:
		var cx: float = cl[0]
		var h: float = cl[1]
		pen.begin().rect(cx - 5, -20 - h, 10, h).fink(Color("#e4ddcf"), 2)
		pen.begin().rect(cx - 7, -24 - h, 14, 4).fink(ST, 1.8)
		for dx in [-2, 2]:
			pen.begin().move(cx + dx, -20).line(cx + dx, -20 - h + 2).stroke(1, Color(OL, 0.35))
	pen.begin().move(33, -20).line(33, -36).line(36, -40).line(39, -35).line(43, -38).line(43, -20).close().fink(Color("#e4ddcf"), 2)
	pen.push().at(44, 2).turn(-0.12)
	pen.begin().rect(-6, -5, 26, 9).fink(Color("#e4ddcf"), 2)
	pen.pop()
	# vines and moss
	for v in [[-36, -58, -34], [-20, -58, -40], [26, -66, -46]]:
		pen.begin().move(v[0], v[1]).quad(v[0] + 5, (v[1] + v[2]) / 2.0, v[0] - 1, v[2]).stroke(2.6, MOSS)
	for m in [[-48, -2, 6], [40, -6, 5], [-10, -60, 5], [18, -4, 4]]:
		pen.begin().ellipse(m[0], m[1], m[2] * 1.4, m[2] * 0.7).fink(MOSS, 1.4)
	# swamp water at the foot
	pen.begin().ellipse(-46, 8, 14, 4).fink(Color("#5b8f86"), 1.6)
	pen.pop()


func draw_treasure_art(x: float, y: float, t: float) -> void:
	pen.push().at(x, y)
	pen.begin().ellipse(0, 4, 40, 11).fill(Color(0, 0, 0, 0.22))
	pen.begin().ellipse(0, 0, 38, 12, PI, TAU).line(38, 0).ellipse(0, 0, 38, 6, 0, PI).close().fink(Color("#e8cf95"), 2.4)
	# the open chest, half buried
	pen.begin().move(-18, -2).line(-18, -20).line(18, -20).line(18, -2).close().fink(Color("#8a5a34"), 2.4)
	pen.begin().move(-18, -20).line(-14, -40).quad(0, -46, 14, -40).line(18, -20).close().fink(Color("#6d4426"), 2.4)
	for bx in [-12, 12]:
		pen.begin().rect(bx - 2, -20, 4, 18).fink(Color("#f4c44f"), 1.4)
	# coins heaped in the chest and spilled on the sand, glinting
	for cc in [[-10, -21], [-3, -24], [5, -22], [12, -21], [0, -19], [22, 2], [27, -1], [-24, 3]]:
		pen.begin().ellipse(cc[0], cc[1], 4.2, 2.6).fink(Color("#ffd34d"), 1.3)
	for kk in 3:
		var ph := fposmod(t * 1.3 + kk * 0.37, 1.0)
		var sx: float = [-6, 8, 24][kk]
		var sy: float = [-28, -26, -4][kk]
		var s := sin(ph * PI) * 5
		if s < 0.5:
			continue
		pen.begin().move(sx - s, sy).line(sx + s, sy).move(sx, sy - s).line(sx, sy + s).stroke(1.6, Color.WHITE)
	pen.pop()


# --- quests: a chest of relics on the ground (Godot only) ---

func draw_chest_art(x: float, y: float, t: float) -> void:
	pen.push().at(x, y)
	pen.begin().ellipse(0, 3, 30, 8).fill(Color(0, 0, 0, 0.25))
	# the box and its rounded lid, banded in iron
	pen.begin().move(-20, 0).line(-20, -20).line(20, -20).line(20, 0).close().fink(Color("#8a5a34"), 2.4)
	pen.begin().move(-20, -20).line(-20, -26).quad(0, -40, 20, -26).line(20, -20).close().fink(Color("#6d4426"), 2.4)
	for bx in [-13, 13]:
		pen.begin().move(bx - 2.5, 0).line(bx - 2.5, -20).line(bx - 2.5, -30.5 + absf(bx) * 0.2).line(bx + 2.5, -31 + absf(bx) * 0.2).line(bx + 2.5, -20).line(bx + 2.5, 0).close().fink(Color("#5a5f6b"), 1.4)
	# the gold lock, glinting now and then
	pen.begin().rect(-5, -24, 10, 10).fink(Color("#f4c44f"), 1.8)
	pen.begin().ellipse(0, -27, 3.5, 3.5, PI, TAU).stroke(1.8, Color("#1d1a22"))
	pen.begin().ellipse(0, -20, 1.4, 1.8).fill(Color("#1d1a22"))
	var ph := fposmod(t * 0.7, 1.0)
	if ph < 0.25:
		var s := sin(ph / 0.25 * PI) * 5
		pen.begin().move(5 - s, -24).line(5 + s, -24).move(5, -24 - s).line(5, -24 + s).stroke(1.6, Color.WHITE)
	pen.pop()


# --- lost travelers (web: v78.js drawTravelers, content.js drawCiv) ---

func _folk_of(B: Dictionary) -> Array:
	var key := "%s:%d" % [game.world.seed, B.prov]
	if not _folk.has(key):
		var folk := []
		for i in int(B.n):
			var fr := Mulberry32.from_string(str(game.world.seed) + ":trav:" + str(B.prov) + ":" + str(i))
			var col: String = CIV_TUNIC[int(floor(fr.next() * CIV_TUNIC.size()))]
			var skin: String = CIV_SKIN[int(floor(fr.next() * CIV_SKIN.size()))]
			var hat := "hood" if fr.next() < 0.6 else "straw"
			var sack := fr.next() < 0.6
			folk.append({"col": col, "skin": skin, "hat": hat, "sack": sack, "ph": fr.next() * 6, "x": 0.0, "y": 0.0, "dir": 1, "moving": false})
		_folk[key] = folk
	return _folk[key]


func draw_travelers(B: Dictionary, t: float, walking: bool) -> void:
	var x: float = B.x
	var y: float = B.y
	var dir: int = B.get("dir", 1)
	# a handcart piled with bundles
	pen.push().at(x + 26 * dir, y - 2).grow(dir, 1)
	pen.begin().move(-14, -8).line(34, -8).stroke(5, OL).stroke(2.4, Color("#8a5a34"))
	pen.begin().rect(-14, -20, 24, 12).fill(Color("#a0703f")).ink(2.2)
	for bd in [[-8, -24, 6, "#d9c39a"], [2, -25, 7, "#b5643c"], [-2, -31, 5, "#7a8fb5"]]:
		pen.begin().ellipse(bd[0], bd[1], bd[2], bd[2] * 0.8).fill(Color(bd[3])).ink(1.8)
	pen.begin().arc(-2, -3, 6).fill(Color("#6d4426")).ink(2)
	pen.pop()
	# when resting, a little campfire in their midst
	if not walking:
		var fx := x - 4
		var fy := y + 6
		var fl := 1 + sin(t * 9) * 0.15
		pen.begin().ellipse(fx, fy, 9, 3.5).fink(Color("#6d4426"), 1.6)
		pen.begin().move(fx - 5, fy).quad(fx - 4, fy - 10 * fl, fx, fy - 14 * fl).quad(fx + 4, fy - 10 * fl, fx + 5, fy).close().fink(Color("#ff9a3c"), 1.6)
		pen.begin().move(fx - 2, fy).quad(fx, fy - 8 * fl, fx + 2, fy).close().fill(Color("#ffe27a"))
	var folk := _folk_of(B)
	for i in folk.size():
		var f: Dictionary = folk[i]
		var a := 0.0 if walking else float(i) / folk.size() * PI * 2 + 0.6
		f.x = x - i * 9 * dir if walking else x - 4 + cos(a) * 18
		f.y = y + (i % 2) * 5 if walking else y + 6 + sin(a) * 9
		f.dir = dir if walking else (-1 if cos(a) > 0 else 1)
		f.moving = walking
	var order := folk.duplicate()
	order.sort_custom(func(p, q): return p.y < q.y)
	for f in order:
		_civ(f, t)
	# a small "?" over their heads until you deal with them
	var k := maxf(1.0, 0.62 / _cam_z())
	var q := Vector2(x - 4, y - 40 + sin(t * 3) * 2)
	view.draw_circle(q, 8 * k + 1 * k, OL)
	view.draw_circle(q, 8 * k - 1 * k, Color("#faf1dc"))
	view.draw_string(ThemeDB.fallback_font, q + Vector2(-4 * k, 5 * k), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * k), OL)


func _civ(cv: Dictionary, t: float) -> void:
	var ph: float = t * 9 + cv.ph
	var sw := sin(ph) * 2.2 if cv.moving else 0.0
	var bob := -absf(sin(ph)) * 1.1 if cv.moving else 0.0
	pen.push().at(cv.x, cv.y).grow(cv.dir, 1)
	pen.begin().ellipse(0, 0.6, 4.6, 1.8).fill(Color(OL, 0.22))
	for lg in [[-1.4, sw], [1.4, -sw]]:
		pen.begin().move(lg[0], -4.6 + bob).line(lg[0] + lg[1], 0).stroke(2.8, OL).stroke(1.4, Color("#5b4a3a"))
	pen.begin().ellipse(0, -7.6 + bob, 3.5, 4.2).fill(Color(cv.col)).ink(1.3)
	if cv.sack:
		pen.begin().arc(3.6, -6.4 + bob, 2.2).fill(Color("#c99560")).ink(1.1)
	pen.begin().arc(0, -13.4 + bob, 2.6).fill(Color(cv.skin)).ink(1.2)
	if cv.hat == "straw":
		pen.begin().ellipse(0, -15 + bob, 4.2, 1.3).fill(Color("#e8cf7a")).ink(1)
		pen.begin().ellipse(0, -16 + bob, 2, 1.4, PI, TAU).close().fill(Color("#e8cf7a")).ink(1)
	else:
		pen.begin().arc(0, -13.8 + bob, 2.9, PI * 1.05, PI * 1.95).stroke(2, Color(cv.col))
	pen.pop()
