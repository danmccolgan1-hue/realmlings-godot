extends Node2D
## Entry point. Milestone 1 so far: pick a seed and a Realmling leader, then play the Practice island.
## Space: pause / play. Left-click: select a unit or a province. Right-click: send the selected unit there.
## Command card keys: q w e r / a s d f / z x c v / u i o p. T: research (with no unit selected).
## F5: quick save, F9: quick load; an autosave every 5 minutes of play.
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
		elif a == "--tutorial":
			_on_ready.call_deferred(Tutorial.start(), false)
		elif a.begins_with("--shot=") and not OS.get_cmdline_user_args().has("--tutorial"):
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
	var tut := Button.new()
	tut.text = "Basic Tutorial"
	tut.add_theme_font_size_override("font_size", 22)
	tut.pressed.connect(func(): _on_ready(Tutorial.start(), false))
	col.add_child(tut)
	var cont := Button.new()
	cont.text = "Continue (last autosave)"
	cont.add_theme_font_size_override("font_size", 22)
	cont.pressed.connect(func(): load_from(AUTOSAVE))
	cont.visible = FileAccess.file_exists(AUTOSAVE)
	col.add_child(cont)
	var quick := Button.new()
	quick.text = "Load quicksave (F9)"
	quick.add_theme_font_size_override("font_size", 22)
	quick.pressed.connect(func(): load_from(QUICKSAVE))
	quick.visible = FileAccess.file_exists(QUICKSAVE)
	col.add_child(quick)
	status = _dark("F5 saves, F9 loads, the game autosaves every 5 minutes.")
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


func _on_ready(g: Game, from_thread := true) -> void:
	if from_thread:
		thread.wait_to_finish()
	game = g
	next_autosave = (floor(g.t / AUTOSAVE_EVERY) + 1) * AUTOSAVE_EVERY
	menu.hide()
	map.set_game(g)
	hud.set_game(g)
	var b := map.bounds()
	cam.position = b.get_center()
	var vp := get_viewport_rect().size
	var z := minf(vp.x / b.size.x, vp.y / b.size.y) * 0.8
	cam.zoom = Vector2(z, z)
	_maybe_screenshot()


const QUICKSAVE := "user://quicksave.json"
const AUTOSAVE := "user://autosave.json"
const AUTOSAVE_EVERY := 300.0   # web: an autosave every 5 minutes of play
var next_autosave := AUTOSAVE_EVERY


func save_to(path: String, quiet := false) -> void:
	if game.tutorial != null:
		if not quiet:
			hud.add_toast("Saving is turned off in the tutorial.", true)
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		hud.add_toast("Couldn't save: %s" % error_string(FileAccess.get_open_error()), true)
		return
	f.store_string(game.save_text())
	f.close()
	if not quiet:
		hud.add_toast("Saved.")


func load_from(path: String) -> void:
	if not FileAccess.file_exists(path):
		if hud.visible:
			hud.add_toast("No saved game yet.", true)
		else:
			status.text = "No saved game yet."
		return
	var g := Game.load_text(FileAccess.get_file_as_string(path))
	if g == null:
		status.text = "That save can't be read."
		return
	g.paused = true
	g.last = 0.0
	map.selected_unit = null
	hud.select_unit(null)
	hud.select_province(-1)
	_on_ready(g, false)
	hud.add_toast("Loaded. The game is paused: press Space to go on.")


func _process(_delta: float) -> void:
	if game:
		game.update(Time.get_ticks_msec() / 1000.0)
		if game.t >= next_autosave:
			next_autosave = (floor(game.t / AUTOSAVE_EVERY) + 1) * AUTOSAVE_EVERY
			if game.tutorial == null:
				save_to(AUTOSAVE, true)
				hud.add_toast("Autosaved.")


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
	var demo := OS.get_cmdline_user_args().has("--demo")
	var q1: int = game.open_nbr[game.capital][0].q
	var spells := OS.get_cmdline_user_args().has("--spells")
	var army = null
	for u in game.units:
		if u.kind == "army":
			army = u
	var battle := OS.get_cmdline_user_args().has("--battle")
	if play > 0 and battle:   # Cormac's Shield Footmen against a Bandit Gang next door, as in tests/fixtures/play/*_battle.json
		var gang := game.spawn_bandit(q1)
		gang.troops = {"d-sword": 5}
		game.order(army, q1)
	elif play > 0 and spells:   # Havva's Herbomancy, as in tests/fixtures/play/*_life.json
		game.grant_tech("school-life")
		for id in ["harvest", "mending", "forest", "eyesforest"]:
			game.grant_tech(id)
		game.order_build(mason, game.capital, "farm")
	elif play > 0 and demo:   # roads, walls and development: the scripted game of tests/fixtures/play/*_roads.json
		for k in Game.RES:
			game.stock[k] += 3000
		game.grant_tech("roads")
		game.queue_survey(wfu, q1)
		game.start_develop(game.capital)
	elif play > 0 and game.tutorial == null:
		game.queue_survey(wfu, game.open_nbr[game.capital][0].q)
		game.order_build(mason, game.capital, "farm")
	if play > 0:
		game.paused = false
		var real := 1.0
		var step := 0
		while game.t < play:
			real += 0.1
			if spells and step == 350:
				game.cast_spell(army, "harvest")
			if demo:
				if step == 400:
					game.order_build(mason, q1, "outpost")
				elif step == 900:
					game.start_link(mason, game.capital, "road")
				elif step == 1010:
					game.grant_tech("walls")
				elif step == 1020:
					for u in game.units:
						if u.kind == "army":
							game.order(u, q1)
			step += 1
			game.update(real)
		game.paused = true
		game.last = 0.0
		game.update(Time.get_ticks_msec() / 1000.0)
	if OS.get_cmdline_user_args().has("--research"):
		hud.toggle_research()
	elif spells or battle:
		map.selected_unit = army
		hud.select_unit(army)
	else:
		map.selected_unit = mason
		hud.select_unit(mason)
	var b := map.bounds()
	var zoom := 0.55
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	cam.zoom = Vector2(zoom, zoom)
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
		if ev.keycode == KEY_F5:
			save_to(QUICKSAVE)
			return
		if ev.keycode == KEY_F9:
			load_from(QUICKSAVE)
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
				if ev.button_index == MOUSE_BUTTON_LEFT and drag_moved < 6.0 and game and hud.aim != null:
					var tp := map.province_at(get_global_mouse_position())
					if tp >= 0:
						game.cast_spell(hud.aim.unit, hud.aim.spell, tp)
					hud.aim = null
				elif ev.button_index == MOUSE_BUTTON_LEFT and drag_moved < 6.0 and game:
					var at := get_global_mouse_position()
					var u = map.unit_at(at)
					map.selected_unit = u
					hud.select_unit(u)
					var p: int = u.prov if u != null else map.province_at(at)
					map.selected_prov = p
					hud.select_province(p)
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed and game and hud.aim != null:
			hud.aim = null
			hud.add_toast("Cancelled.")
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
