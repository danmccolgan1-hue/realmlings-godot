class_name MapOrders
extends RefCounted
## What your orders look like on the map: the provinces your selected units stand in, a survey tracing its loop with
## stakes, the numbered markers of queued surveys and moves, the rally point of the selected building, the marker
## where you just sent units, the selection box, and the eye over a detected Wayfinder. Draws only.
## web: v78.js drawSelProvs / drawMoveMarks, game.js drawSurvey / drawSurveyQueue / #box, v96.js drawRally,
## v102.js drawScoutMarks

const OL := Color("#1d1a22")
const UKK := 1.5

var v: MapView


func _init(view: MapView) -> void:
	v = view


func _z() -> float:
	var c := v.get_viewport().get_camera_2d()
	return c.zoom.x if c else 1.0


func _font() -> Font:
	return v.font if v.font else ThemeDB.fallback_font


# web: v78.js drawSelProvs: the provinces your selected units stand in glow softly
func draw_sel_provs(g: Game, t: float) -> void:
	var ps := {}
	for u in v.selection:
		if u.owner == Game.LOCAL and g.explored.has(u.prov):
			ps[u.prov] = true
	if ps.is_empty():
		return
	var a := 0.5 + sin(t * 2.4) * 0.12
	var z := _z()
	for p in ps:
		var pts := PackedVector2Array()
		for q in g.G.provs[p].inner:
			pts.append(Vector2(q[0], q[1]))
		if pts.size() < 3:
			continue
		Pen.fill_poly(v, pts, Color("#fff6c8", 0.09))
		pts.append(pts[0])
		Pen.stroke_line(v, pts, Color("#ffe27a", a * 0.5), maxf(16, 10 / z))
		Pen.stroke_line(v, pts, Color("#fff1b0", a), maxf(4, 2.4 / z))


# web: game.js drawSurvey: the surveyed stretch of the loop traced behind the Wayfinder, stakes at its corners
func draw_survey(g: Game, site: Dictionary, t: float) -> void:
	if not site.has("loop"):
		return
	var f := minf(1.0, (t - site.t0) / site.dur)
	var done: float = Game.route_at(site, f)[2] - site.lead
	var z := _z()
	if done > 0:
		var pts := PackedVector2Array([Vector2(site.loop[0][0], site.loop[0][1])])
		var left := done
		for i in site.seg.size():
			if left <= 0:
				break
			var a: Array = site.loop[i]
			var b: Array = site.loop[i + 1]
			var k := minf(1.0, left / site.seg[i])
			pts.append(Vector2(a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k))
			left -= site.seg[i]
		Pen.stroke_line(v, pts, OL, maxf(7, 4 / z))
		Pen.stroke_line(v, pts, Color("#8fe3ff"), maxf(4, 2.4 / z))
		v._dashes(pts, 2.0, Color.WHITE, 2.0, 10.0, 0.0)
	var acc := 0.0
	for i in site.loop.size() - 1:
		if acc > done:
			break
		var x: float = site.loop[i][0]
		var y: float = site.loop[i][1]
		v.draw_line(Vector2(x, y), Vector2(x, y - 18), OL, 4.5, true)
		v.draw_line(Vector2(x, y), Vector2(x, y - 18), Color("#c99560"), 2.0, true)
		var fl := PackedVector2Array([Vector2(x, y - 18), Vector2(x + 11, y - 14), Vector2(x, y - 10)])
		v.draw_colored_polygon(fl, Color("#ff7a59"))
		fl.append(fl[0])
		v.draw_polyline(fl, OL, 1.6, true)
		acc += site.seg[i]


# web: game.js drawSurveyQueue: each queued order gets a numbered marker (survey flags; white chevrons for moves)
func draw_survey_queue(g: Game, t: float) -> void:
	var k := maxf(1.0, 0.62 / _z())
	for u in g.units:
		if u.owner != Game.LOCAL:
			continue
		var list: Array = ([u.pendingSurvey] if u.pendingSurvey >= 0 else []) + u.surveyQueue
		for i in list.size():
			var e = list[i]
			var p: int = e if e is int else int(e.move)
			if p < 0 or p >= g.G.provs.size():
				continue
			var o := float(u.id % 5 - 2) * 9
			var x: float = g.G.provs[p].ic[0] + o
			var y: float = g.G.provs[p].ic[1] + 40 + o * 0.5
			var bob := sin(t * 3 + i) * 2
			if not (e is int):
				v._ellipse(Vector2(x, y), 13 * k, 5.5 * k, OL, 3 * k)
				v._ellipse(Vector2(x, y), 13 * k, 5.5 * k, Color.WHITE, 1.6 * k)
				var ch := PackedVector2Array([Vector2(x - 6 * k, y - 22 * k + bob), Vector2(x, y - 12 * k + bob), Vector2(x + 6 * k, y - 22 * k + bob)])
				v.draw_polyline(ch, OL, 6 * k, true)
				v.draw_polyline(ch, Color.WHITE, 3 * k, true)
				_num(Vector2(x + 15 * k, y - 22 * k), k, i + 1)
				continue
			v.draw_line(Vector2(x, y), Vector2(x, y - 30 * k), OL, 6 * k, true)
			v.draw_line(Vector2(x, y), Vector2(x, y - 30 * k), Color("#c99560"), 3 * k, true)
			var fl := PackedVector2Array([Vector2(x, y - 30 * k + bob), Vector2(x + 22 * k, y - 24 * k + bob), Vector2(x, y - 16 * k + bob)])
			v.draw_colored_polygon(fl, Color("#ff7a59"))
			fl.append(fl[0])
			v.draw_polyline(fl, OL, 2.2 * k, true)
			_num(Vector2(x - 12 * k, y - 34 * k), k, i + 1)


func _num(c: Vector2, k: float, n: int) -> void:
	v.draw_circle(c, 9 * k, Color.WHITE)
	v.draw_arc(c, 9 * k, 0, TAU, 20, OL, 2.2 * k, true)
	var fs := int(12 * k)
	var s := str(n)
	var w := _font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	v.draw_string(_font(), c + Vector2(-w / 2, fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, OL)


# web: v96.js drawRally: the selected training building's rally point, a dashed line to it and a flag
func draw_rally(g: Game, key: String, t: float) -> void:
	var rp = g.rally.get(key)
	if rp == null:
		return
	var sp := g.src_spot(key)
	var K := UKK * 1.3
	v._dashes(PackedVector2Array([Vector2(sp.x, sp.y), Vector2(rp.x, rp.y)]), 3.0, Color(1, 1, 1, 0.7), 10.0, 10.0, 0.0)
	v._filled_ellipse(Vector2(rp.x, rp.y), 12 * K, 5 * K, Color(0, 0, 0, 0.25))
	v._army_flag({"owner": Game.LOCAL}, rp.x, rp.y, rp.y - 26 * K, t, K)


# web: v78.js drawMoveMarks: one quick swell, then a fade to nothing at 1 s
func draw_move_marks() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var keep := []
	for m in v.marks:
		var a: float = now - m.t0
		if a >= 1.0:
			continue
		keep.append(m)
		var sw := 0.6 + (a / 0.18) * 0.6 if a < 0.18 else (1.2 - ((a - 0.18) / 0.12) * 0.2 if a < 0.3 else 1.0)
		var alpha := 1.0 if a < 0.3 else 1.0 - (a - 0.3) / 0.7
		var r := 16 * UKK * sw
		var c := Vector2(m.x, m.y)
		var sq := Vector2(1, 0.62)
		if a < 0.45:
			v._ellipse(c, r * (1 + a * 2.2), r * (1 + a * 2.2) * 0.62, Color(1, 0.84, 0.35, 0.8 * (1 - a / 0.45) * alpha), 3.0)
		for st in [[10 * sqrt(UKK), OL], [6 * sqrt(UKK), Color("#ffc93c")], [2 * sqrt(UKK), Color("#fff3b8")]]:
			var col: Color = st[1]
			col.a *= maxf(0, alpha)
			v.draw_line(c + Vector2(-r, -r) * sq, c + Vector2(r, r) * sq, col, st[0], true)
			v.draw_line(c + Vector2(r, -r) * sq, c + Vector2(-r, r) * sq, col, st[0], true)
	v.marks = keep


# the selection box while you drag (web: #box)
func draw_box() -> void:
	if v.box.size == Vector2.ZERO:
		return
	var z := _z()
	v.draw_rect(v.box, Color(1, 0.95, 0.7, 0.12))
	v.draw_rect(v.box, Color("#ffe27a"), false, 2.0 / z)


# web: v102.js drawScoutMarks: an eye over a Wayfinder the enemy has detected
func draw_scout_marks(g: Game, t: float) -> void:
	for u in g.units:
		if u.kind != g.WAYFINDER or not u.get("detected", false):
			continue
		if u.owner != Game.LOCAL and not g.visible.has(u.prov):
			continue
		var x: float = u.x
		var y: float = u.y - 58 * UKK
		var K := UKK
		var eye := PackedVector2Array()
		for i in 25:
			var s := float(i) / 24.0
			var px := -13 * K + 26 * K * s
			eye.append(Vector2(x + px, y - 11 * K * 2 * s * (1 - s)))
		for i in range(23, 0, -1):
			var s := float(i) / 24.0
			var px := -13 * K + 26 * K * s
			eye.append(Vector2(x + px, y + 11 * K * 2 * s * (1 - s)))
		v.draw_colored_polygon(eye, Color.WHITE)
		eye.append(eye[0])
		v.draw_polyline(eye, OL, 3 * K, true)
		v.draw_circle(Vector2(x, y), 4.5 * K, Color("#e0403a"))
		v.draw_arc(Vector2(x, y), 4.5 * K, 0, TAU, 16, OL, 1.6 * K, true)
