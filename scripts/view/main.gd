extends Node2D
## Entry point. Milestone 1 so far: generates the Practice island (on a background thread) and shows it.
## Drag with the left or middle mouse button to pan, scroll to zoom, R for a new random island.

const SEED_WORDS := ["ember", "oak", "river", "banner", "moss", "crown", "lantern", "stone", "harbor", "thistle", "kettle", "saffron"]

var map: MapView
var cam: Camera2D
var status: Label
var thread: Thread
var dragging := false
var seed := "Practice"


func _ready() -> void:
	map = MapView.new()
	add_child(map)
	cam = Camera2D.new()
	add_child(cam)
	var ui := CanvasLayer.new()
	add_child(ui)
	status = Label.new()
	status.position = Vector2(24, 16)
	status.add_theme_font_size_override("font_size", 28)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 6)
	ui.add_child(status)
	generate(seed)


func generate(s: String) -> void:
	if thread and thread.is_alive():
		return
	seed = s
	status.text = "Raising the island…  (seed \"%s\")" % seed
	thread = Thread.new()
	thread.start(_gen.bind(seed))


func _gen(s: String) -> void:
	var t0 := Time.get_ticks_msec()
	var w := RealmGen.scale_world(RealmGen.generate_practice(s))
	call_deferred("_on_generated", w, Time.get_ticks_msec() - t0)


func _on_generated(w: Dictionary, ms: int) -> void:
	thread.wait_to_finish()
	if w.provinces.is_empty():
		status.text = "Generation failed for seed \"%s\"" % seed
		return
	map.set_world(w)
	var b := map.bounds()
	cam.position = b.get_center()
	var vp := get_viewport_rect().size
	var z := minf(vp.x / b.size.x, vp.y / b.size.y) * 0.85
	cam.zoom = Vector2(z, z)
	_maybe_screenshot()
	status.text = "Practice island \"%s\" — %d provinces, built in %.1f s.   Drag to pan, wheel to zoom, R for a new island." % [seed, w.provinces.size(), ms / 1000.0]


## For checking the view without a person: godot --path . -- --shot=res://shot.png saves a picture and quits.
func _maybe_screenshot() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(a.substr(7))
			get_tree().quit()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			cam.zoom *= 1.15
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			cam.zoom /= 1.15
		elif ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			dragging = ev.pressed
	elif ev is InputEventMouseMotion and dragging:
		cam.position -= ev.relative / cam.zoom
	elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_R:
		generate(SEED_WORDS.pick_random() + str(randi() % 1000))


func _exit_tree() -> void:
	if thread and thread.is_started():
		thread.wait_to_finish()
