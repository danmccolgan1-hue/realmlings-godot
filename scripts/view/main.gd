extends Node2D
## Entry point. Milestone 1 so far: pick a seed and a Realmling leader, then play the Practice island.
## Space: pause / play. Left-click: select a unit or a province. Right-click: send the selected unit there.
## Command card keys: q w e r / a s d f / z x c v / u i o p. T: research (with no unit selected).
## Drag (left or middle mouse) to pan, wheel to zoom.

const SEED_WORDS := ["ember", "oak", "river", "banner", "moss", "crown", "lantern", "stone", "harbor", "thistle", "kettle", "saffron"]

var map: MapView
var cam: Camera2D
var hud: Hud
var menu: PanelContainer
var seed_edit: LineEdit
var leader_pick: OptionButton
var leader_ids := [""]
var status: Label
var thread: Thread
var game: Game
var dragging := false
var drag_moved := 0.0


func _ready() -> void:
	map = MapView.new()
	add_child(map)
	cam = Camera2D.new()
	add_child(cam)
	hud = Hud.new()
	add_child(hud)
	_build_menu()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_edit.text = a.substr(7)
		elif a.begins_with("--leader="):
			var i := leader_ids.find(a.substr(9))
			if i >= 0:
				leader_pick.selected = i
		elif a.begins_with("--shot="):
			_start.call_deferred()


func _build_menu() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	menu = PanelContainer.new()
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	menu.add_theme_stylebox_override("panel", Hud._box(Color("#faf1dc")))
	ui.add_child(menu)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(560, 0)
	menu.add_child(col)
	var title := Label.new()
	title.text = "Realmlings"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color("#1d1a22"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	col.add_child(_dark("Practice island: 10 provinces, just you."))
	col.add_child(_dark("Seed"))
	seed_edit = LineEdit.new()
	seed_edit.text = SEED_WORDS.pick_random()
	col.add_child(seed_edit)
	col.add_child(_dark("Leader"))
	leader_pick = OptionButton.new()
	leader_pick.add_item("Random")
	var L: Dictionary = GameData.c("LEADERS")
	for id in L:
		if L[id].race == "realm":
			leader_ids.append(id)
			leader_pick.add_item("%s — %s" % [L[id].full, L[id].bonus.split(".")[0]])
	col.add_child(leader_pick)
	var start := Button.new()
	start.text = "Start"
	start.add_theme_font_size_override("font_size", 28)
	start.pressed.connect(_start)
	col.add_child(start)
	status = _dark("")
	col.add_child(status)


func _dark(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", Color("#1d1a22"))
	l.add_theme_font_size_override("font_size", 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _start() -> void:
	if thread and thread.is_alive():
		return
	var seed := seed_edit.text.strip_edges()
	if seed == "":
		seed = SEED_WORDS.pick_random()
	status.text = "Raising the island…"
	thread = Thread.new()
	thread.start(_gen.bind(seed, leader_ids[leader_pick.selected]))


func _gen(seed: String, leader_id: String) -> void:
	var g := Game.new_practice(seed, leader_id)
	call_deferred("_on_ready", g)


func _on_ready(g: Game) -> void:
	thread.wait_to_finish()
	game = g
	menu.hide()
	map.set_game(g)
	hud.set_game(g)
	var b := map.bounds()
	cam.position = b.get_center()
	var vp := get_viewport_rect().size
	var z := minf(vp.x / b.size.x, vp.y / b.size.y) * 0.8
	cam.zoom = Vector2(z, z)
	_maybe_screenshot()


func _process(_delta: float) -> void:
	if game:
		game.update(Time.get_ticks_msec() / 1000.0)


## For checking the view without a person: godot --path . -- --shot=/tmp/a.png [--seed=ember] [--leader=finn]
## [--play=25] starts a game, lets it run that many game seconds, saves a picture and quits.
func _maybe_screenshot() -> void:
	var shot := ""
	var play := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--play="):
			play = float(a.substr(7))
	if shot == "":
		return
	hud.select_province(game.capital)
	map.selected_prov = game.capital
	var mason = null
	var wfu = null
	for u in game.units:
		if u.kind == Game.MASON and mason == null:
			mason = u
		elif u.kind == game.WAYFINDER and wfu == null:
			wfu = u
	if play > 0:
		game.queue_survey(wfu, game.open_nbr[game.capital][0].q)
		game.order_build(mason, game.capital, "farm")
		game.paused = false
		var real := 1.0
		while game.t < play:
			real += 0.1
			game.update(real)
		game.paused = true
		game.last = 0.0
		game.update(Time.get_ticks_msec() / 1000.0)
	if OS.get_cmdline_user_args().has("--research"):
		hud.toggle_research()
	else:
		map.selected_unit = mason
		hud.select_unit(mason)
	var b := map.bounds()
	cam.zoom = Vector2(0.55, 0.55)
	cam.position = Vector2(game.G.provs[game.capital].ic[0], game.G.provs[game.capital].ic[1] - 60)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and game:
		if ev.keycode == KEY_SPACE:
			game.paused = not game.paused
			get_viewport().set_input_as_handled()
			return
		if ev.keycode == KEY_T and hud.unit == null:
			hud.toggle_research()
			get_viewport().set_input_as_handled()
			return
		if hud.key(OS.get_keycode_string(ev.keycode).to_lower()):
			get_viewport().set_input_as_handled()
			return
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			cam.zoom = (cam.zoom * 1.15).clamp(Vector2(0.03, 0.03), Vector2(3, 3))
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			cam.zoom = (cam.zoom / 1.15).clamp(Vector2(0.03, 0.03), Vector2(3, 3))
		elif ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			if ev.pressed:
				dragging = true
				drag_moved = 0.0
			else:
				dragging = false
				if ev.button_index == MOUSE_BUTTON_LEFT and drag_moved < 6.0 and game:
					var at := get_global_mouse_position()
					var u = map.unit_at(at)
					map.selected_unit = u
					hud.select_unit(u)
					var p: int = u.prov if u != null else map.province_at(at)
					map.selected_prov = p
					hud.select_province(p)
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed and game and map.selected_unit != null:
			var at := get_global_mouse_position()
			var p := map.province_at(at)
			if p >= 0:
				game.order(map.selected_unit, p, false, [at.x, at.y])
	elif ev is InputEventMouseMotion and dragging:
		drag_moved += ev.relative.length()
		cam.position -= ev.relative / cam.zoom


func _exit_tree() -> void:
	if thread and thread.is_started():
		thread.wait_to_finish()
