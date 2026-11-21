class_name Minimap
extends Control
## The whole island at a glance: explored land in its terrain colors, your provinces outlined in your color, your
## units as dots, raiders you can see in red, and the camera's view as a frame. Click or drag to look there.
## web: game.js #mini

const SIZE := Vector2(280, 210)
const FOG := Color("#2f3b55")

var game: Game
var map: MapView
var cam: Camera2D
var rect := Rect2()       # world bounds shown
var dragging := false


func setup(g: Game, m: MapView, c: Camera2D) -> void:
	game = g
	map = m
	cam = c
	custom_minimum_size = SIZE
	size = SIZE
	rect = map.bounds().grow(300)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if togs == null:
		_build_toggles()


# --- the four toggles over the minimap: resources, province names, nation names, nation colors on the minimap.
# web: v78.js .mini-togs (TG_ICON, VIEW) ---

var togs: HBoxContainer
const TOGS := [["res", "Show or hide each province’s resources"], ["names", "Show each province’s name under its resources"],
	["realm", "Show nation names over their land"], ["miniColor", "Fill the minimap with each nation’s color"]]


func _build_toggles() -> void:
	togs = HBoxContainer.new()
	togs.add_theme_constant_override("separation", 6)
	togs.position = Vector2(-3, -44)
	add_child(togs)
	for t in TOGS:
		var b := Control.new()
		b.custom_minimum_size = Vector2(38, 38)
		b.tooltip_text = t[1]
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var key: String = t[0]
		b.draw.connect(_draw_toggle.bind(b, key))
		b.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				Settings.view[key] = not Settings.view.get(key, false)
				Settings.save_all()
				b.queue_redraw()
				b.accept_event())
		togs.add_child(b)


func _draw_toggle(b: Control, key: String) -> void:
	var on: bool = Settings.view.get(key, false)
	var r := Rect2(Vector2.ZERO, b.size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#ffc93c") if on else Color("#faf1dc")
	sb.border_color = UiKit.INK
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0.08, 0.06, 0.1, 0.25)
	sb.shadow_size = 2
	b.draw_style_box(sb, r)
	var mod := Color.WHITE if on else Color(1, 1, 1, 0.35)
	var c := r.get_center()
	match key:
		"res":
			var sp = Art.get_sprite("icons", "common", "res_gold.png")
			if sp:
				b.draw_texture_rect(sp.tex, Rect2(c - Vector2(14, 14), Vector2(28, 28)), false, mod if on else Color(0.6, 0.6, 0.6, 0.35))
		"names":
			var hex := PackedVector2Array()
			for v in [[7, 3.5], [16.5, 2.8], [21.3, 10.2], [18.2, 19.4], [8.8, 21.2], [2.8, 13.6]]:
				hex.append(c + (Vector2(v[0], v[1]) - Vector2(12, 12)) * 1.2)
			b.draw_colored_polygon(hex, Color("#9bd95f") * mod if on else Color(0.62, 0.62, 0.62, 0.35))
			hex.append(hex[0])
			b.draw_polyline(hex, Color(UiKit.INK, mod.a), 2.0, true)
			b.draw_line(c + Vector2(-5, -1), c + Vector2(5.5, -1), Color(UiKit.INK, mod.a), 1.6)
			b.draw_line(c + Vector2(-5, 3), c + Vector2(2.5, 3), Color(UiKit.INK, mod.a), 1.6)
		"realm":
			var tex = Art.nation_flag(game, Game.ME) if game else null
			if tex:
				b.draw_texture_rect(tex, Rect2(c - Vector2(14, 10), Vector2(28, 20)), false, mod if on else Color(0.6, 0.6, 0.6, 0.35))
		"miniColor":
			var q := Rect2(c - Vector2(11, 11), Vector2(22, 22))
			b.draw_rect(q, Color("#faf1dc"))
			for i in 5:
				var o := -11.0 + i * 6.0
				var a := c + Vector2(-11, o + 6)
				var e := c + Vector2(o + 6, -11)
				b.draw_line(a, e, Color("#c7362b", 1.0 if on else 0.35), 2.0)
			b.draw_rect(q, Color(UiKit.INK, mod.a), false, 2.0)


func _to_mini(v: Vector2) -> Vector2:
	var k := minf(SIZE.x / rect.size.x, SIZE.y / rect.size.y)
	var off := (SIZE - rect.size * k) / 2
	return off + (v - rect.position) * k


func _to_world(p: Vector2) -> Vector2:
	var k := minf(SIZE.x / rect.size.x, SIZE.y / rect.size.y)
	var off := (SIZE - rect.size * k) / 2
	return rect.position + (p - off) / k


func _draw() -> void:
	if game == null:
		return
	draw_rect(Rect2(Vector2.ZERO, SIZE), MapLayers.SEA.darkened(0.15))
	for i in map.polys.size():
		var pts := PackedVector2Array()
		for v in map.polys[i]:
			pts.append(_to_mini(v))
		var known: bool = game.explored.has(i)
		var col := Color(MapLayers.TER[game.G.provs[i].terrain][0]) if known else FOG
		if known and not game.visible.has(i):
			col = col.darkened(0.3)
		draw_colored_polygon(pts, col)
		if known and Settings.view.get("miniColor", false):   # web: game.js Z14, each nation's color over its land
			var own := game.nation_of(i)
			if own > 0:
				draw_colored_polygon(pts, Color(game.player_info(own).color, 0.8))
		if game.buildings.has(i):
			pts.append(pts[0])
			draw_polyline(pts, Color(game.player_info(game.buildings[i].owner).color), 2.5)
	for u in game.units:
		if u.owner != Game.ME and not game.visible.has(u.prov):
			continue
		var c := Color("#fff6c8") if u.owner == Game.ME else Color("#d8473a")
		var at := _to_mini(Vector2(u.x, u.y))
		draw_circle(at, 3.5 if u.kind == "army" else 2.5, c)
	if cam:
		var vs := get_viewport().get_visible_rect().size / cam.zoom
		var a := _to_mini(cam.position - vs / 2)
		var b := _to_mini(cam.position + vs / 2)
		draw_rect(Rect2(a, b - a).intersection(Rect2(Vector2.ZERO, SIZE)), Color.WHITE, false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, SIZE), UiKit.INK, false, 3.0)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		dragging = ev.pressed
		if ev.pressed:
			cam.position = _to_world(ev.position)
		accept_event()
	elif ev is InputEventMouseMotion and dragging:
		cam.position = _to_world(ev.position)
		accept_event()


func _process(_dt: float) -> void:
	if game:
		queue_redraw()
