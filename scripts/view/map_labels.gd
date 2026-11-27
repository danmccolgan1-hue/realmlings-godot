class_name MapLabels
extends RefCounted
## Words and badges on the map: each surveyed province's resources (a plaque under its settlement), province names
## under them, and each nation's name over its land. The minimap's toggles switch them (Settings.view).
## web: game.js drawYieldBadge / drawBadgeBody; v78.js drawProvLabels, realmLabelsOf. Only draws.

const OL := Color("#1d1a22")
const RES := ["gold", "wood", "food"]

var view: Node2D
var game: Game
var _realm := []
var _realm_sig := ""
var _f4z := 0.0


func _init(v: Node2D) -> void:
	view = v


func _cam() -> Camera2D:
	return view.get_viewport().get_camera_2d()


func _z() -> float:
	var c := _cam()
	return c.zoom.x if c else 1.0


func _view_rect(pad: float) -> Rect2:
	var c := _cam()
	if c == null:
		return Rect2(-1e9, -1e9, 2e9, 2e9)
	var half := view.get_viewport_rect().size / c.zoom / 2
	return Rect2(c.get_screen_center_position() - half, half * 2).grow(pad)


func draw(g: Game, now: float) -> void:
	game = g
	if Settings.view.get("res", true):
		var vr := _view_rect(300)
		for p in game.surveyed:
			if not game.explored.has(p) or game.battles.any(func(b): return b.prov == p):
				continue
			var ic: Array = game.G.provs[p].ic
			if not vr.has_point(Vector2(ic[0], ic[1])):
				continue
			_yield_badge(p, now - float(game.surveyed[p]))
	_prov_labels()


## web: game.js drawYieldBadge, drawBadgeBody
func _yield_badge(p: int, age: float) -> void:
	var base: Dictionary = game.yields[p]
	var y := {}
	var b = game.buildings.get(p)
	var mine: bool = b != null and b.owner == Game.LOCAL
	var bonus := {}
	if mine:
		var inc: Dictionary = {"gold": 0, "wood": 0, "food": 0} if game.occ.has(p) else game.province_income(p, b)
		for k in RES:
			y[k] = inc[k]
			bonus[k] = inc[k] > base[k]
		y.deposit = base.get("deposit", false) and not game.extras_in(p).any(func(e): return e.type == "goldmine")
	else:
		for k in RES:
			y[k] = base[k]
		y.deposit = base.get("deposit", false)
	var ks := RES.filter(func(k): return int(y[k]) > 0)
	if ks.is_empty():
		return
	var P: Dictionary = game.G.provs[p]
	var pop := 1.0 if age >= 1.2 else maxf(0.01, 1 - exp(-age * 7) * cos(age * 14))
	var k := maxf(1.0, 0.62 / _z()) * pop
	var w: float = (ks.size() * 44 + 10 + (30 if y.deposit else 0)) * k
	var h := 26 * k
	var cx0: float = P.ic[0]
	var yy: float = P.ic[1] + 118 + (26 * maxf(1.0, 0.62 / _z()) - h) / 2   # (it pops in about its middle)
	var x := cx0 - w / 2
	var a := 1.0 if mine else 0.72
	var box := StyleBoxFlat.new()
	box.bg_color = Color(243 / 255.0, 228 / 255.0, 196 / 255.0, 0.94 * a) if mine else Color(0.86, 0.86, 0.86, 0.94 * a)
	box.set_corner_radius_all(int(h / 2))
	box.set_border_width_all(maxi(1, int(round(2.6 * k))))
	box.border_color = Color(OL, a)
	box.anti_aliasing = true
	view.draw_style_box(box, Rect2(x, yy, w, h))
	var font := ThemeDB.fallback_font
	for i in ks.size():
		var r: String = ks[i]
		var cx := x + (10 + i * 44) * k + 8 * k
		var sp = Art.get_sprite("icons", "common", "res_%s.png" % r)
		if sp:
			var s: float = 0.72 * k / 3.4   # (the icon was drawn at resIcon scale 3.4, centered on 40, 42)
			var tex: Texture2D = sp.tex
			view.draw_texture_rect(tex, Rect2(Vector2(cx, yy + h / 2) - Vector2(40, 42) * s, tex.get_size() * s), false, Color(1, 1, 1, a) if mine else Color(0.75, 0.75, 0.75, a))
		var col := Color("#1f7a2e") if bonus.get(r, false) else OL
		view.draw_string(font, Vector2(cx + 11 * k, yy + h / 2 + 5.5 * k), str(int(y[r])), HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * k), Color(col, a))
	if y.deposit:   # a small pick over a gold nugget marks the hidden deposit
		var dc := Vector2(x + (10 + ks.size() * 44) * k + 9 * k, yy + h / 2)
		view.draw_circle(dc, 10 * k + 1 * k, Color(OL, a))
		view.draw_circle(dc, 10 * k - 1 * k, Color("#fff1c2", a))
		var nug := PackedVector2Array([dc + Vector2(-5, 3) * k, dc + Vector2(-3, -2) * k, dc + Vector2(2, -4) * k, dc + Vector2(5, 1) * k, dc + Vector2(1, 4) * k])
		view.draw_colored_polygon(nug, Color("#f4c44f", a))
		nug.append(nug[0])
		view.draw_polyline(nug, Color(OL, a), 1.4 * k, true)


## Province names under their resources, and each nation's name over its land. web: v78.js drawProvLabels
func _prov_labels() -> void:
	var font := ThemeDB.fallback_font
	var z := _z()
	if Settings.view.get("names", false):
		var k := maxf(1.0, 0.62 / z)
		var vr := _view_rect(300)
		for p in game.explored:
			var P: Dictionary = game.G.provs[p]
			if not vr.has_point(Vector2(P.ic[0], P.ic[1])):
				continue
			var y: float = P.ic[1] + 118 + (30 * k if game.surveyed.has(p) else 0.0)
			if game.setpieces.has(p) and game.sp_known(p):
				y = maxf(y, P.ic[1] + 150 + 30 * k)
			var nm := game.prov_name(p)
			var fs := int(15 * k)
			var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := Vector2(P.ic[0] - w / 2, y + fs)
			view.draw_string_outline(font, at, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(4 * k), Color(OL, 0.9))
			view.draw_string(font, at, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#fff6d6") if game.owned(p) else Color("#f1f3f7"))
	if Settings.view.get("realm", true):
		if _f4z <= 0 and game.capital >= 0:
			_f4z = _near_zoom()
		for L in _realm_labels():
			var px: float = L.fs * z
			var zf := (_f4z * 1.7 - z) / (_f4z * 0.6) if _f4z > 0 else 1.0
			var a := clampf(minf(minf(zf, (px - 10) / 8.0), (220 - px) / 60.0), 0.0, 0.8)
			if a <= 0.02:
				continue
			var fs := int(L.fs)
			var gap: float = L.fs * 0.18
			var total := 0.0
			var ws := []
			for ch in L.name:
				var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				ws.append(cw)
				total += cw
			total += gap * (L.name.length() - 1)
			var x: float = L.x - total / 2
			var light := Color(str(game.player_info(L.o).get("light", "#ffffff")))
			for i in L.name.length():
				var at := Vector2(x, L.y + fs * 0.35)
				view.draw_string_outline(font, at, L.name[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(L.fs * 0.09), Color(OL, 0.75 * a))
				view.draw_string(font, at, L.name[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(light, a))
				x += ws[i] + gap


## The zoom framing your capital and its neighbors, halved (the F4 zoom; nation names show from there outward).
func _near_zoom() -> float:
	var r := Rect2()
	var first := true
	for p in [game.capital] + game.all_nbr[game.capital]:
		for v in game.G.provs[p].pts:
			if first:
				r = Rect2(v[0], v[1], 0, 0)
				first = false
			else:
				r = r.expand(Vector2(v[0], v[1]))
	var vs := view.get_viewport_rect().size
	return minf(vs.x * 0.95 / r.size.x, vs.y * 0.95 / r.size.y) / 2


## A label for your nation and every nation you have met, over the biggest block of their land you know.
## web: v78.js realmLabelsOf
func _realm_labels() -> Array:
	var who := [Game.LOCAL] if not game.spectator else game.seat_ids()   # (0.19.3: an observer sees every nation)
	for o in (game.met if not game.spectator else game.nations):
		if game.nations.has(o) and not game.provs_of(o).is_empty() and not who.has(o):
			who.append(o)
	var sig := ""
	for o in who:
		var ps := []
		for p in game.buildings:
			if game.buildings[p].owner == o and (o == Game.LOCAL or game.explored.has(p)):
				ps.append(p)
		sig += "%d:%s%s|" % [o, ps, game.player_info(o).name]
	if sig == _realm_sig:
		return _realm
	_realm_sig = sig
	_realm = []
	for o in who:
		var mine := {}
		for p in game.buildings:
			if game.buildings[p].owner == o and (o == Game.LOCAL or game.explored.has(p)):
				mine[p] = true
		if mine.is_empty():
			continue
		var seen := {}
		var best := []
		for s0 in mine:
			if seen.has(s0):
				continue
			var comp := []
			var q := [s0]
			seen[s0] = true
			while not q.is_empty():
				var a = q.pop_front()
				comp.append(a)
				for n in game.all_nbr[a]:
					if mine.has(n) and not seen.has(n):
						seen[n] = true
						q.append(n)
			if comp.size() > best.size():
				best = comp
		var x0 := INF
		var x1 := -INF
		var sx := 0.0
		var sy := 0.0
		for p in best:
			var P: Dictionary = game.G.provs[p]
			sx += P.ic[0]
			sy += P.ic[1]
			for v in P.pts:
				x0 = minf(x0, v[0])
				x1 = maxf(x1, v[0])
		var name := str(game.player_info(o).get("name", "My Realm")).to_upper()
		var w := (x1 - x0) * 0.8
		_realm.append({"o": o, "x": sx / best.size(), "y": sy / best.size() - 40, "name": name, "fs": maxf(70, minf(420, w / maxf(4, name.length() * 0.78)))})
	return _realm
