extends Node2D
## Entry point. Milestone 1 so far: pick a seed and a Realmling leader, then play the Practice island.
## Space: pause / play. Left-click: select a unit or a province. Right-click: send the selected unit there.
## Command card keys: q w e r / a s d f / z x c v / u i o p. T: research (with no unit selected).
## F5: quick save, F9: quick load; an autosave every 5 minutes of play.
## Drag (left or middle mouse) or the arrow keys to pan, wheel to zoom, Home: back to the capital. G: the Armory.
## Esc: close a window, or open the menu.

const SEED_WORDS := ["ember", "oak", "river", "banner", "moss", "crown", "lantern", "stone", "harbor", "thistle", "kettle", "saffron"]

var map: MapView
var cam: Camera2D
var hud: Hud
var menu: PanelContainer
var seed_edit: LineEdit
var leader_pick: OptionButton
var leader_ids := [""]
var map_pick: OptionButton
var opp_box: VBoxContainer
var opp_count: OptionButton
var opp_diff: OptionButton
var start_pick: OptionButton
const DIFFS := ["easy", "moderate", "difficult"]
var shot_slots := []
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
	hud.main = self
	hud.map = map
	hud.cam = cam
	add_child(hud)
	_build_menu()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_edit.text = a.substr(7)
		elif a.begins_with("--leader="):
			var i := leader_ids.find(a.substr(9))
			if i >= 0:
				leader_pick.selected = i
		elif a.begins_with("--world="):   # a full map: --world=moderate,difficult,easy
			map_pick.selected = 1
			opp_box.visible = true
			shot_slots = a.substr(8).split(",")
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
	col.add_child(_dark("Map"))
	map_pick = OptionButton.new()
	map_pick.add_item("Practice island — 10 provinces, just you")
	map_pick.add_item("Full map — computer nations, wars and diplomacy")
	map_pick.item_selected.connect(func(i): opp_box.visible = i == 1)
	col.add_child(map_pick)
	opp_box = VBoxContainer.new()
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 10)
	var ol := _dark("Opponents")
	orow.add_child(ol)
	opp_count = OptionButton.new()
	for n in range(1, 7):
		opp_count.add_item(str(n))
	opp_count.selected = 2
	orow.add_child(opp_count)
	opp_diff = OptionButton.new()
	for d in ["Easy", "Moderate", "Difficult", "Mixed"]:
		opp_diff.add_item(d)
	opp_diff.selected = 1
	orow.add_child(opp_diff)
	start_pick = OptionButton.new()
	for d in ["Start in the center", "Start at the edge", "Random start"]:
		start_pick.add_item(d)
	orow.add_child(start_pick)
	opp_box.add_child(orow)
	opp_box.visible = false
	col.add_child(opp_box)
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


## Leave the game for the start screen (from the in-game menu).
func to_main_menu() -> void:
	if game and game.tutorial == null:
		save_to(AUTOSAVE, true)
	game = null
	hud.game = null
	hud.hide()
	map.game = null
	menu.show()


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
	var slots := Array(shot_slots)
	if map_pick.selected == 1 and slots.is_empty():
		for i in opp_count.selected + 1:
			slots.append(DIFFS[i % 3] if opp_diff.selected == 3 else DIFFS[opp_diff.selected])
	status.text = "Raising the island…" if slots.is_empty() else "Raising the world and its nations…"
	thread = Thread.new()
	thread.start(_gen.bind(seed, leader_ids[leader_pick.selected], slots, ["center", "edge", "random"][start_pick.selected]))


func _gen(seed: String, leader_id: String, slots := [], start := "center") -> void:
	var g := Game.new_practice(seed, leader_id) if slots.is_empty() else Game.new_world(seed, leader_id, slots, start)
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


func _process(delta: float) -> void:
	if game:
		_camera(delta)
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
	if play > 0 and OS.get_cmdline_user_args().has("--siege") and not game.nations.is_empty():
		# as in tests/fixtures/siege/siege.json: a walled capital next door, 20 Footmen battering their way in
		var foe: int = game.nations.keys()[0]
		var fc := game.capital_of(foe)
		var qs: Array = game.open_nbr[fc].map(func(n): return n.q).filter(func(p): return not game.buildings.has(p) and not game.unique_ban(p))
		game.ai_frozen = true
		game.nations[foe].tech.gov.done.append("walls")
		game.buildings[qs[0]] = {"stage": 0, "born": 0, "owner": Game.ME}
		game.surveyed[qs[0]] = 0
		game.stock.gold += 500
		game.stock.food += 3000
		for o in game.nations:
			game.met[o] = true
		game.compute_income()
		game.compute_fog()
		game.update(1.0)
		game.declare_war(Game.ME, foe)
		army = game.new_army(qs[0], {"d-sword": 20})
		game.order(army, fc)
		battle = true
	if play > 0 and battle and not OS.get_cmdline_user_args().has("--siege"):   # Cormac's Shield Footmen against a Bandit Gang next door, as in tests/fixtures/play/*_battle.json
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
	if OS.get_cmdline_user_args().has("--reveal"):   # see the whole map (for pictures of the other nations)
		game.reveal_all = true
		game.compute_fog()
		for o in game.nations:
			game.met[o] = true
		map.layers.refresh()
	if OS.get_cmdline_user_args().has("--dip"):
		hud.diplomacy.open()
	if OS.get_cmdline_user_args().has("--research"):
		hud.toggle_research()
	elif spells or battle:
		map.selected_unit = army
		hud.select_unit(army)
	else:
		map.selected_unit = mason
		hud.select_unit(mason)
	if OS.get_cmdline_user_args().has("--armory"):
		hud.armory.open()
	if OS.get_cmdline_user_args().has("--orders"):
		hud.armory.open(1)
	var b := map.bounds()
	var zoom := 0.55
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	cam.zoom = Vector2(zoom, zoom)
	cam.position = Vector2(game.G.provs[game.capital].ic[0], game.G.provs[game.capital].ic[1] - 60)
	if OS.get_cmdline_user_args().has("--siege") and army != null:
		cam.position = Vector2(army.x, army.y)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="):   # the n-th computer nation's capital
			var ids: Array = game.nations.keys()
			var o: int = ids[mini(int(a.substr(7)), ids.size() - 1)]
			var c := game.capital_of(o)
			if c >= 0:
				cam.position = Vector2(game.G.provs[c].ic[0], game.G.provs[c].ic[1])
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()


var zoom_to := 0.0


## The camera: a smooth zoom toward the target, arrows / WASD-free panning (the letter keys are the command card's),
## kept within reach of the island. web: page.html zoomAt / clampCam
func _camera(dt: float) -> void:
	if zoom_to > 0:
		var z := lerpf(cam.zoom.x, zoom_to, minf(1.0, dt * 12))
		var before := get_global_mouse_position()
		cam.zoom = Vector2(z, z)
		cam.position += before - get_global_mouse_position()
		if absf(z - zoom_to) < 0.0005:
			zoom_to = 0.0
	var pan := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if pan != Vector2.ZERO and not (get_viewport().gui_get_focus_owner() is LineEdit):
		cam.position += pan * 900.0 * dt / cam.zoom.x
	var b := map.bounds().grow(850)
	cam.position = cam.position.clamp(b.position, b.end)


func zoom_by(f: float) -> void:
	var lo := map.fit_zoom() * 0.6
	zoom_to = clampf((zoom_to if zoom_to > 0 else cam.zoom.x) * f, lo, 3.0)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and game:
		if ev.keycode == KEY_ESCAPE:
			if hud.dialog.visible:
				hud.dialog.pick("close")
			elif hud.armory.visible:
				hud.armory.close()
			elif hud.diplomacy.win.panel.visible:
				hud.diplomacy.close()
			elif hud.aim != null:
				hud.aim = null
			else:
				hud.toggle_menu()
			get_viewport().set_input_as_handled()
			return
		if ev.keycode == KEY_Y and not ev.ctrl_pressed:
			hud.diplomacy.toggle()
			get_viewport().set_input_as_handled()
			return
		if ev.keycode == KEY_G and not ev.ctrl_pressed:
			hud.armory.toggle()
			get_viewport().set_input_as_handled()
			return
		if ev.keycode == KEY_HOME:
			var P: Dictionary = game.G.provs[game.capital]
			cam.position = Vector2(P.ic[0], P.ic[1])
			return
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
			zoom_by(1.2)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			zoom_by(1 / 1.2)
		elif ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			if ev.pressed:
				dragging = true
				drag_moved = 0.0
			else:
				dragging = false
				if ev.button_index == MOUSE_BUTTON_LEFT and drag_moved < 6.0 and game and hud.aim != null:
					var tp := map.province_at(get_global_mouse_position())
					if tp >= 0:
						if hud.aim.spell == "fly":
							game.fly_army(hud.aim.unit, tp)
						elif hud.aim.spell == "shock":
							game.start_spell2(hud.aim.unit, "shock", tp)
						else:
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
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed and game and map.selected_unit != null and map.selected_unit.owner == Game.ME:
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
