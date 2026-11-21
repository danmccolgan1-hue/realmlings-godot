class_name Pen
extends RefCounted
## A small stand-in for the web game's canvas paths, so its drawing code ports almost line for line:
## move / line / quad / bez / ellipse / rect build a path, then fill or stroke draws it on a CanvasItem.
## The pen has its own transform (at / turn / grow, saved and restored with push / pop), because Art.draw
## resets the CanvasItem's transform. Only draws; never changes the game.

const OL := Color("#1d1a22")

var subs := []                     # [{pts: PackedVector2Array, closed: bool}]
var cur := PackedVector2Array()
var cur_closed := false
var xf := Transform2D.IDENTITY
var _stack := []
var ci: CanvasItem


func _init(target: CanvasItem) -> void:
	ci = target


# --- transform (web: g.save / g.translate / g.rotate / g.scale / g.restore) ---

func push() -> Pen:
	_stack.append(xf)
	return self


func pop() -> Pen:
	xf = _stack.pop_back() if not _stack.is_empty() else Transform2D.IDENTITY
	return self


func at(x: float, y: float) -> Pen:
	xf = xf * Transform2D(0.0, Vector2(x, y))
	return self


func turn(a: float) -> Pen:
	xf = xf * Transform2D(a, Vector2.ZERO)
	return self


func grow(sx: float, sy := NAN) -> Pen:
	xf = xf * Transform2D.IDENTITY.scaled(Vector2(sx, sx if is_nan(sy) else sy))
	return self


func k() -> float:   # how much the pen's transform scales line widths
	return sqrt(absf(xf.determinant()))


# --- paths ---

func begin() -> Pen:
	subs = []
	cur = PackedVector2Array()
	cur_closed = false
	return self


func _flush() -> void:
	if cur.size() > 0:
		subs.append({"pts": cur, "closed": cur_closed})
	cur = PackedVector2Array()
	cur_closed = false


func move(x: float, y: float) -> Pen:
	_flush()
	cur.append(xf * Vector2(x, y))
	return self


func line(x: float, y: float) -> Pen:
	cur.append(xf * Vector2(x, y))
	return self


func _last() -> Vector2:
	return xf.affine_inverse() * cur[cur.size() - 1] if cur.size() > 0 else Vector2.ZERO


func quad(cx: float, cy: float, x: float, y: float, steps := 10) -> Pen:
	var p0 := _last()
	var c := Vector2(cx, cy)
	var p1 := Vector2(x, y)
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var p := p0 * (1 - t) * (1 - t) + c * 2 * (1 - t) * t + p1 * t * t
		cur.append(xf * p)
	return self


func bez(c1x: float, c1y: float, c2x: float, c2y: float, x: float, y: float, steps := 12) -> Pen:
	var p0 := _last()
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var u := 1.0 - t
		var p := p0 * u * u * u + Vector2(c1x, c1y) * 3 * u * u * t + Vector2(c2x, c2y) * 3 * u * t * t + Vector2(x, y) * t * t * t
		cur.append(xf * p)
	return self


## An ellipse or part of one, joined to the path so far like the canvas's ellipse(); a0 to a1 clockwise on screen.
func ellipse(cx: float, cy: float, rx: float, ry: float, a0 := 0.0, a1 := TAU, rot := 0.0) -> Pen:
	var span := a1 - a0
	if span < 0:
		span += TAU
	span = minf(span, TAU)
	var n := maxi(8, int(ceil(span / TAU * clampf((rx + ry) * k() * 0.25, 16, 56))))
	var R := Transform2D(rot, Vector2(cx, cy))
	for i in n + 1:
		var a := a0 + span * i / n
		cur.append(xf * (R * Vector2(cos(a) * rx, sin(a) * ry)))
	if span >= TAU - 0.001:
		cur_closed = true
	return self


func arc(cx: float, cy: float, r: float, a0 := 0.0, a1 := TAU) -> Pen:
	return ellipse(cx, cy, r, r, a0, a1)


func rect(x: float, y: float, w: float, h: float) -> Pen:
	move(x, y).line(x + w, y).line(x + w, y + h).line(x, y + h)
	cur_closed = true
	_flush()
	return self


func close() -> Pen:
	cur_closed = true
	var first := cur[0] if cur.size() > 0 else Vector2.ZERO
	_flush()
	cur.append(first)   # the canvas starts the next part where the closed one began
	return self


## Take a ready-made polygon (world points, already transformed) as the path.
func poly(pts: PackedVector2Array, closed := true) -> Pen:
	_flush()
	cur = pts.duplicate()
	cur_closed = closed
	_flush()
	return self


func paths() -> Array:
	_flush()
	var out := []
	for s in subs:
		if s.pts.size() >= 2:
			out.append(s)
	return out


# --- drawing ---

func fill(col: Color) -> Pen:
	for s in paths():
		fill_poly(ci, s.pts, col)
	return self


## Stroke the path; `w` is in the pen's units (the canvas lineWidth), joins are rounded.
func stroke(w: float, col: Color) -> Pen:
	var ww := w * k()
	for s in paths():
		var pts: PackedVector2Array = s.pts
		if s.closed and pts[0].distance_to(pts[pts.size() - 1]) > 0.01:
			pts = pts.duplicate()
			pts.append(pts[0])
		stroke_line(ci, pts, col, ww)
	return self


## The common "ink" outline.
func ink(w := 2.6) -> Pen:
	return stroke(w, OL)


## fill, then outline in ink
func fink(col: Color, w := 2.6) -> Pen:
	fill(col)
	return ink(w)


static func fill_poly(c: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3 or col.a <= 0.001:
		return
	if pts[0].distance_to(pts[pts.size() - 1]) < 0.01:
		pts = pts.slice(0, pts.size() - 1)
		if pts.size() < 3:
			return
	if Geometry2D.triangulate_polygon(pts).is_empty():
		for part in Geometry2D.merge_polygons(pts, PackedVector2Array()):   # untangle a self-crossing outline
			if not Geometry2D.triangulate_polygon(part).is_empty():
				c.draw_colored_polygon(part, col)
		return
	c.draw_colored_polygon(pts, col)


static func stroke_line(c: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	if pts.size() < 2 or col.a <= 0.001:
		return
	c.draw_polyline(pts, col, w, true)
	if w >= 3.0 and col.a >= 0.99:   # round joins at the corners, as the web game's lineJoin = 'round'
		var r := w * 0.5
		for i in range(1, pts.size() - 1):
			var d0 := (pts[i] - pts[i - 1])
			var d1 := (pts[i + 1] - pts[i])
			if d0.length() > 0.01 and d1.length() > 0.01 and absf(d0.angle_to(d1)) > 0.35:
				c.draw_circle(pts[i], r, col)
		c.draw_circle(pts[0], r, col)
		c.draw_circle(pts[pts.size() - 1], r, col)


static var _glow_tex: GradientTexture2D

## A soft radial glow, `col` at the middle fading to nothing at the rim (web: createRadialGradient to alpha 0).
func glow(cx: float, cy: float, rx: float, ry: float, col: Color) -> Pen:
	if _glow_tex == null:
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = gr
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128
		_glow_tex.height = 128
	var c := xf * Vector2(cx, cy)
	var r := Vector2(rx, ry) * k()
	ci.draw_texture_rect(_glow_tex, Rect2(c - r, r * 2), false, col)
	return self


## Clip this path's fill to a polygon (web: g.clip), for shading drawn inside a shape.
func fill_in(clip: PackedVector2Array, col: Color) -> Pen:
	for s in paths():
		for part in Geometry2D.intersect_polygons(s.pts, clip):
			fill_poly(ci, part, col)
	return self


func stroke_in(clip: PackedVector2Array, w: float, col: Color) -> Pen:
	for s in paths():
		for part in Geometry2D.intersect_polyline_with_polygon(s.pts, clip):
			stroke_line(ci, part, col, w * k())
	return self
