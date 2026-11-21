class_name MapEffects
extends RefCounted
## Battle and spell effects on the map. Draws only.
## - Battles: the melee in the middle of the province, each side's soldiers swinging at the other with slash arcs,
##   dust, crossed swords over it, and the strength bar under it; the blows (−n) and falling soldiers; arrows from
##   forts with Arrowslits. web: game.js drawBattle / drawBattleBar / drawBattleFx, govtech.js drawArrows
## - Magic: forest paths and tunnels, the stasis trap, the casting circle under a casting Mage (with its progress),
##   Shockwave and Earthquake casting rings, the moment they strike, stasis bubbles and Mending's pluses.
##   web: magic.js drawMagic, gpc.js drawQuakes / drawSpellFx / dustPuff

const OL := Color("#1d1a22")
const UKK := 1.5
const UK := 1.0
const SCHOOL_COL := {"life": Color("#3fa34d"), "death": Color("#6b3fa0"), "arcane": Color("#3a6fd8"), "pyro": Color("#e8552a"), "elemental": Color("#2a9fd6")}

var v: MapView


func _init(view: MapView) -> void:
	v = view


func _z() -> float:
	var c := v.get_viewport().get_camera_2d()
	return c.zoom.x if c else 1.0


func _font() -> Font:
	return v.font if v.font else ThemeDB.fallback_font


func _school_col(g: Game, o: int) -> Color:
	var sc = g.current_school() if o == Game.ME else (g.nations[o].get("school") if g.nations.has(o) else null)
	if sc == null:
		sc = "arcane"
	var S: Dictionary = GameData.c("SCHOOLS")
	return Color(S[sc].color) if S.has(sc) else SCHOOL_COL.get(sc, Color("#3a6fd8"))


func _oval(c: Vector2, rx: float, ry: float, col: Color, w: float, a0 := 0.0, a1 := TAU, n := 40) -> void:
	var pts := PackedVector2Array()
	for k in n + 1:
		var a := a0 + (a1 - a0) * k / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	v.draw_polyline(pts, col, w, true)


func _disc(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 32:
		var a := TAU * k / 32
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	v.draw_colored_polygon(pts, col)


# a soft radial glow: rings of falling alpha (stands in for the canvas's radial gradients)
func _glow(c: Vector2, r: float, ry_k: float, cols: Array, alpha: float) -> void:
	var n := 10
	for i in n:
		var f := 1.0 - float(i) / n
		var col: Color = cols[0].lerp(cols[1], 1 - f) if cols.size() == 2 else cols[0]
		col.a *= alpha * (1.0 / n) * 2.2
		_disc(c, r * f, r * f * ry_k, col)


# --- under the units ------------------------------------------------------------------------------------------

func draw_under(g: Game, t: float) -> void:
	var V: Array = g.world.vertices
	# forest paths and tunnels (web: magic.js drawMagic)
	for i in g.paths:
		var e: Dictionary = g.world.edges[int(i)]
		if not g.explored.has(e.a) and not g.explored.has(e.b):
			continue
		var a := Vector2(V[e.v[0]][0], V[e.v[0]][1])
		var b := Vector2(V[e.v[1]][0], V[e.v[1]][1])
		var m := (a + b) / 2
		var ang := (b - a).angle()
		v.draw_set_transform(m, ang, Vector2.ONE)
		if g.paths[i] == "forest":
			_disc(Vector2.ZERO, 30, 24, Color("#9bd95f"))
			_oval(Vector2.ZERO, 30, 24, Color(OL, 0.35), 2.5)
			v.draw_rect(Rect2(-9, -26, 18, 52), Color("#c9a46b"))
			for s in [-1, 1]:
				v.draw_circle(Vector2(s * 22, -14), 4, Color("#5fae4a"))
				v.draw_circle(Vector2(s * 24, 12), 3, Color("#5fae4a"))
		else:
			for s in [-1, 1]:
				var arch := PackedVector2Array()
				var inner := PackedVector2Array()
				for k in 11:
					var f := float(k) / 10
					arch.append(Vector2(-14 + 28 * f, -4 - 16 * 4 * f * (1 - f) * 0.75))
					inner.append(Vector2(-8 + 16 * f, -2 - 10 * 4 * f * (1 - f) * 0.75))
				var outer := PackedVector2Array([Vector2(-14, 6)]) + arch + PackedVector2Array([Vector2(14, 6)])
				var hole := PackedVector2Array([Vector2(-8, 6)]) + inner + PackedVector2Array([Vector2(8, 6)])
				var xf := Transform2D(PI if s < 0 else 0.0, Vector2(0, s * 14))
				v.draw_colored_polygon(xf * outer, Color("#8a8f9b"))
				var ol := xf * outer
				ol.append(ol[0])
				v.draw_polyline(ol, OL, 2.6, true)
				v.draw_colored_polygon(xf * hole, OL)
			v.draw_rect(Rect2(-6, -10, 12, 20), Color(0.63, 0.43, 0.86, 0.35))
		v.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# the stasis trap (web: S.trap)
	if g.trap != null and g.visible.has(g.trap.prov):
		var c: Array = g.G.provs[g.trap.prov].ic
		var at := Vector2(c[0] + 60, c[1] + 120)
		v._dashes(_oval_pts(at, 26, 13, t * 0.5), 4.0, Color(0.31, 0.67, 1, 0.8), 8.0, 6.0, 0.0)
		for k in 6:
			var q := k * PI / 3 + t * 0.5
			v.draw_circle(at + Vector2(cos(q) * 26, sin(q) * 13), 3.5, Color("#bfe3ff"))
	for u in g.units:
		if u.get("cast") != null and (u.owner == Game.ME or g.visible.has(u.prov)):
			_cast_circle(g, u, t)
		if u.get("quake") and (u.owner == Game.ME or g.visible.has(u.prov)):
			_quake_ring(g, u, t)


func _oval_pts(c: Vector2, rx: float, ry: float, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 41:
		var a := TAU * k / 40 + rot
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


# web: magic.js drawMagic (GC08): a bright casting circle on the ground, two rings of runes turning opposite ways,
# motes rising, and the cast's progress over the caster
func _cast_circle(g: Game, u: Dictionary, t: float) -> void:
	var K := UKK
	var long: bool = not is_finite(u.cast.dur) or u.cast.dur >= 30
	var col := _school_col(g, u.owner)
	var r := (40.0 if u.kind == "army" else 26.0) * K * (1.25 if long else 1.0)
	var pulse := 1 + sin(t * 3) * 0.05
	var c := Vector2(u.x, u.y + 2)
	var sy := 0.42
	_glow(c, r * 1.25, sy, [col, Color(1, 1, 1, 0)], 0.42 + sin(t * 4) * 0.08)
	_oval(c, r * pulse, r * pulse * sy, OL, 9)
	_oval(c, r * pulse, r * pulse * sy, col, 5)
	_oval(c, r * pulse, r * pulse * sy, Color(1, 1, 1, 0.8), 1.6)
	var ring := PackedVector2Array()
	for k in 49:
		var a := TAU * k / 48 + t * 1.2
		ring.append(c + Vector2(cos(a) * r * 0.72, sin(a) * r * 0.72 * sy))
	v._dashes(ring, 3.0, col, 10.0, 7.0, 0.0)
	for k in 6:
		var q := k * PI / 3 + t * 1.2
		var p := c + Vector2(cos(q) * r * 0.86, sin(q) * r * 0.86 * sy)
		v.draw_line(p + Vector2(-4, -2), p + Vector2(4, 2), Color.WHITE, 2.4, true)
		v.draw_line(p + Vector2(4, -2), p + Vector2(-4, 2), Color.WHITE, 2.4, true)
		v.draw_line(p + Vector2(0, -2.5), p + Vector2(0, 2.5), Color.WHITE, 2.4, true)
	var tri := PackedVector2Array()
	for k in 4:
		var q := k * TAU / 3 - t * 0.8
		tri.append(c + Vector2(cos(q) * r * 0.72, sin(q) * r * 0.72 * sy))
	v.draw_polyline(tri, Color(col, 0.8), 2.0, true)
	for k in 6:   # motes rising from the circle
		var f := fposmod(t * 0.6 + k / 6.0, 1.0)
		var q := k * 1.7 + t * 0.4
		v.draw_circle(Vector2(u.x + cos(q) * r * 0.8, u.y + sin(q) * r * 0.32 - f * 46 * K), 2.6 * K, Color(col, 0.85 * (1 - f)))
	if is_finite(u.cast.dur):
		var f := minf(1.0, (g.t - u.cast.t0) / u.cast.dur)
		_progress_dot(Vector2(u.x, u.y - (90.0 if u.kind == "army" else 66.0) * K), f, col)


func _progress_dot(at: Vector2, f: float, col: Color) -> void:
	var K := UKK
	v.draw_circle(at, 10 * K, Color(0.98, 0.945, 0.86, 0.95))
	v.draw_arc(at, 10 * K, -PI / 2, -PI / 2 + f * TAU, 24, col, 4.5 * K, true)
	v.draw_arc(at, 10 * K, 0, TAU, 24, OL, 1.8, true)


# web: gpc.js drawQuakes: a dashed ring that shakes while a Shockwave or Earthquake is cast; Shockwave ripples outward
func _quake_ring(g: Game, u: Dictionary, t: float) -> void:
	var K := UKK
	var T: float = u.quake.get("T", 30.0)
	var col := Color("#8a6a3a") if u.quake.kind == "quake" else Color("#6f8fc9")
	var r := (40.0 if u.kind == "army" else 26.0) * K
	var f := minf(1.0, (g.t - u.quake.t0) / T)
	var shake := sin(t * 40) * 1.5
	var c := Vector2(u.x + shake, u.y)
	var pts := _oval_pts(c, r, r * 0.45)
	v._dashes(pts, 6.0, OL, 6.0, 6.0, 0.0)
	v._dashes(pts, 4.0, col, 6.0, 6.0, 0.0)
	if u.quake.kind == "shock":
		for k in 2:
			var w := fposmod(t * 0.8 + k * 0.5, 1.0)
			_oval(c, r * (1 + w * 1.6), r * (1 + w * 1.6) * 0.45, Color(col, 1 - w), 3.0)
	if u.quake.kind == "quake" and sin(t * 1.7 + u.id) > 0.92:
		_dust(Vector2(u.x + sin(t * 13) * 30 * K, u.y + 6 * K), 14 * K, 0.5)
	_progress_dot(Vector2(u.x, u.y - (80.0 if u.kind == "army" else 60.0) * K), f, col)


# web: gpc.js dustPuff
func _dust(at: Vector2, r: float, a: float) -> void:
	for k in 4:
		_disc(at + Vector2((k - 1.5) * r * 0.7, -(k % 2) * r * 0.4), r * (0.7 + (k % 3) * 0.2), r * 0.5, Color(Color("#c8b28a") if k % 2 else Color("#b39a70"), a))


# --- battles -----------------------------------------------------------------------------------------------------

# web: game.js battleFigures: up to 6 soldiers standing for a side, shared out by kind
static func battle_figures(armies: Array) -> Array:
	var kinds := {}
	var total := 0
	for a in armies:
		for k in a.troops:
			kinds[k] = kinds.get(k, 0) + a.troops[k]
			total += a.troops[k]
	var shown := mini(6, total)
	var ks := kinds.keys()
	ks.sort_custom(func(x, y): return kinds[x] > kinds[y])
	var out := []
	for k in ks:
		var n := maxi(1, roundi(float(shown) * kinds[k] / maxf(1, total)))
		for i in n:
			if out.size() < shown:
				out.append(k)
	return out


func _sides(g: Game, b: Dictionary) -> Dictionary:
	var sides := {}
	for a in g.units:
		if a.kind == "army" and is_same(a.get("battle"), b) and not a.get("retreating", false):
			if not sides.has(a.owner):
				sides[a.owner] = []
			sides[a.owner].append(a)
	return sides


# web: game.js drawBattle: the melee
func draw_battle(g: Game, b: Dictionary, t: float) -> void:
	var bc := g.battle_center(b.prov)
	var cx: float = bc[0]
	var cy: float = bc[1]
	var sides := _sides(g, b)
	var order: Array = (b.get("order") if b.get("order") != null else sides.keys()).filter(func(o): return sides.has(o))
	for k in 5:   # dust in the middle of the melee
		var f := fposmod(t * 0.7 + k / 5.0, 1.0)
		v.draw_circle(Vector2(cx + sin(k * 2.3 + t) * 22, cy - 4 - f * 18), 8 + f * 12, Color("#e9dcc0", 0.35 * (1 - f)))
	var all := []
	for i in order.size():
		var o: int = order[i]
		var dir := -1 if i == 0 else 1
		var figs := battle_figures(sides[o])
		for j in figs.size():
			var row := j % 3
			var col := j / 3
			var bx := cx + dir * (30 + col * 24 + (8 if row == 1 else 0)) * sqrt(UKK)
			var by := cy - 14 + row * 15 * sqrt(UKK)
			var ph := j * 1.37 + o * 2.1
			var swing := pow(maxf(0, sin(t * 3.2 + ph)), 6)
			var hit_age: float = g.t - b.get("hits", {}).get(o, -9.0)
			var shake := sin(hit_age * 80) * 2.5 if hit_age < 0.25 else 0.0
			all.append({"k": figs[j], "o": o, "dir": dir, "x": bx - dir * swing * 20 + shake, "y": by, "swing": swing})
	all.sort_custom(func(p, q): return p.y < q.y)
	for f in all:
		_disc(Vector2(f.x, f.y + 2), 12, 4.5, Color(Color(str(g.player_info(f.o).color)), 0.28))
		var sp = Art.get_sprite("units", "realm", Art.unit_file(f.k, "d6" if f.dir < 0 else "d2"))
		if sp == null:
			sp = Art.get_sprite("units", "realm", Art.unit_file(Art.design_art(g, f.k), "d6" if f.dir < 0 else "d2"))
		if sp == null and str(f.k).begins_with("m-"):
			sp = Art.get_sprite("units", "common", Art.unit_file("monster-" + str(f.k).substr(2), "d6" if f.dir < 0 else "d2"))
		if sp:
			Art.draw(v, sp, Vector2(f.x, f.y), 0.8 if v._is_cav(f.k) else 1.0)
		if f.swing > 0.55:   # a slash arc in front of the attacker
			var s := Vector2(f.x - f.dir * 14, f.y - 16)
			var a0 := -1.2 if f.dir < 0 else PI + 1.2
			var a1 := 1.2 if f.dir < 0 else PI - 1.2
			v.draw_arc(s, 11, a0, a1, 12, Color(1, 1, 1, (f.swing - 0.55) * 2), 3.2, true)
	# crossed swords over the melee
	var at := Vector2(cx, cy - 70 + sin(t * 3) * 3)
	for s2 in [-1, 1]:
		var xf := Transform2D(s2 * 0.75, at)
		var blade := xf * PackedVector2Array([Vector2(-2.5, -16), Vector2(2.5, -16), Vector2(2.5, 10), Vector2(-2.5, 10)])
		v.draw_colored_polygon(blade, Color("#eef2f7"))
		blade.append(blade[0])
		v.draw_polyline(blade, OL, 2.2, true)
		var guard := xf * PackedVector2Array([Vector2(-7, 6), Vector2(7, 6), Vector2(7, 10), Vector2(-7, 10)])
		v.draw_colored_polygon(guard, Color("#f4c44f"))
		guard.append(guard[0])
		v.draw_polyline(guard, OL, 2.2, true)


# web: game.js drawBattleBar: each side's strength, its soldiers' count and the terrain's effect
func draw_battle_bar(g: Game, b: Dictionary) -> void:
	var sides := _sides(g, b)
	var order: Array = (b.get("order") if b.get("order") != null else []).filter(func(o): return sides.has(o))
	if order.size() < 2:
		return
	var P: Dictionary = g.G.provs[b.prov]
	var max_y := -INF
	for q in P.inner:
		max_y = maxf(max_y, q[1])
	var k := maxf(1.0, 0.62 / _z())
	var w := 230 * k
	var h := 20 * k
	var x: float = P.ic[0] - w / 2
	var y := maxf(g.battle_center(b.prov)[1] + 34, max_y - 40 - h)
	var sA := g.raw_strength(sides[order[0]])
	var sB := g.raw_strength(sides[order[1]])
	var f := sA / maxf(1, sA + sB)
	b["shownF"] = f if b.get("shownF") == null else b.shownF + (f - b.shownF) * 0.15
	var sf: float = b.shownF
	var outer := StyleBoxFlat.new()
	outer.bg_color = Color(0.95, 0.89, 0.77, 0.96)
	outer.set_corner_radius_all(int((h + 6 * k) / 2))
	outer.set_border_width_all(int(2.6 * k))
	outer.border_color = OL
	v.draw_style_box(outer, Rect2(x - 3 * k, y - 3 * k, w + 6 * k, h + 6 * k))
	var r := StyleBoxFlat.new()
	r.bg_color = Color(str(g.player_info(order[1]).color))
	r.set_corner_radius_all(int(h / 2))
	v.draw_style_box(r, Rect2(x, y, w, h))
	var l := StyleBoxFlat.new()
	l.bg_color = Color(str(g.player_info(order[0]).color))
	l.set_corner_radius_all(int(h / 2))
	if sf > 0.02:
		v.draw_style_box(l, Rect2(x, y, maxf(h, w * sf), h))
	v.draw_rect(Rect2(x + h / 2, y, w - h, h * 0.35), Color(1, 1, 1, 0.3))
	v.draw_line(Vector2(x + w * sf, y - 4 * k), Vector2(x + w * sf, y + h + 4 * k), Color.WHITE, 3 * k)
	var nA := 0
	var nB := 0
	for a in sides[order[0]]:
		nA += g.troop_count(a)
	for a in sides[order[1]]:
		nB += g.troop_count(a)
	var fs := int(14 * k)
	var fnt := _font()
	_outlined("⚔ %d" % nA, Vector2(x + 8 * k, y + h / 2 + fs * 0.36), fs, Color.WHITE, OL)
	var tb := "%d ⚔" % nB
	_outlined(tb, Vector2(x + w - 8 * k - fnt.get_string_size(tb, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, y + h / 2 + fs * 0.36), fs, Color.WHITE, OL)
	var note: String = g.TERRAIN_MOD.get(g.world.provinces[b.prov].terrain, "")
	var fs2 := int(11 * k)
	_outlined(note, Vector2(P.ic[0] - fnt.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x / 2, y + h + 13 * k + fs2 * 0.36), fs2, OL, Color.WHITE)


func _outlined(s: String, at: Vector2, fs: int, col: Color, ol: Color) -> void:
	v.draw_string_outline(_font(), at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(fs * 0.25)), ol)
	v.draw_string(_font(), at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# --- over everything ----------------------------------------------------------------------------------------------

func draw_over(g: Game, t: float) -> void:
	for b in g.battles:
		if g.visible.has(b.prov):
			draw_battle_bar(g, b)
	_battle_fx(g, t)
	_spell_fx(g, t)
	_arrows(g, t)
	for u in g.units:
		if not g.visible.has(u.prov) and u.owner != Game.ME:
			continue
		if u.get("stasisUntil", 0.0) > g.t:   # held by a stasis trap
			_disc(Vector2(u.x, u.y - 14), 30, 26, Color(0.56, 0.82, 1, 0.35))
			_oval(Vector2(u.x, u.y - 14), 30, 26, Color("#4fa6e8"), 2.0)
		if u.get("heal") != null or (u.has("healFx") and g.t - u.healFx < 1.5):   # Mending's green pluses
			for k in 4:
				var f := fposmod(t * 0.8 + k / 4.0, 1.0)
				v.draw_string(_font(), Vector2(u.x - 14 + k * 9, u.y - 20 - f * 24), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.43, 0.86, 0.47, 1 - f))


# web: game.js drawBattleFx: −n over a side as blows land; a soldier topples over and fades, with a puff and stars
func _battle_fx(g: Game, t: float) -> void:
	for f in g.fx:
		if f.kind == "arrow" or not g.visible.has(f.prov):
			continue
		var dt: float = g.t - f.t0
		if dt < 0 or dt >= 1.4:
			continue
		var b = null
		for x in g.battles:
			if x.prov == f.prov:
				b = x
		var bc := g.battle_center(f.prov)
		var c := Vector2(bc[0], bc[1] - 34)
		var order: Array = b.order if b != null and b.get("order") != null else [Game.ME]
		var dir := -1 if order.find(f.owner) == 0 else 1
		if f.kind == "num":
			var a := maxf(0, 1 - dt / 1.2)
			var s := "−%d" % f.n
			var fs := 18
			var w := _font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_outlined(s, Vector2(c.x + dir * 50 - w / 2, c.y - 10 - dt * 36 + fs * 0.36), fs, Color(1, 0.7, 0.7, a), Color(OL, a))
		else:
			var x: float = c.x + dir * (36 + f.r * 30)
			var y: float = c.y + 22 + f.r * 26
			var a := maxf(0, 1 - dt / 1.4)
			var sp = Art.get_sprite("units", "realm", Art.unit_file(str(f.unit), "d6" if dir < 0 else "d2"))
			if sp == null:
				sp = Art.get_sprite("units", "realm", Art.unit_file(Art.design_art(g, str(f.unit)), "d6" if dir < 0 else "d2"))
			if sp:
				var rot := -dir * minf(1.4, dt * 4)
				var tex: Texture2D = sp.tex
				var s: float = (0.8 if v._is_cav(str(f.unit)) else 1.0) / sp.scale
				v.draw_set_transform(Vector2(x, y), rot, Vector2(s, s))
				v.draw_texture(tex, -Vector2(sp.ax, sp.ay), Color(1, 1, 1, a))
				v.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			v.draw_circle(Vector2(x, y - 4), 4 + dt * 9, Color(0.93, 0.94, 0.96, a * 0.45))
			for i in 3:
				var q := t * 6 + i * 2.1
				v.draw_circle(Vector2(x + cos(q) * 10, y - 26 + sin(q) * 3), 2, Color(1, 0.95, 0.65, a))


# web: govtech.js drawArrows: arrows arc from the fort's top to the invaders
func _arrows(g: Game, _t: float) -> void:
	for f in g.fx:
		if f.kind != "arrow" or not g.visible.has(f.prov):
			continue
		var k: float = (g.t - f.t0) / 0.45
		if k < 0 or k > 1:
			continue
		var p := Vector2(f.x0 + (f.x1 - f.x0) * k, f.y0 + (f.y1 - f.y0) * k - sin(k * PI) * 40)
		var k2 := maxf(0, k - 0.06)
		var p2 := Vector2(f.x0 + (f.x1 - f.x0) * k2, f.y0 + (f.y1 - f.y0) * k2 - sin(k2 * PI) * 40)
		v.draw_line(p2, p, OL, 4.0, true)
		v.draw_line(p2, p, Color("#e8d6a8"), 2.0, true)


# web: gpc.js drawSpellFx: rings of force roll to the wall, which cracks with a flash (Shockwave); cracks race out
# from the middle of the province, dust rises, the ground heaves (Earthquake)
func _spell_fx(g: Game, _t: float) -> void:
	for F in g.spell_fx:
		var T: float = Game.SPELL_FX_TIME.get(F.kind, 2.0)
		var e: float = g.t - F.t0
		if e < 0 or e >= T:
			continue
		if not (g.visible.has(F.prov) or (F.get("to") != null and g.visible.has(int(F.to)))):
			continue
		if F.kind == "shock" and F.get("at") != null:
			var x0: float = F.from[0]
			var y0: float = F.from[1]
			var x1: float = F.at[0]
			var y1: float = F.at[1]
			var k := e / T
			for i in 4:
				var kk := k * 1.6 - i * 0.18
				if kk < 0 or kk > 1:
					continue
				var c := Vector2(x0 + (x1 - x0) * kk, y0 + 30 + (y1 - y0 - 30) * kk)
				var rr := 55 + kk * 80
				_oval(c, rr, rr * 0.45, Color(OL, (1 - kk) * 0.9), 11)
				_oval(c, rr, rr * 0.45, Color(0.62, 0.77, 1, (1 - kk) * 0.9), 6)
			if k > 0.55:
				var f := (k - 0.55) / 0.45
				var R := 60 + f * 170
				_glow(Vector2(x1, y1 - 16), R, 1.0, [Color.WHITE, Color(0.44, 0.56, 0.79, 0)], 1 - f)
				for i in 6:
					var a: float = F.seed + i * 1.05
					v.draw_polyline(PackedVector2Array([Vector2(x1, y1 - 10), Vector2(x1 + cos(a) * 60 * (0.5 + f), y1 - 10 + sin(a) * 34 * (0.5 + f)),
						Vector2(x1 + cos(a + 0.3) * 110 * (0.5 + f), y1 - 10 + sin(a + 0.3) * 60 * (0.5 + f))]), Color(OL, 1 - f), 5.0, true)
		elif F.kind == "quake":
			var P: Dictionary = g.G.provs[F.prov]
			var cx: float = P.ic[0]
			var cy: float = P.ic[1]
			var k := e / T
			var grow := minf(1.0, e / 0.8)
			var fade := 1 - (k - 0.6) / 0.4 if k > 0.6 else 1.0
			var jig := sin(e * 60) * 4 * (1 - k)
			for i in 7:
				var a: float = F.seed + i * 0.9
				var x := cx + jig
				var y := cy
				var L := (110 + (i % 3) * 50) * grow
				var pts := PackedVector2Array([Vector2(x, y)])
				for s in 6:
					a += sin(F.seed * 3 + i * 7 + s * 5) * 0.5
					x += cos(a) * L / 6
					y += sin(a) * L / 6 * 0.55
					pts.append(Vector2(x, y))
				v.draw_polyline(pts, Color(OL, fade), 9.0, true)
				v.draw_polyline(pts, Color(Color("#5a3a1e"), fade), 4.0, true)
			for i in 10:
				var a: float = F.seed + i * 0.63
				var d := (40 + (i % 4) * 30) * grow
				_dust(Vector2(cx + jig + cos(a) * d * 1.4, cy + sin(a) * d * 0.6 - k * 30), 16 + (i % 3) * 6, 0.75 * fade)
