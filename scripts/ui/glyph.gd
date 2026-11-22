class_name Glyph
extends Control
## Small icons drawn in code, so they look the same on every PC whatever fonts it has (the web game draws these as
## inline SVGs: v96.js FORT_SVG / PROV_SVG, v98.js MANA_STAR_SVG, the payday ring, the map buttons).
## kind: fort, prov, mana, ring, play, pause, full, plus, minus, home, gear, close, check, cross, war, tri_r, tri_d,
## tree_gov, tree_mil, tree_mag. `value` fills the ring (0..1) and the tree circles.

const INK := Color("#1d1a22")
const SUN := Color("#ffc93c")
const MANA_BLUE := Color("#3f7fe0")
const TREE_COL := {"tree_gov": Color("#3f72d9"), "tree_mil": Color("#c7362b"), "tree_mag": Color("#7d4fc9")}

var kind := ""
var value := 0.0
var color := INK
var active := false   # (tree circles: researching something)


static func make(k: String, px := 22.0, col := INK) -> Glyph:
	var g := Glyph.new()
	g.kind = k
	g.color = col
	g.custom_minimum_size = Vector2(px, px)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func set_value(v: float) -> void:
	if not is_equal_approx(v, value):
		value = v
		queue_redraw()


func _pts(list: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in list:
		out.append(Vector2(p[0], p[1]))
	return out


func _shape(list: Array, fill: Color, w := 1.7) -> void:
	var pts := _pts(list)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, INK, w, true)


func _draw() -> void:
	# drawn on a 24 × 24 grid, scaled to fit and centered in whatever room the icon has
	var fit := minf(size.x, size.y) / 24.0
	draw_set_transform((size - Vector2(24, 24) * fit) / 2, 0.0, Vector2(fit, fit))
	var s := 1.0
	var c := Vector2(12, 12)
	match kind:
		"fort":   # web: v96.js FORT_SVG
			_shape([[3, 21], [3, 9], [6, 9], [6, 11], [9, 11], [9, 6], [15, 6], [15, 11], [18, 11], [18, 9], [21, 9], [21, 21]], Color("#cfc8ba"))
			_shape([[10, 21], [10, 16], [14, 16], [14, 21]], Color("#6b4a2a"), 1.5)
			_shape([[12, 6], [12, 2.5], [16, 4], [12, 5.5]], Color("#c7362b"), 1.2)
		"prov":   # web: v96.js PROV_SVG
			_shape([[7, 3.5], [16.5, 2.8], [21.3, 10.2], [18.2, 19.4], [8.8, 21.2], [2.8, 13.6]], Color("#9bd95f"), 1.8)
		"mana":   # web: v98.js MANA_STAR_SVG, a 7-pointed star
			var pts := []
			for k in 14:
				var a := -PI / 2 + k * PI / 7
				var r := 4.6 if k % 2 else 10.4
				pts.append([12 + cos(a) * r, 12.6 + sin(a) * r])
			_shape(pts, MANA_BLUE, 1.6)
		"ring":   # the payday: fills over the 10 s between paydays (web: the conic-gradient tick)
			var r := 12 - 1.5 * s
			draw_circle(c, r, Color("#e9edf3"))
			if value > 0.001:
				var pts := PackedVector2Array([c])
				var n := maxi(3, int(48 * value))
				for k in n + 1:
					var a := -PI / 2 + TAU * value * k / n
					pts.append(c + Vector2(cos(a), sin(a)) * r)
				draw_colored_polygon(pts, SUN)
			draw_arc(c, r, 0, TAU, 40, INK, 1.6 * s, true)
		"rp_gov", "rp_mil", "rp_mag", "rp_gov_off", "rp_mil_off", "rp_mag_off":   # web: content.js rpSVG, a tree's banner
			var off: bool = kind.ends_with("_off")
			var tr: String = kind.substr(3, 3)
			var col: Color = Color("#9aa0aa") if off else {"gov": Color("#3f72d9"), "mil": Color("#c8473d"), "mag": Color("#7a55c9")}[tr]
			var cream := Color("#eceef2") if off else Color("#faf1dc")
			var rod := Color("#c9ced8") if off else Color("#ffc93c")
			# (the web's 20 × 24 banner, moved 2 to the right on this 24 grid)
			var o := Vector2(2, 0)
			var ban := PackedVector2Array([Vector2(3, 3.2) + o, Vector2(17, 3.2) + o, Vector2(17, 21.5) + o, Vector2(10, 18) + o, Vector2(3, 21.5) + o])
			draw_colored_polygon(ban, col)
			var bl := ban.duplicate()
			bl.append(ban[0])
			draw_polyline(bl, INK, 1.4, true)
			draw_rect(Rect2(Vector2(1.4, 1.4) + o, Vector2(17.2, 2.4)), rod)
			draw_rect(Rect2(Vector2(1.4, 1.4) + o, Vector2(17.2, 2.4)), INK, false, 1.0)
			if tr == "gov":
				for r in [Rect2(5.6, 6.2, 8.8, 1.9), Rect2(7.3, 8.1, 5.4, 6.9), Rect2(5.6, 15, 8.8, 1.9)]:
					var rr: Rect2 = Rect2(r.position + o, r.size)
					draw_rect(rr, cream)
					draw_rect(rr, INK, false, 0.8)
			elif tr == "mil":
				for ln in [[6, 5.6, 13.4, 13.4, 1.5], [14, 5.6, 6.6, 13.4, 1.5], [11.3, 14.4, 14.4, 11.3, 1.3], [8.7, 14.4, 5.6, 11.3, 1.3], [13.6, 13.6, 15, 15, 1.4], [6.4, 13.6, 5, 15, 1.4]]:
					var a := Vector2(ln[0], ln[1]) + o
					var b := Vector2(ln[2], ln[3]) + o
					draw_line(a, b, INK, ln[4] + 1.3, true)
					draw_line(a, b, cream, ln[4], true)
			else:
				var st := PackedVector2Array()
				for k in 14:
					var ang := -PI / 2 + k * PI / 7
					var rad := 2.1 if k % 2 else 4.9
					st.append(Vector2(10 + cos(ang) * rad, 11.4 + sin(ang) * rad) + o)
				draw_colored_polygon(st, cream)
				var sl := st.duplicate()
				sl.append(st[0])
				draw_polyline(sl, INK, 0.8, true)
		"tree_gov", "tree_mil", "tree_mag":   # a research tree: empty when idle, its color filling as research goes
			var r := 12 - 1.5 * s
			draw_circle(c, r, Color("#f4ead2"))
			if active and value > 0.001:
				var pts := PackedVector2Array([c])
				var n := maxi(3, int(40 * value))
				for k in n + 1:
					var a := -PI / 2 + TAU * value * k / n
					pts.append(c + Vector2(cos(a), sin(a)) * r)
				draw_colored_polygon(pts, TREE_COL[kind])
			draw_arc(c, r, 0, TAU, 40, TREE_COL[kind] if active else INK, 1.6 * s, true)
		"play":
			_shape([[8, 5], [19, 12], [8, 19]], color, 1.0)
		"pause":
			draw_rect(Rect2(Vector2(7, 5) * s, Vector2(3.5, 14) * s), color)
			draw_rect(Rect2(Vector2(13.5, 5) * s, Vector2(3.5, 14) * s), color)
		"full":
			for q in [[[4, 9], [4, 4], [9, 4]], [[15, 4], [20, 4], [20, 9]], [[20, 15], [20, 20], [15, 20]], [[9, 20], [4, 20], [4, 15]]]:
				draw_polyline(_pts(q), color, 2.2 * s, true)
		"plus":
			draw_line(Vector2(5, 12) * s, Vector2(19, 12) * s, color, 2.2 * s)
			draw_line(Vector2(12, 5) * s, Vector2(12, 19) * s, color, 2.2 * s)
		"minus":
			draw_line(Vector2(5, 12) * s, Vector2(19, 12) * s, color, 2.2 * s)
		"home":
			draw_polyline(_pts([[4, 12], [12, 4.5], [20, 12]]), color, 2.0 * s, true)
			draw_polyline(_pts([[6.5, 10], [6.5, 19.5], [17.5, 19.5], [17.5, 10]]), color, 2.0 * s, true)
		"gear":
			var ro := 9.5 * s
			var ri := 7.0 * s
			var pts := PackedVector2Array()
			for k in 32:
				var a := TAU * k / 32.0
				var r := ro if (k % 4) < 2 else ri
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, color)
			draw_circle(c, 3.2 * s, Color("#f4ead2"))
		"close", "cross":
			draw_line(Vector2(6, 6) * s, Vector2(18, 18) * s, color, 2.4 * s)
			draw_line(Vector2(18, 6) * s, Vector2(6, 18) * s, color, 2.4 * s)
		"check":
			draw_polyline(_pts([[5, 12.5], [10, 17.5], [19, 6.5]]), color, 2.6 * s, true)
		"war":   # two crossed swords
			for d in [1.0, -1.0]:
				var a := Vector2(12 - 7 * d, 5) * s
				var b := Vector2(12 + 6 * d, 18) * s
				draw_line(a, b, color, 2.2 * s)
				var m := Vector2(12 + 3 * d, 14.5) * s
				draw_line(m + Vector2(-3, 1.5 * d) * s, m + Vector2(3, -1.5 * d) * s, color, 2.0 * s)
		"tri_r":
			_shape([[8, 6], [17, 12], [8, 18]], color, 0.8)
		"tri_d":
			_shape([[6, 8], [18, 8], [12, 17]], color, 0.8)
		"hammer":
			draw_line(Vector2(7, 19) * s, Vector2(15, 9) * s, Color("#7a4f2a"), 2.6 * s)
			_shape([[11, 5], [19, 11], [17, 13.5], [9, 7.5]], Color("#9aa0a8"), 1.3)
