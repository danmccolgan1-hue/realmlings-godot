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
	var P: Dictionary = GameData.c("PLAYERS")
	for i in map.polys.size():
		var pts := PackedVector2Array()
		for v in map.polys[i]:
			pts.append(_to_mini(v))
		var known: bool = game.explored.has(i)
		var col := Color(MapLayers.TER[game.G.provs[i].terrain][0]) if known else FOG
		if known and not game.visible.has(i):
			col = col.darkened(0.3)
		draw_colored_polygon(pts, col)
		if game.buildings.has(i):
			pts.append(pts[0])
			draw_polyline(pts, Color(P[str(game.buildings[i].owner)].color), 2.5)
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
